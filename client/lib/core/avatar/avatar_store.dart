import 'package:hive_flutter/hive_flutter.dart';

class AvatarStore {
  static late Box _box;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox('avatars');
    _initialized = true;
  }

  static String? get ownAvatarBase64 => _box.get('own') as String?;
  static Future<void> setOwnAvatarBase64(String base64) => _box.put('own', base64);
  static Future<void> clearOwnAvatar() => _box.delete('own');

  static String? peerAvatarBase64(String userId) => _box.get('peer:$userId') as String?;
  static Future<void> setPeerAvatarBase64(String userId, String base64) => _box.put('peer:$userId', base64);

  static String? sharedHashFor(String peerUserId) => _box.get('shared_hash:$peerUserId') as String?;
  static Future<void> setSharedHashFor(String peerUserId, String hash) => _box.put('shared_hash:$peerUserId', hash);

  /// Full local state export/import for the LAN device-transfer feature —
  /// avatars are local-only (never touch the server), so they must travel
  /// with the rest of the clone snapshot to survive moving to a new device.
  static Map<String, dynamic> exportAll() {
    return {for (final key in _box.keys) key as String: _box.get(key)};
  }

  static Future<void> importAll(Map<String, dynamic> data) async {
    for (final entry in data.entries) {
      await _box.put(entry.key, entry.value);
    }
  }
}
