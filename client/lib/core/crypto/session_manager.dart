import 'dart:convert';
import 'dart:typed_data';

import '../network/api_client.dart';
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

  Future<void> _persistIdentity() async {
    final privBytes = await _identity!.keyPair.extractPrivateKeyBytes();
    await SecureStore.setBlob('identity_keypair', jsonEncode({
      'private': base64Encode(privBytes),
      'public': base64Encode(_identity!.publicKeyBytes),
    }));
  }

  Future<X25519KeyPair> _loadIdentityFromJson(Map<String, dynamic> json) async {

    return X25519KeyPairCodec.fromBytes(
      base64Decode(json['private'] as String),
      base64Decode(json['public'] as String),
    );
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

  bool hasSession(String conversationId) => _sessions.containsKey(conversationId);
}
