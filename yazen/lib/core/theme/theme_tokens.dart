import 'package:flutter/material.dart';

abstract final class ThemeSpacing {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
}

abstract final class ThemeRadii {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
  static const double xLarge = 20;
  static const double hero = 28;
}

abstract final class ThemeElevation {
  static const double flat = 0;
  static const double low = 1;
  static const double medium = 3;
  static const double high = 6;
}

enum EchoThemePreset {
  oledBlack('oled_black', 'OLED Black'),
  rgbRainbow('rgb_rainbow', 'RGB Rainbow'),
  crimsonRed('crimson_red', 'Crimson Red'),
  pureWhite('pure_white', 'Pure White');

  const EchoThemePreset(this.id, this.label);

  final String id;
  final String label;
}

@immutable
class ThemeTokens {
  const ThemeTokens({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.accent,
    required this.accentStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.divider,
    required this.isLight,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color accent;
  final Color accentStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color divider;
  final bool isLight;

  Color get glass => surface.withValues(alpha: isLight ? 0.72 : 0.58);
  Color get scrim =>
      isLight
          ? Colors.white.withValues(alpha: 0.42)
          : Colors.black.withValues(alpha: 0.28);

  static ThemeTokens fromPreset(EchoThemePreset preset) {
    switch (preset) {
      case EchoThemePreset.oledBlack:
        return const ThemeTokens(
          background: Color(0xFF121212),
          surface: Color(0xFF1C1C1E),
          surfaceElevated: Color(0xFF242426),
          surfaceMuted: Color(0xFF2C2C2E),
          accent: Color(0xFFB8A7FF),
          accentStrong: Color(0xFF7C5CFC),
          textPrimary: Color(0xFFF7F5FF),
          textSecondary: Color(0xFFA6A3B2),
          divider: Color(0xFF303035),
          isLight: false,
        );
      case EchoThemePreset.rgbRainbow:
        return const ThemeTokens(
          background: Color(0xFF090A10),
          surface: Color(0xFF15151D),
          surfaceElevated: Color(0xFF20202A),
          surfaceMuted: Color(0xFF2A2A36),
          accent: Color(0xFF8DF5FF),
          accentStrong: Color(0xFF9C70FF),
          textPrimary: Color(0xFFF7F8FF),
          textSecondary: Color(0xFFA9AFBD),
          divider: Color(0xFF303342),
          isLight: false,
        );
      case EchoThemePreset.crimsonRed:
        return const ThemeTokens(
          background: Color(0xFF120D0E),
          surface: Color(0xFF211517),
          surfaceElevated: Color(0xFF2D1C1F),
          surfaceMuted: Color(0xFF3A2529),
          accent: Color(0xFFFF9B9B),
          accentStrong: Color(0xFFE84A5F),
          textPrimary: Color(0xFFFFF4F4),
          textSecondary: Color(0xFFC6A9AD),
          divider: Color(0xFF4A2B30),
          isLight: false,
        );
      case EchoThemePreset.pureWhite:
        return const ThemeTokens(
          background: Color(0xFFF7F8FA),
          surface: Color(0xFFFFFFFF),
          surfaceElevated: Color(0xFFFFFFFF),
          surfaceMuted: Color(0xFFE9ECF2),
          accent: Color(0xFF5A46D6),
          accentStrong: Color(0xFF3D2AA8),
          textPrimary: Color(0xFF111318),
          textSecondary: Color(0xFF626977),
          divider: Color(0xFFD8DCE5),
          isLight: true,
        );
    }
  }
}
