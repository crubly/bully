import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

const defaultAccentColor = Color(0xFF5865F2);

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  late Box _box;
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  Color? _accentColor;
  List<Color>? _accentGradient;

  Color get accentColor => _accentGradient?.first ?? _accentColor ?? defaultAccentColor;
  List<Color>? get accentGradient => _accentGradient;

  Future<void> init() async {
    _box = await Hive.openBox('appearance');
    final stored = _box.get('theme_mode') as String?;
    _mode = switch (stored) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };

    final accentValue = _box.get('accent_color') as int?;
    if (accentValue != null) _accentColor = Color(accentValue);
    final gradientValues = (_box.get('accent_gradient') as List?)?.cast<int>();
    if (gradientValues != null && gradientValues.length == 2) {
      _accentGradient = gradientValues.map(Color.new).toList();
    }
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

  Future<void> setAccentColor(Color color) async {
    _accentColor = color;
    _accentGradient = null;
    await _box.put('accent_color', color.toARGB32());
    await _box.delete('accent_gradient');
    notifyListeners();
  }

  Future<void> setAccentGradient(Color start, Color end) async {
    _accentGradient = [start, end];
    await _box.put('accent_gradient', [start.toARGB32(), end.toARGB32()]);
    notifyListeners();
  }

  Future<void> resetAccent() async {
    _accentColor = null;
    _accentGradient = null;
    await _box.delete('accent_color');
    await _box.delete('accent_gradient');
    notifyListeners();
  }
}
