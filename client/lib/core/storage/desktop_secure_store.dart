import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

class DesktopSecureStore {
  static Uint8List? _key;
  static File? _dataFile;
  static Map<String, String> _cache = {};
  static bool _loaded = false;
  static Future<void>? _loading;
  static Future<void> _opChain = Future.value();

  static Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _opChain.then((_) => op());
    _opChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);

    final keyFile = File('${dir.path}/secure_store.key');
    if (await keyFile.exists()) {
      _key = base64Decode(await keyFile.readAsString());
    } else {
      final random = Random.secure();
      _key = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
      await keyFile.writeAsString(base64Encode(_key!));
      if (!Platform.isWindows) {
        try {
          await Process.run('chmod', ['600', keyFile.path]);
        } catch (_) {
        }
      }
    }

    _dataFile = File('${dir.path}/secure_store.enc');
    if (await _dataFile!.exists()) {
      try {
        final bytes = await _dataFile!.readAsBytes();
        if (bytes.isNotEmpty) {
          final aead = AesGcm.with256bits();
          final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
          final plaintext = await aead.decrypt(box, secretKey: SecretKey(_key!));
          _cache = Map<String, String>.from(jsonDecode(utf8.decode(plaintext)) as Map);
        }
      } catch (_) {
        _cache = {};
      }
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final aead = AesGcm.with256bits();
    final plaintext = utf8.encode(jsonEncode(_cache));
    final box = await aead.encrypt(plaintext, secretKey: SecretKey(_key!));
    await _dataFile!.writeAsBytes(box.concatenation());
  }

  static Future<void> write(String key, String value) => _serialized(() async {
        await _ensureLoaded();
        _cache[key] = value;
        await _persist();
      });

  static Future<String?> read(String key) => _serialized(() async {
        await _ensureLoaded();
        return _cache[key];
      });

  static Future<void> delete(String key) => _serialized(() async {
        await _ensureLoaded();
        _cache.remove(key);
        await _persist();
      });

  static Future<Map<String, String>> readAll() => _serialized(() async {
        await _ensureLoaded();
        return Map.from(_cache);
      });
}
