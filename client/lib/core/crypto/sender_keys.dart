import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SenderKeyState {
  Uint8List chainKey;
  int iteration;

  SenderKeyState(this.chainKey, this.iteration);

  static Future<SenderKeyState> generate() async {
    final random = SecretKeyData.random(length: 32);
    return SenderKeyState(Uint8List.fromList(await random.extractBytes()), 0);
  }

  Map<String, dynamic> toDistributionMessage() => {
        'chain_key': base64Encode(chainKey),
        'iteration': iteration,
      };

  static SenderKeyState fromDistributionMessage(Map<String, dynamic> map) =>
      SenderKeyState(base64Decode(map['chain_key'] as String), map['iteration'] as int);

  Future<({Uint8List messageKeyA, Uint8List messageKeyB})> _stepAndGetMessageKeys() async {
    final hmac = Hmac.sha256();
    final messageKeyA = await hmac.calculateMac(utf8.encode('message-a'), secretKey: SecretKey(chainKey));
    final messageKeyB = await hmac.calculateMac(utf8.encode('message-b'), secretKey: SecretKey(chainKey));
    final nextChain = await hmac.calculateMac(utf8.encode('chain'), secretKey: SecretKey(chainKey));
    chainKey = Uint8List.fromList(nextChain.bytes);
    iteration++;
    return (messageKeyA: Uint8List.fromList(messageKeyA.bytes), messageKeyB: Uint8List.fromList(messageKeyB.bytes));
  }
}

class GroupCiphertext {
  final int iteration;
  final Uint8List ciphertext;
  GroupCiphertext(this.iteration, this.ciphertext);
}

// Same cascade as the DM Double Ratchet: AES-256-GCM first, then the whole
// box wrapped again in ChaCha20-Poly1305 under an independently derived key.
class SenderKeyCipher {
  static Future<GroupCiphertext> encrypt(SenderKeyState state, Uint8List plaintext) async {
    final iteration = state.iteration;
    final keys = await state._stepAndGetMessageKeys();
    final innerBox = await AesGcm.with256bits().encrypt(plaintext, secretKey: SecretKey(keys.messageKeyA));
    final outerBox = await Chacha20.poly1305Aead().encrypt(innerBox.concatenation(), secretKey: SecretKey(keys.messageKeyB));
    return GroupCiphertext(iteration, Uint8List.fromList(outerBox.concatenation()));
  }

  static Future<Uint8List> decrypt(SenderKeyState state, int iteration, Uint8List ciphertext) async {
    while (state.iteration < iteration) {
      await state._stepAndGetMessageKeys();
    }
    final keys = await state._stepAndGetMessageKeys();
    final outerBox = SecretBox.fromConcatenation(ciphertext, nonceLength: 12, macLength: 16);
    final innerBytes = await Chacha20.poly1305Aead().decrypt(outerBox, secretKey: SecretKey(keys.messageKeyB));
    final innerBox = SecretBox.fromConcatenation(Uint8List.fromList(innerBytes), nonceLength: 12, macLength: 16);
    final plaintext = await AesGcm.with256bits().decrypt(innerBox, secretKey: SecretKey(keys.messageKeyA));
    return Uint8List.fromList(plaintext);
  }
}
