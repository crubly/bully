import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/kdf.dart';

/// Encrypted framing for the LAN device-transfer channel. The 32-char
/// pairing code shown on the source device and typed into the target
/// device is the ONLY secret here — it never touches the relay server, only
/// travels over this direct LAN connection (or better, is read by a human
/// off one screen and typed into the other). Wrong code -> AEAD decryption
/// fails -> connection is rejected, so this doubles as authentication.
class TransferCrypto {
  static const _fixedSalt = 'bully-device-transfer-v1';

  static Future<Uint8List> deriveKey(String pairingCode) =>
      PassphraseKdf.deriveBootstrapSecret(pairingCode, _fixedSalt);

  static Future<Uint8List> encryptFrame(Uint8List key, Map<String, dynamic> payload) async {
    final aead = AesGcm.with256bits();
    final plaintext = utf8.encode(jsonEncode(payload));
    final box = await aead.encrypt(plaintext, secretKey: SecretKey(key));
    return Uint8List.fromList(box.concatenation());
  }

  static Future<Map<String, dynamic>> decryptFrame(Uint8List key, Uint8List ciphertext) async {
    final aead = AesGcm.with256bits();
    final box = SecretBox.fromConcatenation(ciphertext, nonceLength: 12, macLength: 16);
    final plaintext = await aead.decrypt(box, secretKey: SecretKey(key));
    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  /// Writes a 4-byte big-endian length prefix followed by the frame bytes.
  static Future<void> writeFrame(Socket socket, Uint8List frame) async {
    final lengthPrefix = ByteData(4)..setUint32(0, frame.length, Endian.big);
    socket.add(lengthPrefix.buffer.asUint8List());
    socket.add(frame);
    await socket.flush();
  }

  /// Reads exactly one length-prefixed frame from a byte stream buffer,
  /// consuming from [buffer] and returning null if not enough data has
  /// arrived yet (caller should await more chunks and retry).
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
