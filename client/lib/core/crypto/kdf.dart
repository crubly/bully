import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Derives a bootstrap secret from the user-chosen chat passphrase.
///
/// This secret is NEVER sent to the server. It only seeds the initial
/// Double Ratchet handshake (see [RatchetSession.initFromBootstrap]); actual
/// message keys come from the ratchet's own KDF chains, so compromising this
/// passphrase later does not retroactively break forward secrecy once the
/// ratchet has advanced.
class PassphraseKdf {
  static final _argon2 = Argon2id(
    memory: 64 * 1024, // 64 MiB
    iterations: 3,
    parallelism: 2,
    hashLength: 32,
  );

  /// [salt] should be a stable, non-secret value shared by both peers, e.g.
  /// the conversation ID — it just needs to differ between conversations so
  /// the same passphrase reused across chats doesn't yield the same key.
  static Future<Uint8List> deriveBootstrapSecret(String passphrase, String salt) async {
    final nonce = _fixedNonce(salt);
    final secretKey = await _argon2.deriveKeyFromPassword(
      password: passphrase.trim(),
      nonce: nonce,
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  /// Argon2id needs a fixed-length nonce; derive 16 bytes deterministically
  /// from the salt string instead of requiring callers to pad it themselves.
  static List<int> _fixedNonce(String salt) {
    final hash = utf8.encode(salt);
    final out = List<int>.filled(16, 0);
    for (var i = 0; i < hash.length; i++) {
      out[i % 16] ^= hash[i];
    }
    return out;
  }
}
