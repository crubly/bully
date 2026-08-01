import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {

  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  static Future<void> setAuthToken(String nodeUrl, String token) => _storage.write(key: 'auth_token:$nodeUrl', value: token);
  static Future<String?> getAuthToken(String nodeUrl) => _storage.read(key: 'auth_token:$nodeUrl');
  static Future<void> clearAuthToken(String nodeUrl) => _storage.delete(key: 'auth_token:$nodeUrl');

  static Future<void> setUser(String nodeUrl, String userId, String username) async {
    await _storage.write(key: 'user_id:$nodeUrl', value: userId);
    await _storage.write(key: 'username:$nodeUrl', value: username);
  }

  static Future<String?> getUserId(String nodeUrl) => _storage.read(key: 'user_id:$nodeUrl');
  static Future<String?> getUsername(String nodeUrl) => _storage.read(key: 'username:$nodeUrl');

  static Future<void> setBlob(String key, String json) => _storage.write(key: 'blob:$key', value: json);
  static Future<String?> getBlob(String key) => _storage.read(key: 'blob:$key');
  static Future<void> deleteBlob(String key) => _storage.delete(key: 'blob:$key');

  static Future<Map<String, String>> exportAllBlobs() async {
    final all = await _storage.readAll();
    return {
      for (final entry in all.entries)
        if (entry.key.startsWith('blob:')) entry.key.substring('blob:'.length): entry.value
    };
  }

  static Future<void> importAllBlobs(Map<String, String> blobs) async {
    for (final entry in blobs.entries) {
      await _storage.write(key: 'blob:${entry.key}', value: entry.value);
    }
  }
}
