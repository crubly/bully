import 'dart:math';

class PairingCode {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generate() {
    final random = Random.secure();
    return List.generate(32, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
  }
}
