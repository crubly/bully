import 'package:flutter/material.dart';

class DiscordColors {
  static const blurple = Color(0xFF5865F2);
  static const bgPrimary = Color(0xFF313338);
  static const bgSecondary = Color(0xFF2B2D31);
  static const bgTertiary = Color(0xFF1E1F22);
  static const textNormal = Color(0xFFDBDEE1);
  static const textMuted = Color(0xFF949BA4);
  static const online = Color(0xFF23A559);
  static const danger = Color(0xFFDA373C);
}

ThemeData buildDiscordTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: DiscordColors.bgPrimary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: DiscordColors.blurple,
      brightness: Brightness.dark,
      surface: DiscordColors.bgPrimary,
      primary: DiscordColors.blurple,
    ),
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: DiscordColors.textNormal),
      bodySmall: TextStyle(color: DiscordColors.textMuted),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: DiscordColors.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: DiscordColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: DiscordColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: DiscordColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: DiscordColors.textNormal,
      iconColor: DiscordColors.textMuted,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: DiscordColors.bgTertiary,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: DiscordColors.blurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
}
