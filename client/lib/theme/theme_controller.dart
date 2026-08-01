import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  late Box _box;
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Future<void> init() async {
    _box = await Hive.openBox('appearance');
    final stored = _box.get('theme_mode') as String?;
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await _box.put('theme_mode', value);
    notifyListeners();
  }
}
