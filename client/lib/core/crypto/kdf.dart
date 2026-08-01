import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class PassphraseKdf {
  static final _argon2 = Argon2id(
    memory: 64 * 1024,
    iterations: 3,
    parallelism: 2,
    hashLength: 32,
  );

  static Future<Uint8List> deriveBootstrapSecret(String passphrase, String salt) async {
    final nonce = _fixedNonce(salt);
    final secretKey = await _argon2.deriveKeyFromPassword(
      password: passphrase.trim(),
      nonce: nonce,
    );
    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  static List<int> _fixedNonce(String salt) {
    final hash = utf8.encode(salt);
    final out = List<int>.filled(16, 0);
    for (var i = 0; i < hash.length; i++) {
      out[i % 16] ^= hash[i];
    }
    return out;
  }
}
