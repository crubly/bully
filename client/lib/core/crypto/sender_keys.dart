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

  Future<Uint8List> _stepAndGetMessageKey() async {
    final hmac = Hmac.sha256();
    final messageKey = await hmac.calculateMac(utf8.encode('message'), secretKey: SecretKey(chainKey));
    final nextChain = await hmac.calculateMac(utf8.encode('chain'), secretKey: SecretKey(chainKey));
    chainKey = Uint8List.fromList(nextChain.bytes);
    iteration++;
    return Uint8List.fromList(messageKey.bytes);
  }
}

class GroupCiphertext {
  final int iteration;
  final Uint8List ciphertext;
  GroupCiphertext(this.iteration, this.ciphertext);
}

class SenderKeyCipher {

  static Future<GroupCiphertext> encrypt(SenderKeyState state, Uint8List plaintext) async {
    final iteration = state.iteration;
    final key = await state._stepAndGetMessageKey();
    final aead = AesGcm.with256bits();
    final box = await aead.encrypt(plaintext, secretKey: SecretKey(key));
    return GroupCiphertext(iteration, Uint8List.fromList(box.concatenation()));
  }

  static Future<Uint8List> decrypt(SenderKeyState state, int iteration, Uint8List ciphertext) async {
    while (state.iteration < iteration) {
      await state._stepAndGetMessageKey();
    }
    final key = await state._stepAndGetMessageKey();
    final aead = AesGcm.with256bits();
    final box = SecretBox.fromConcatenation(ciphertext, nonceLength: 12, macLength: 16);
    final plaintext = await aead.decrypt(box, secretKey: SecretKey(key));
    return Uint8List.fromList(plaintext);
  }
}
