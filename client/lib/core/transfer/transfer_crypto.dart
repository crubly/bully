import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/kdf.dart';

class TransferCrypto {
  static const _fixedSalt = 'bully-device-transfer-v1';

  static Future<Uint8List> deriveKey(String pairingCode) =>
      PassphraseKdf.deriveBootstrapSecret(pairingCode, _fixedSalt);

  static Future<({Uint8List keyA, Uint8List keyB})> _splitKeys(Uint8List key) async {
    final hmac = Hmac.sha256();
    final a = await hmac.calculateMac(utf8.encode('transfer-a'), secretKey: SecretKey(key));
    final b = await hmac.calculateMac(utf8.encode('transfer-b'), secretKey: SecretKey(key));
    return (keyA: Uint8List.fromList(a.bytes), keyB: Uint8List.fromList(b.bytes));
  }

  // Cascade: AES-256-GCM first, then ChaCha20-Poly1305 over the result,
  // under an independently derived key — same defense-in-depth as chat
  // messages, since this key briefly authorizes a full account clone.
  static Future<Uint8List> encryptFrame(Uint8List key, Map<String, dynamic> payload) async {
    final keys = await _splitKeys(key);
    final plaintext = utf8.encode(jsonEncode(payload));
    final innerBox = await AesGcm.with256bits().encrypt(plaintext, secretKey: SecretKey(keys.keyA));
    final outerBox = await Chacha20.poly1305Aead().encrypt(innerBox.concatenation(), secretKey: SecretKey(keys.keyB));
    return Uint8List.fromList(outerBox.concatenation());
  }

  static Future<Map<String, dynamic>> decryptFrame(Uint8List key, Uint8List ciphertext) async {
    final keys = await _splitKeys(key);
    final outerBox = SecretBox.fromConcatenation(ciphertext, nonceLength: 12, macLength: 16);
    final innerBytes = await Chacha20.poly1305Aead().decrypt(outerBox, secretKey: SecretKey(keys.keyB));
    final innerBox = SecretBox.fromConcatenation(Uint8List.fromList(innerBytes), nonceLength: 12, macLength: 16);
    final plaintext = await AesGcm.with256bits().decrypt(innerBox, secretKey: SecretKey(keys.keyA));
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  static Future<void> writeFrame(Socket socket, Uint8List frame) async {
    final lengthPrefix = ByteData(4)..setUint32(0, frame.length, Endian.big);
    socket.add(lengthPrefix.buffer.asUint8List());
    socket.add(frame);
    await socket.flush();
  }

  static Uint8List? tryReadFrame(BytesBuilder buffer) {
    final bytes = buffer.toBytes();
    if (bytes.length < 4) return null;
    final length = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
    if (bytes.length < 4 + length) return null;
    final frame = bytes.sublist(4, 4 + length);
    buffer.clear();
    buffer.add(bytes.sublist(4 + length));
    return frame;
  }
}
