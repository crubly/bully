import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../network/api_client.dart';
import '../security/app_lock.dart';
import '../storage/secure_store.dart';
import 'double_ratchet.dart';
import 'kdf.dart';
import 'keys.dart';
import 'security/peer_identity_store.dart';

export 'security/peer_identity_store.dart' show PeerIdentityChangedException;

class CryptoSessionManager {
  final ApiClient api;
  X25519KeyPair? _identity;
  final Map<String, RatchetSession> _sessions = {};

  CryptoSessionManager(this.api);

  X25519KeyPair get identity => _identity!;

  Future<void> ensureIdentity() async {
    if (_identity != null) return;
    final stored = await SecureStore.getBlob('identity_keypair');
    if (stored != null) {
      final json = jsonDecode(stored) as Map<String, dynamic>;
      _identity = await _loadIdentityFromJson(json);
      return;
    }
    _identity = await X25519KeyPair.generate();
    await _persistIdentity();
    await api.uploadPrekeys({
      'signed_key_id': 1,
      'signed_public_key': base64Encode(_identity!.publicKeyBytes),
      'signature': '',
      'one_time_keys': [],
    });
  }

  // When the app lock is enabled, the identity private key is encrypted at
  // rest with a key derived from the lock password (via Argon2id) — that
  // password only unlocks access to the already-independently-generated
  // private key, it never forms the key itself. Without the app lock, the
  // key is stored plain in SecureStore (Keychain/Keystore on mobile, which
  // are already hardware-backed where the device supports it).
  Future<void> _persistIdentity() async {
    final privBytes = await _identity!.keyPair.extractPrivateKeyBytes();
    final publicB64 = base64Encode(_identity!.publicKeyBytes);
    if (AppLock.instance.enabled) {
      final key = AppLock.instance.lockKey;
      if (key == null) throw StateError('app lock enabled but not unlocked — cannot persist identity key');
      final box = await AesGcm.with256bits().encrypt(privBytes, secretKey: SecretKey(key));
      await SecureStore.setBlob('identity_keypair', jsonEncode({
        'wrapped': true,
        'private_enc': base64Encode(box.concatenation()),
        'public': publicB64,
      }));
    } else {
      await SecureStore.setBlob('identity_keypair', jsonEncode({
        'wrapped': false,
        'private': base64Encode(privBytes),
        'public': publicB64,
      }));
    }
  }

  Future<X25519KeyPair> _loadIdentityFromJson(Map<String, dynamic> json) async {
    final publicBytes = base64Decode(json['public'] as String);
    final wrapped = json['wrapped'] as bool? ?? false;
    if (!wrapped) {
      return X25519KeyPairCodec.fromBytes(base64Decode(json['private'] as String), publicBytes);
    }
    final key = AppLock.instance.lockKey;
    if (key == null) throw StateError('identity key is locked — unlock the app first');
    final box = SecretBox.fromConcatenation(base64Decode(json['private_enc'] as String), nonceLength: 12, macLength: 16);
    final privBytes = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(key));
    return X25519KeyPairCodec.fromBytes(Uint8List.fromList(privBytes), publicBytes);
  }

  /// Re-persists the identity key under the current app-lock state — call
  /// after enabling or disabling the lock so the on-disk wrapping matches.
  Future<void> rewrapIdentity() async {
    if (_identity == null) return;
    await _persistIdentity();
  }

  /// Explicitly re-pins a peer's identity key after the caller has shown
  /// the user a warning and they chose to trust it anyway.
  Future<void> trustNewPeerIdentity(String peerUserId, Uint8List peerPublicKey) =>
      PeerIdentityStore.trust(peerUserId, peerPublicKey);

  Future<void> startAsSender({
    required String conversationId,
    required String peerUserId,
    required String passphrase,
  }) async {
    await ensureIdentity();
    final bootstrapSecret = await PassphraseKdf.deriveBootstrapSecret(passphrase, conversationId);
    final bundle = await api.fetchKeyBundle(peerUserId);
    final peerPublicKey = base64Decode(bundle['signed_public_key'] as String);

    await PeerIdentityStore.checkOrPin(peerUserId, Uint8List.fromList(peerPublicKey));

    final session = await RatchetSession.initAsSender(
      bootstrapSecret: bootstrapSecret,
      peerPublicKey: Uint8List.fromList(peerPublicKey),
    );
    _sessions[conversationId] = session;
    await _persistSession(conversationId, session);
  }

  Future<void> prepareAsReceiver({
    required String conversationId,
    required String passphrase,
  }) async {
    await ensureIdentity();
    final bootstrapSecret = await PassphraseKdf.deriveBootstrapSecret(passphrase, conversationId);
    final session = await RatchetSession.initAsReceiver(
      bootstrapSecret: bootstrapSecret,
      myKeyPair: _identity!,
    );
    _sessions[conversationId] = session;
    await _persistSession(conversationId, session);
  }

  Future<RatchetSession> _loadOrThrow(String conversationId) async {
    final existing = _sessions[conversationId];
    if (existing != null) return existing;
    final stored = await SecureStore.getBlob('ratchet:$conversationId');
    if (stored == null) {
      throw StateError('no ratchet session for conversation $conversationId — set the chat passphrase first');
    }
    final session = await RatchetSession.fromJson(jsonDecode(stored) as Map<String, dynamic>);
    _sessions[conversationId] = session;
    return session;
  }

  Future<void> _persistSession(String conversationId, RatchetSession session) async {
    final json = await session.toJson();
    await SecureStore.setBlob('ratchet:$conversationId', jsonEncode(json));
  }

  Future<RatchetMessage> encrypt(String conversationId, String plaintext) async {
    final session = await _loadOrThrow(conversationId);
    final message = await session.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    await _persistSession(conversationId, session);
    return message;
  }

  Future<String> decrypt(String conversationId, Uint8List header, Uint8List ciphertext) async {
    final session = await _loadOrThrow(conversationId);
    final plaintext = await session.decrypt(header, ciphertext);
    await _persistSession(conversationId, session);
    return utf8.decode(plaintext);
  }

  /// Checks in-memory sessions first, then falls back to persisted storage
  /// — without this, every app restart looked like "no session yet" and
  /// re-running startAsSender/prepareAsReceiver silently overwrote the real
  /// session with a fresh one (new ephemeral keys), breaking decryption for
  /// whichever side didn't also get reset the same way.
  Future<bool> hasSession(String conversationId) async {
    if (_sessions.containsKey(conversationId)) return true;
    return (await SecureStore.getBlob('ratchet:$conversationId')) != null;
  }
}
