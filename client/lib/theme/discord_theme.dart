import 'package:flutter/material.dart';

/// Discord-inspired dark palette.
class DiscordColors {
  static const blurple = Color(0xFF5865F2);
  static const bgPrimary = Color(0xFF313338); // chat area
  static const bgSecondary = Color(0xFF2B2D31); // channel list
  static const bgTertiary = Color(0xFF1E1F22); // server rail
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
