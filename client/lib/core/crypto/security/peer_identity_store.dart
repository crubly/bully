import 'dart:convert';
import 'dart:typed_data';

import '../../storage/secure_store.dart';

// Thrown when a peer's long-term identity key no longer matches the one
// pinned the first time we ever talked to them (trust-on-first-use). A
// genuine key change happens when they reinstall/reset the app; an
// attacker-swapped key looks identical over the wire, which is exactly why
// this is checked automatically instead of relying on someone remembering
// to compare safety numbers every single time. Shared between DM sessions
// and group sender-key exchange sessions — same peer, same trust anchor.
class PeerIdentityChangedException implements Exception {
  final String peerUserId;
  PeerIdentityChangedException(this.peerUserId);
}

class PeerIdentityStore {
  static String _key(String peerUserId) => 'peer_identity:$peerUserId';
  static String _verifiedKey(String peerUserId) => 'peer_verified:$peerUserId';

  static Future<void> checkOrPin(String peerUserId, Uint8List peerPublicKey) async {
    final key = _key(peerUserId);
    final stored = await SecureStore.getBlob(key);
    final encoded = base64Encode(peerPublicKey);
    if (stored == null) {
      await SecureStore.setBlob(key, encoded);
      return;
    }
    if (stored != encoded) {
      throw PeerIdentityChangedException(peerUserId);
    }
  }

  static Future<void> trust(String peerUserId, Uint8List peerPublicKey) async {
    await SecureStore.setBlob(_key(peerUserId), base64Encode(peerPublicKey));
    // A key change always resets verification — the safety number must be
    // re-checked against whatever key is now trusted, never carried over.
    await SecureStore.deleteBlob(_verifiedKey(peerUserId));
  }

  /// True once the user has explicitly confirmed the safety number matches
  /// — this is the only thing that defeats an active key-exchange MITM,
  /// since even a node that mimics the protocol perfectly and silently
  /// logs everything only ever sees ciphertext once this check passes.
  static Future<bool> isVerified(String peerUserId) async => (await SecureStore.getBlob(_verifiedKey(peerUserId))) == '1';

  static Future<void> markVerified(String peerUserId) => SecureStore.setBlob(_verifiedKey(peerUserId), '1');
}
