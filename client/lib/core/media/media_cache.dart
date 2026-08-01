import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class MediaCache {
  static late Box _settings;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _settings = await Hive.openBox('media_settings');
    _initialized = true;
  }

  static bool get autoSaveEnabled => (_settings.get('auto_save') as bool?) ?? false;
  static Future<void> setAutoSaveEnabled(bool value) => _settings.put('auto_save', value);

  static int get autoDeleteAfterDays => (_settings.get('auto_delete_days') as int?) ?? 7;
  static Future<void> setAutoDeleteAfterDays(int days) => _settings.put('auto_delete_days', days);

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/media_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<int> sweep() async {
    if (autoDeleteAfterDays <= 0) return 0;
    final dir = await _cacheDir();
    final cutoff = DateTime.now().subtract(Duration(days: autoDeleteAfterDays));
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
        deleted++;
      }
    }
    return deleted;
  }

  static Future<int> currentCacheSizeBytes() async {
    final dir = await _cacheDir();
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }
}
