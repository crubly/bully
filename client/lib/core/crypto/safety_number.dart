import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class SafetyNumber {
  static Future<String> compute(Uint8List keyA, Uint8List keyB) async {
    final ordered = _compareBytes(keyA, keyB) <= 0 ? [...keyA, ...keyB] : [...keyB, ...keyA];
    final digest = await Sha256().hash(ordered);
    final bytes = digest.bytes;

    final groups = <String>[];
    for (var g = 0; g < 6; g++) {
      final offset = g * 4;
      final chunk = bytes.sublist(offset, offset + 4);
      final value = (chunk[0] << 24) | (chunk[1] << 16) | (chunk[2] << 8) | chunk[3];
      groups.add((value.abs() % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }

  static int _compareBytes(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
