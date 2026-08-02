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

  static const dark = BullyPalette._(
    bgPrimary: BullyColors.bgPrimary,
    bgSecondary: BullyColors.bgSecondary,
    bgTertiary: BullyColors.bgTertiary,
    textNormal: BullyColors.textNormal,
    textMuted: BullyColors.textMuted,
  );

  static const light = BullyPalette._(
    bgPrimary: BullyColors.bgPrimaryLight,
    bgSecondary: BullyColors.bgSecondaryLight,
    bgTertiary: BullyColors.bgTertiaryLight,
    textNormal: BullyColors.textNormalLight,
    textMuted: BullyColors.textMutedLight,
  );

  static BullyPalette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

const _radius = 12.0;

ThemeData buildBullyTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bgPrimary = dark ? BullyColors.bgPrimary : BullyColors.bgPrimaryLight;
  final bgSecondary = dark ? BullyColors.bgSecondary : BullyColors.bgSecondaryLight;
  final bgTertiary = dark ? BullyColors.bgTertiary : BullyColors.bgTertiaryLight;
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
