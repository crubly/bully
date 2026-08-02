import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_hash;

import '../crypto/session_manager.dart';
import '../network/ws_client.dart';
import 'avatar_store.dart';
import 'image_validator.dart';

/// Avatars are local-only: they never touch the relay server. An avatar is
/// shared, E2E encrypted, exactly like a chat message — one-to-one with
/// each DM contact you actually talk to (not broadcast to the whole
/// account), reusing that conversation's Double Ratchet session. Group
/// avatar sharing isn't in scope here (only DM contacts see your avatar).
class AvatarService {
  final WsClient ws;
  final CryptoSessionManager crypto;
  final _updates = StreamController<String>.broadcast();

  AvatarService(this.ws, this.crypto) {
    ws.messages.listen(_handle);
  }

  /// Fires with the peer's userId whenever their avatar is received/updated.
  Stream<String> get onPeerAvatarUpdated => _updates.stream;

  String _hashOf(String base64Data) => crypto_hash.sha256.convert(utf8.encode(base64Data)).toString();

  /// Throws with a human-readable reason if [bytes] doesn't decode as a
  /// real image — never accept unvalidated bytes as an avatar (see
  /// image_validator.dart for why).
  Future<void> setOwnAvatar(Uint8List bytes) async {
    final rejection = await ImageValidator.validate(bytes);
    if (rejection != null) throw StateError(rejection);
    await AvatarStore.setOwnAvatarBase64(base64Encode(bytes));
  }

  Future<void> clearOwnAvatar() => AvatarStore.clearOwnAvatar();

  Uint8List? ownAvatarBytes() {
    final b64 = AvatarStore.ownAvatarBase64;
    return b64 == null ? null : base64Decode(b64);
  }

  Uint8List? peerAvatarBytes(String userId) {
    final b64 = AvatarStore.peerAvatarBase64(userId);
    return b64 == null ? null : base64Decode(b64);
  }

  /// Sends the current avatar to one DM contact if they don't already have
  /// this exact version. Safe to call often (e.g. every time a chat opens)
  /// — it's a no-op once the peer is already up to date.
  Future<void> shareWithPeer({required String conversationId, required String peerUserId}) async {
    final own = AvatarStore.ownAvatarBase64;
    if (own == null) return;
    if (!(await crypto.hasSession(conversationId))) return;

    final hash = _hashOf(own);
    if (AvatarStore.sharedHashFor(peerUserId) == hash) return;

    final message = await crypto.encrypt(conversationId, jsonEncode({'avatar': own}));
    ws.send(RelayEnvelope(
      type: 'avatar',
      conversationId: conversationId,
      fromUserId: '',
      toUserId: peerUserId,
      ciphertext: base64Encode(message.ciphertext),
      header: base64Encode(message.header),
    ));
    await AvatarStore.setSharedHashFor(peerUserId, hash);
  }

  Future<void> _handle(RelayEnvelope env) async {
    if (env.type != 'avatar') return;
    try {
      final plaintext = await crypto.decrypt(env.conversationId, base64Decode(env.header!), base64Decode(env.ciphertext!));
      final map = jsonDecode(plaintext) as Map<String, dynamic>;
      final avatarB64 = map['avatar'] as String;
      final bytes = base64Decode(avatarB64);

      // A contact is still a semi-trusted but external input source — run
      // their avatar through the same decode validation before storing or
      // displaying it, exactly like our own upload.
      final rejection = await ImageValidator.validate(bytes);
      if (rejection != null) return;

      await AvatarStore.setPeerAvatarBase64(env.fromUserId, avatarB64);
      _updates.add(env.fromUserId);
    } catch (_) {
      // no ratchet session for this conversation yet, or malformed — drop
    }
  }
}
