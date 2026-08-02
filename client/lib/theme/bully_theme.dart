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

class _TintedBackgrounds {
  final Color bgPrimary;
  final Color bgSecondary;
  final Color bgTertiary;
  const _TintedBackgrounds(this.bgPrimary, this.bgSecondary, this.bgTertiary);
}

_TintedBackgrounds _backgroundsFor(Brightness brightness) {
  final hue = HSVColor.fromColor(ThemeController.instance.accentColor).hue;
  if (brightness == Brightness.dark) {
    return _TintedBackgrounds(_tinted(hue, 0.38, 0.22), _tinted(hue, 0.42, 0.19), _tinted(hue, 0.46, 0.135));
  }
  return _TintedBackgrounds(_tinted(hue, 0.12, 1.0), _tinted(hue, 0.16, 0.955), _tinted(hue, 0.2, 0.895));
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
    final bg = _backgroundsFor(dark ? Brightness.dark : Brightness.light);
    return BullyPalette._(
      bgPrimary: bg.bgPrimary,
      bgSecondary: bg.bgSecondary,
      bgTertiary: bg.bgTertiary,
      textNormal: dark ? BullyColors.textNormal : BullyColors.textNormalLight,
      textMuted: dark ? BullyColors.textMuted : BullyColors.textMutedLight,
    );
  }
}

const _radius = 12.0;

ThemeData buildBullyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = _backgroundsFor(brightness);
  final bgPrimary = bg.bgPrimary;
  final bgSecondary = bg.bgSecondary;
  final bgTertiary = bg.bgTertiary;
  final textNormal = dark ? BullyColors.textNormal : BullyColors.textNormalLight;
  final textMuted = dark ? BullyColors.textMuted : BullyColors.textMutedLight;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: bgPrimary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: BullyColors.blurple,
      brightness: brightness,
      surface: bgPrimary,
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
      backgroundColor: bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: bgSecondary,
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
