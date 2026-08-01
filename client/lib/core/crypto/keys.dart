import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class X25519KeyPair {
  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  X25519KeyPair._(this.keyPair, this.publicKeyBytes);

  static final _algorithm = X25519();

  static Future<X25519KeyPair> generate() async {
    final pair = await _algorithm.newKeyPair();
    final pub = await pair.extractPublicKey();
    return X25519KeyPair._(pair, Uint8List.fromList(pub.bytes));
  }

  static X25519KeyPair fromExisting(SimpleKeyPair keyPair, Uint8List publicKeyBytes) {
    return X25519KeyPair._(keyPair, publicKeyBytes);
  }

  static Future<Uint8List> sharedSecret({
    required SimpleKeyPair privateKey,
    required Uint8List peerPublicKeyBytes,
  }) async {
    final peerPublic = SimplePublicKey(peerPublicKeyBytes, type: KeyPairType.x25519);
    final shared = await _algorithm.sharedSecretKey(keyPair: privateKey, remotePublicKey: peerPublic);
    return Uint8List.fromList(await shared.extractBytes());
  }
}

class X25519KeyPairCodec {
  static X25519KeyPair fromBytes(Uint8List privateKeyBytes, Uint8List publicKeyBytes) {
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    return X25519KeyPair.fromExisting(keyPair, publicKeyBytes);
  }
}
