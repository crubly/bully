import 'dart:math';

/// A one-time, human-typeable 32-character code (uppercase letters + digits,
/// ambiguous characters like 0/O/1/I excluded) authenticating a single LAN
/// device-transfer session.
class PairingCode {
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String generate() {
    final random = Random.secure();
    return List.generate(32, (_) => _alphabet[random.nextInt(_alphabet.length)]).join();
  }
}
