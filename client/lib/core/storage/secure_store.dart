import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local-only storage for the account auth token and all ratchet/sender-key
/// state. Nothing in here is ever sent to the server.
///
/// Auth/account identity is namespaced by node URL: each node is an
/// independent server (not a federated pool), so a token issued by one node
/// must never be replayed against another.
class SecureStore {
  static const _storage = FlutterSecureStorage();

  static Future<void> setAuthToken(String nodeUrl, String token) => _storage.write(key: 'auth_token:$nodeUrl', value: token);
  static Future<String?> getAuthToken(String nodeUrl) => _storage.read(key: 'auth_token:$nodeUrl');
  static Future<void> clearAuthToken(String nodeUrl) => _storage.delete(key: 'auth_token:$nodeUrl');

  static Future<void> setUser(String nodeUrl, String userId, String username) async {
    await _storage.write(key: 'user_id:$nodeUrl', value: userId);
    await _storage.write(key: 'username:$nodeUrl', value: username);
  }

  static Future<String?> getUserId(String nodeUrl) => _storage.read(key: 'user_id:$nodeUrl');
  static Future<String?> getUsername(String nodeUrl) => _storage.read(key: 'username:$nodeUrl');

  /// Ratchet/sender-key state is serialized to JSON by the calling code and
  /// stored under a conversation- or member-scoped key.
  static Future<void> setBlob(String key, String json) => _storage.write(key: 'blob:$key', value: json);
  static Future<String?> getBlob(String key) => _storage.read(key: 'blob:$key');
  static Future<void> deleteBlob(String key) => _storage.delete(key: 'blob:$key');

  /// All crypto-state blobs (identity keypair, DM ratchets, group Sender
  /// Key sessions), keyed without the `blob:` prefix — used by the LAN
  /// device-transfer feature to clone a device's full crypto state.
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
