import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Settings + lifecycle for locally-cached media (photos/videos received in
/// chats). NOTE: this build doesn't yet implement sending/receiving media
/// messages — text chat only — so these settings and the sweep below have
/// nothing to act on until that lands. The infrastructure is real and
/// wired up so media support can hook into it directly.
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

  /// 0 means "never auto-delete".
  static int get autoDeleteAfterDays => (_settings.get('auto_delete_days') as int?) ?? 7;
  static Future<void> setAutoDeleteAfterDays(int days) => _settings.put('auto_delete_days', days);

  static Future<Directory> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/media_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Deletes cached media files older than [autoDeleteAfterDays] from the
  /// APP's own cache directory. This can never reach files the user chose
  /// to save to their OS photo library / Downloads — once media leaves the
  /// app's sandbox that way, only the user can delete it from there.
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
