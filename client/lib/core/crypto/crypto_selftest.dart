import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'double_ratchet.dart';
import 'kdf.dart';
import 'keys.dart';

class CryptoSelfTestFailure implements Exception {
  final String reason;
  CryptoSelfTestFailure(this.reason);
  @override
  String toString() => 'CryptoSelfTestFailure: $reason';
}

class CryptoSelfTest {
  static Future<void> runOrThrow() async {
    await _x25519RoundTrip();
    await _hkdfDeterminism();
    await _aesGcmRoundTrip();
    await _argon2idRoundTrip();
    await _doubleRatchetRoundTrip();
  }

  static Future<void> _x25519RoundTrip() async {
    final alice = await X25519KeyPair.generate();
    final bob = await X25519KeyPair.generate();
    final aliceShared = await X25519KeyPair.sharedSecret(privateKey: alice.keyPair, peerPublicKeyBytes: bob.publicKeyBytes);
    final bobShared = await X25519KeyPair.sharedSecret(privateKey: bob.keyPair, peerPublicKeyBytes: alice.publicKeyBytes);
    if (!_bytesEqual(aliceShared, bobShared)) {
      throw CryptoSelfTestFailure('X25519 ECDH shared secrets do not match');
    }
  }

  static Future<void> _hkdfDeterminism() async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final secret = SecretKey(List.filled(32, 7));
    final a = await hkdf.deriveKey(secretKey: secret, nonce: utf8.encode('n'), info: utf8.encode('info-a'));
    final b = await hkdf.deriveKey(secretKey: secret, nonce: utf8.encode('n'), info: utf8.encode('info-a'));
    final c = await hkdf.deriveKey(secretKey: secret, nonce: utf8.encode('n'), info: utf8.encode('info-b'));
    final aBytes = await a.extractBytes();
    final bBytes = await b.extractBytes();
    final cBytes = await c.extractBytes();
    if (!_bytesEqual(Uint8List.fromList(aBytes), Uint8List.fromList(bBytes))) {
      throw CryptoSelfTestFailure('HKDF is not deterministic for identical inputs');
    }
    if (_bytesEqual(Uint8List.fromList(aBytes), Uint8List.fromList(cBytes))) {
      throw CryptoSelfTestFailure('HKDF produced identical output for different info strings');
    }
  }

  static Future<void> _aesGcmRoundTrip() async {
    final aead = AesGcm.with256bits();
    final key = SecretKey(List.filled(32, 3));
    final plaintext = utf8.encode('bully-crypto-selftest');
    final aad = utf8.encode('aad');
    final box = await aead.encrypt(plaintext, secretKey: key, aad: aad);
    final decrypted = await aead.decrypt(box, secretKey: key, aad: aad);
    if (!_bytesEqual(Uint8List.fromList(decrypted), Uint8List.fromList(plaintext))) {
      throw CryptoSelfTestFailure('AES-256-GCM round-trip did not recover plaintext');
    }

    final tampered = SecretBox(
      box.cipherText,
      nonce: box.nonce,
      mac: Mac(box.mac.bytes.map((b) => b ^ 0xFF).toList()),
    );
    var rejectedTampering = false;
    try {
      await aead.decrypt(tampered, secretKey: key, aad: aad);
    } catch (_) {
      rejectedTampering = true;
    }
    if (!rejectedTampering) {
      throw CryptoSelfTestFailure('AES-256-GCM accepted a tampered ciphertext');
    }
  }

  static Future<void> _argon2idRoundTrip() async {
    final a = await PassphraseKdf.deriveBootstrapSecret('correct horse battery staple', 'salt-a');
    final b = await PassphraseKdf.deriveBootstrapSecret('correct horse battery staple', 'salt-a');
    final c = await PassphraseKdf.deriveBootstrapSecret('wrong horse', 'salt-a');
    if (!_bytesEqual(a, b)) {
      throw CryptoSelfTestFailure('Argon2id is not deterministic for identical inputs');
    }
    if (_bytesEqual(a, c)) {
      throw CryptoSelfTestFailure('Argon2id produced identical output for different passphrases');
    }
  }

  static Future<void> _doubleRatchetRoundTrip() async {
    final bootstrapSecret = Uint8List.fromList(List.filled(32, 9));
    final receiverKeyPair = await X25519KeyPair.generate();

    final sender = await RatchetSession.initAsSender(
      bootstrapSecret: bootstrapSecret,
      peerPublicKey: receiverKeyPair.publicKeyBytes,
    );
    final receiver = await RatchetSession.initAsReceiver(
      bootstrapSecret: bootstrapSecret,
      myKeyPair: receiverKeyPair,
    );

    final plaintext = Uint8List.fromList(utf8.encode('bully-double-ratchet-selftest'));
    final message = await sender.encrypt(plaintext);
    final decrypted = await receiver.decrypt(message.header, message.ciphertext);
    if (!_bytesEqual(decrypted, plaintext)) {
      throw CryptoSelfTestFailure('Double Ratchet round-trip did not recover plaintext');
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
