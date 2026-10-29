import 'package:flutter/material.dart';

/// Palet warna Swavina (setara konstanta warna di versi Expo).
class AppColors {
  AppColors(this.isDark);

  final bool isDark;

  factory AppColors.of(BuildContext context) =>
      AppColors(Theme.of(context).brightness == Brightness.dark);

  static const accent = Color(0xFFC35423);
  static const success = Color(0xFF28A745);
  static const danger = Color(0xFFDC3545);
  static const deleteRed = Color(0xFFE53935);
  static const warning = Color(0xFFFFA726);
  static const vibration = Color(0xFF4B5FA5);
  static const durationGreen = Color(0xFF4B9F4A);

  Color get textPrimary => isDark ? Colors.white : Colors.black;
  Color get textSecondary =>
      isDark ? const Color(0xFFCCCCCC) : const Color(0xFF555555);
  Color get card => isDark ? const Color(0xFF1C1C1E) : Colors.white;
  Color get cardAlt => isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF2F2F2);
  Color get pageBg => isDark ? Colors.black : const Color(0xFFF8F8F8);
  Color get progressBg => isDark ? const Color(0xFF333333) : const Color(0xFFEEEEEE);
  Color get sliderTrack => isDark ? const Color(0xFF444444) : const Color(0xFFEEEEEE);
  Color get border => isDark ? const Color(0xFF333333) : const Color(0xFFDDDDDD);
  Color get headerBg =>
      isDark ? const Color(0xFF47361D) : const Color(0xFFDCC0A1);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: dark ? Colors.black : const Color(0xFFF8F8F8),
  );
}
