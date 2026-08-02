import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

const defaultAccentColor = Color(0xFF5865F2);

class AccentPoint {
  final Offset position;
  final Color color;
  const AccentPoint(this.position, this.color);

  Map<String, dynamic> toMap() => {'x': position.dx, 'y': position.dy, 'color': color.toARGB32()};

  static AccentPoint fromMap(Map map) => AccentPoint(
        Offset((map['x'] as num).toDouble(), (map['y'] as num).toDouble()),
        Color(map['color'] as int),
      );
}

class AccentPreset {
  final String name;
  final Color? color;
  final List<AccentPoint>? gradient;
  const AccentPreset.solid(this.name, this.color) : gradient = null;
  const AccentPreset.gradient(this.name, this.gradient) : color = null;
}

const accentPresets = [
  AccentPreset.solid('Bully', defaultAccentColor),
  AccentPreset.solid('Розовый', Color(0xFFEB459E)),
  AccentPreset.solid('Изумруд', Color(0xFF23A559)),
  AccentPreset.gradient('Закат', [
    AccentPoint(Offset(0, 0), Color(0xFFF0B232)),
    AccentPoint(Offset(0.5, 0.5), Color(0xFFEB459E)),
    AccentPoint(Offset(1, 1), Color(0xFF5865F2)),
  ]),
  AccentPreset.gradient('Океан', [
    AccentPoint(Offset(0, 0), Color(0xFF00A8FC)),
    AccentPoint(Offset(0.5, 0.5), Color(0xFF2B7DE9)),
    AccentPoint(Offset(1, 1), Color(0xFF1E1F5C)),
  ]),
  AccentPreset.gradient('Лес', [
    AccentPoint(Offset(0, 0), Color(0xFF9BC53D)),
    AccentPoint(Offset(0.5, 0.5), Color(0xFF23A559)),
    AccentPoint(Offset(1, 1), Color(0xFF14532D)),
  ]),
];

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  late Box _box;
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  // Акцентный цвет: solid color for buttons/icons/highlights. Independent
  // from the theme gradient below — setting one never touches the other.
  Color? _accentColor;
  Color get accentColor => _accentColor ?? defaultAccentColor;

  // Тема: gradient OR image/gif OR video that tints/fills the whole
  // messenger's background surfaces as ONE shared backdrop. Only one of the
  // three is active at a time. Independent from the accent color above.
  List<AccentPoint>? _themeGradient;
  List<AccentPoint>? get themeGradient => _themeGradient;

  String? _backgroundImagePath;
  String? get backgroundImagePath => _backgroundImagePath;

  String? _backgroundVideoPath;
  String? get backgroundVideoPath => _backgroundVideoPath;

  bool get hasCustomBackground => _themeGradient != null || _backgroundImagePath != null || _backgroundVideoPath != null;
  bool get hasMediaBackground => _backgroundImagePath != null || _backgroundVideoPath != null;

  // Only meaningful for the image/gif/video backdrop — blur sigma (0 = off,
  // up to 40) and darkening scrim opacity (0..1), both user-adjustable.
  double _mediaBlur = 0;
  double get mediaBlur => _mediaBlur;

  double _mediaDarken = 0.35;
  double get mediaDarken => _mediaDarken;

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
    final gradientRaw = (_box.get('theme_gradient_points') as List?)?.cast<Map>();
    if (gradientRaw != null && gradientRaw.length >= 2) {
      _themeGradient = gradientRaw.map(AccentPoint.fromMap).toList();
    }
    _backgroundImagePath = _box.get('background_image_path') as String?;
    _backgroundVideoPath = _box.get('background_video_path') as String?;
    _mediaBlur = (_box.get('media_blur') as num?)?.toDouble() ?? 0;
    _mediaDarken = (_box.get('media_darken') as num?)?.toDouble() ?? 0.35;
  }

  Future<void> setMediaBlur(double sigma) async {
    _mediaBlur = sigma;
    await _box.put('media_blur', sigma);
    notifyListeners();
  }

  Future<void> setMediaDarken(double alpha) async {
    _mediaDarken = alpha;
    await _box.put('media_darken', alpha);
    notifyListeners();
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
    await _box.put('accent_color', color.toARGB32());
    notifyListeners();
  }

  Future<void> resetAccentColor() async {
    _accentColor = null;
    await _box.delete('accent_color');
    notifyListeners();
  }

  Future<void> setThemeGradientPoints(List<AccentPoint> points) async {
    _themeGradient = points;
    _backgroundImagePath = null;
    _backgroundVideoPath = null;
    await _box.put('theme_gradient_points', points.map((p) => p.toMap()).toList());
    await _box.delete('background_image_path');
    await _box.delete('background_video_path');
    notifyListeners();
  }

  Future<void> setBackgroundImage(String path) async {
    _backgroundImagePath = path;
    _backgroundVideoPath = null;
    _themeGradient = null;
    await _box.put('background_image_path', path);
    await _box.delete('background_video_path');
    await _box.delete('theme_gradient_points');
    notifyListeners();
  }

  Future<void> setBackgroundVideo(String path) async {
    _backgroundVideoPath = path;
    _backgroundImagePath = null;
    _themeGradient = null;
    await _box.put('background_video_path', path);
    await _box.delete('background_image_path');
    await _box.delete('theme_gradient_points');
    notifyListeners();
  }

  Future<void> resetThemeGradient() async {
    _themeGradient = null;
    _backgroundImagePath = null;
    _backgroundVideoPath = null;
    await _box.delete('theme_gradient_points');
    await _box.delete('background_image_path');
    await _box.delete('background_video_path');
    notifyListeners();
  }

  Future<void> applyPreset(AccentPreset preset) async {
    if (preset.gradient != null) {
      await setThemeGradientPoints(preset.gradient!);
    } else {
      await setAccentColor(preset.color!);
      await resetThemeGradient();
    }
  }
}
