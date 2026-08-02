import 'package:flutter/material.dart';

import 'theme_controller.dart';

class BullyColors {
  static Color get blurple => ThemeController.instance.accentColor;
  static const bgPrimary = Color(0xFF313338);
  static const bgSecondary = Color(0xFF2B2D31);
  static const bgTertiary = Color(0xFF1E1F22);
  static const textNormal = Color(0xFFDBDEE1);
  static const textMuted = Color(0xFF949BA4);
  static const online = Color(0xFF23A559);
  static const danger = Color(0xFFDA373C);

  static const bgPrimaryLight = Color(0xFFFFFFFF);
  static const bgSecondaryLight = Color(0xFFF2F3F5);
  static const bgTertiaryLight = Color(0xFFE3E5E8);
  static const textNormalLight = Color(0xFF060607);
  static const textMutedLight = Color(0xFF5C5E66);
}

Color _tinted(double hue, double saturation, double value) => HSVColor.fromAHSV(1, hue, saturation, value).toColor();

Color? _themeBlend() {
  final points = ThemeController.instance.themeGradient;
  if (points == null || points.isEmpty) return null;
  double r = 0, g = 0, b = 0;
  for (final p in points) {
    r += p.color.r;
    g += p.color.g;
    b += p.color.b;
  }
  final n = points.length;
  return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
}

/// Solid tinted color used ONLY for modal overlays (dialogs/popup menus) —
/// those need to stand out against the shared backdrop, so they never go
/// transparent even when a custom background is active.
Color _modalSurface(Brightness brightness) {
  final blend = _themeBlend();
  final dark = brightness == Brightness.dark;
  if (blend == null) return dark ? BullyColors.bgSecondary : BullyColors.bgSecondaryLight;
  final hsv = HSVColor.fromColor(blend);
  return _tinted(hsv.hue, dark ? hsv.saturation : hsv.saturation * 0.6, dark ? 0.20 : 0.955);
}

class BullyPalette {
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  final Color textNormal;
  final Color textMuted;

  const BullyPalette._({
    required this.bgPrimary,
    required this.bgSecondary,
    required this.bgTertiary,
    required this.textNormal,
    required this.textMuted,
  });

  static BullyPalette of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final custom = ThemeController.instance.hasCustomBackground;
    final defaults = dark
        ? const (bgPrimary: BullyColors.bgPrimary, bgSecondary: BullyColors.bgSecondary, bgTertiary: BullyColors.bgTertiary)
        : const (bgPrimary: BullyColors.bgPrimaryLight, bgSecondary: BullyColors.bgSecondaryLight, bgTertiary: BullyColors.bgTertiaryLight);
    return BullyPalette._(
      bgPrimary: custom ? Colors.transparent : defaults.bgPrimary,
      bgSecondary: custom ? Colors.transparent : defaults.bgSecondary,
      bgTertiary: custom ? Colors.transparent : defaults.bgTertiary,
      textNormal: dark ? BullyColors.textNormal : BullyColors.textNormalLight,
      textMuted: dark ? BullyColors.textMuted : BullyColors.textMutedLight,
    );
  }
}

const _radius = 12.0;

ThemeData buildBullyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final custom = ThemeController.instance.hasCustomBackground;
  final bgPrimary = custom ? Colors.transparent : (dark ? BullyColors.bgPrimary : BullyColors.bgPrimaryLight);
  final bgSecondary = custom ? Colors.transparent : (dark ? BullyColors.bgSecondary : BullyColors.bgSecondaryLight);
  final bgTertiary = custom ? Colors.transparent : (dark ? BullyColors.bgTertiary : BullyColors.bgTertiaryLight);
  final modalSurface = _modalSurface(brightness);
  final textNormal = dark ? BullyColors.textNormal : BullyColors.textNormalLight;
  final textMuted = dark ? BullyColors.textMuted : BullyColors.textMutedLight;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: bgPrimary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BullyColors.blurple,
      brightness: brightness,
      surface: modalSurface,
      primary: BullyColors.blurple,
    ),
    fontFamily: 'Roboto',
    textTheme: TextTheme(
      bodyMedium: TextStyle(color: textNormal),
      bodySmall: TextStyle(color: textMuted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: bgSecondary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: modalSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: modalSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),
    listTileTheme: ListTileThemeData(
      textColor: textNormal,
      iconColor: textMuted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: bgTertiary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(_radius), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: BullyColors.blurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textNormal,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
    ),
  );
}
