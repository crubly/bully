import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_hash;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../crypto/kdf.dart';

enum AutoLockDuration {
  immediately(0, 'Сразу'),
  oneMinute(1, '1 минута'),
  fiveMinutes(5, '5 минут'),
  fifteenMinutes(15, '15 минут'),
  thirtyMinutes(30, '30 минут'),
  never(-1, 'Никогда');

  final int minutes;
  final String label;
  const AutoLockDuration(this.minutes, this.label);

  static AutoLockDuration fromMinutes(int minutes) =>
      AutoLockDuration.values.firstWhere((d) => d.minutes == minutes, orElse: () => AutoLockDuration.fiveMinutes);
}

/// Local app-lock. The password derives a wrapping key (via Argon2id) used
/// to encrypt the identity private key and other sensitive blobs at rest —
/// the password never forms the private key directly, it only unlocks
/// access to it. Only a verifier hash of the wrapping key is persisted,
/// never the key itself; the real wrapping key lives in memory only while
/// unlocked and is discarded on lock.
class AppLock extends ChangeNotifier {
  static final AppLock instance = AppLock._();
  AppLock._();

  late Box _box;
  bool _enabled = false;
  int _autoLockMinutes = 5;
  bool _locked = false;
  Uint8List? _lockKey;
  DateTime _lastActivity = DateTime.now();
  Timer? _autoLockTimer;

  bool get enabled => _enabled;
  AutoLockDuration get autoLock => AutoLockDuration.fromMinutes(_autoLockMinutes);
  bool get locked => _locked;
  Uint8List? get lockKey => _lockKey;

  Future<void> init() async {
    _box = await Hive.openBox('app_lock');
    _enabled = (_box.get('enabled') as bool?) ?? false;
    _autoLockMinutes = (_box.get('auto_lock_minutes') as int?) ?? 5;
    _locked = _enabled;
    _startAutoLockTimer();
  }

  void _startAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkAutoLock());
  }

  void _checkAutoLock() {
    if (!_enabled || _locked) return;
    final duration = autoLock;
    if (duration == AutoLockDuration.never) return;
    final elapsedMinutes = DateTime.now().difference(_lastActivity).inMinutes;
    if (elapsedMinutes >= duration.minutes) lockNow();
  }

  void recordActivity() {
    _lastActivity = DateTime.now();
  }

  Future<Uint8List> _deriveKey(String password, String saltB64) async {
    final bytes = await PassphraseKdf.deriveBootstrapSecret(password, 'app-lock:$saltB64');
    return bytes;
  }

  String _verifierOf(Uint8List key) => crypto_hash.sha256.convert(key).toString();

  Future<void> setup(String password, AutoLockDuration autoLockDuration) async {
    final saltBytes = Uint8List.fromList(List.generate(16, (_) => Random.secure().nextInt(256)));
    final salt = base64Encode(saltBytes);
    final key = await _deriveKey(password, salt);
    await _box.put('salt', salt);
    await _box.put('verifier', _verifierOf(key));
    await _box.put('enabled', true);
    await _box.put('auto_lock_minutes', autoLockDuration.minutes);
    _enabled = true;
    _autoLockMinutes = autoLockDuration.minutes;
    _lockKey = key;
    _locked = false;
    recordActivity();
    notifyListeners();
  }

  Future<void> setAutoLock(AutoLockDuration duration) async {
    _autoLockMinutes = duration.minutes;
    await _box.put('auto_lock_minutes', duration.minutes);
    notifyListeners();
  }

  Future<bool> unlock(String password) async {
    final salt = _box.get('salt') as String?;
    final verifier = _box.get('verifier') as String?;
    if (salt == null || verifier == null) return false;
    final key = await _deriveKey(password, salt);
    if (_verifierOf(key) != verifier) return false;
    _lockKey = key;
    _locked = false;
    recordActivity();
    notifyListeners();
    return true;
  }

  void lockNow() {
    if (!_enabled) return;
    _lockKey = null;
    _locked = true;
    notifyListeners();
  }

  /// Changes the password once already unlocked (caller must have verified
  /// the current password first, e.g. via [unlock]). Re-derives a fresh
  /// wrapping key from the new password; callers must re-wrap any blobs
  /// encrypted under the old key afterward.
  Future<void> changePassword(String newPassword) async {
    final saltBytes = Uint8List.fromList(List.generate(16, (_) => Random.secure().nextInt(256)));
    final salt = base64Encode(saltBytes);
    final key = await _deriveKey(newPassword, salt);
    await _box.put('salt', salt);
    await _box.put('verifier', _verifierOf(key));
    _lockKey = key;
    notifyListeners();
  }

  /// Disables the lock after confirming the password — callers are
  /// responsible for re-encrypting any wrapped blobs back to unwrapped
  /// storage before/after calling this.
  Future<bool> disable(String password) async {
    final ok = await unlock(password);
    if (!ok) return false;
    await _box.delete('salt');
    await _box.delete('verifier');
    await _box.put('enabled', false);
    _enabled = false;
    _locked = false;
    _lockKey = null;
    notifyListeners();
    return true;
  }
}
