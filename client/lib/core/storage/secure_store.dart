import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../desktop_window.dart';
import 'desktop_secure_store.dart';

class SecureStore {
  static const _storage = FlutterSecureStorage();
  static bool get _useDesktopStore => DesktopWindow.isDesktop;

  static Future<void> _write(String key, String value) =>
      _useDesktopStore ? DesktopSecureStore.write(key, value) : _storage.write(key: key, value: value);
  static Future<String?> _read(String key) => _useDesktopStore ? DesktopSecureStore.read(key) : _storage.read(key: key);
  static Future<void> _delete(String key) => _useDesktopStore ? DesktopSecureStore.delete(key) : _storage.delete(key: key);
  static Future<Map<String, String>> _readAll() => _useDesktopStore ? DesktopSecureStore.readAll() : _storage.readAll();

  static Future<void> setAuthToken(String nodeUrl, String token) => _write('auth_token:$nodeUrl', token);
  static Future<String?> getAuthToken(String nodeUrl) => _read('auth_token:$nodeUrl');
  static Future<void> clearAuthToken(String nodeUrl) => _delete('auth_token:$nodeUrl');

  static Future<void> setUser(String nodeUrl, String userId, String username) async {
    await _write('user_id:$nodeUrl', userId);
    await _write('username:$nodeUrl', username);
  }

  static Future<String?> getUserId(String nodeUrl) => _read('user_id:$nodeUrl');
  static Future<String?> getUsername(String nodeUrl) => _read('username:$nodeUrl');

  static Future<void> setBlob(String key, String json) => _write('blob:$key', json);
  static Future<String?> getBlob(String key) => _read('blob:$key');
  static Future<void> deleteBlob(String key) => _delete('blob:$key');

  static Future<Map<String, String>> exportAllBlobs() async {
    final all = await _readAll();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith('blob:')) entry.key.substring('blob:'.length): entry.value
    };
  }

  static Future<void> importAllBlobs(Map<String, String> blobs) async {
    for (final entry in blobs.entries) {
      await _write('blob:${entry.key}', entry.value);
    }
  }
}
