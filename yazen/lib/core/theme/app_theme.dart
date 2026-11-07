import 'package:flutter/material.dart';

import 'theme_tokens.dart';

abstract final class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF242426);
  static const surfaceMuted = Color(0xFF2C2C2E);
  static const accent = Color(0xFFB8A7FF);
  static const accentStrong = Color(0xFF7C5CFC);
  static const textPrimary = Color(0xFFF7F5FF);
  static const textSecondary = Color(0xFFA6A3B2);
  static const divider = Color(0xFF303035);
}

ThemeData buildAppTheme({ThemeTokens? tokens}) {
  final palette = tokens ?? ThemeTokens.fromPreset(EchoThemePreset.oledBlack);
  final base =
      palette.isLight
          ? ThemeData.light(useMaterial3: true)
          : ThemeData.dark(useMaterial3: true);
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accentStrong,
    brightness: palette.isLight ? Brightness.light : Brightness.dark,
  ).copyWith(
    surface: palette.surface,
    surfaceContainerLowest: palette.background,
    surfaceContainerLow: palette.surface,
    surfaceContainer: palette.surfaceElevated,
    surfaceContainerHigh: palette.surfaceMuted,
    surfaceContainerHighest: palette.surfaceMuted,
    primary: palette.accent,
    secondary: palette.accentStrong,
    onSurface: palette.textPrimary,
    onSurfaceVariant: palette.textSecondary,
    onPrimary: palette.isLight ? Colors.white : Colors.black,
    outline: palette.divider,
  );

  final type = base.textTheme.apply(
    bodyColor: palette.textPrimary,
    displayColor: palette.textPrimary,
    fontFamily: 'Plus Jakarta Sans',
  );
  final refinedType = type.copyWith(
    displayLarge: type.displayLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -2.0,
    ),
    displayMedium: type.displayMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
    ),
    headlineLarge: type.headlineLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.3,
    ),
    headlineMedium: type.headlineMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.0,
    ),
    titleLarge: type.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.35,
    ),
    titleMedium: type.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.15,
    ),
    labelLarge: type.labelLarge?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.05,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    colorScheme: scheme,
    splashFactory: NoSplash.splashFactory,
    textTheme: refinedType,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background.withValues(alpha: 0.82),
      foregroundColor: palette.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background.withValues(alpha: 0.92),
      indicatorColor: palette.accent.withValues(alpha: 0.18),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      height: 72,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ThemeRadii.hero),
        ),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeRadii.hero),
      ),
      titleTextStyle: refinedType.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: refinedType.bodyMedium?.copyWith(
        color: palette.textSecondary,
        height: 1.45,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.surfaceElevated,
      contentTextStyle: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      elevation: ThemeElevation.medium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeRadii.large),
        side: BorderSide(color: palette.divider),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.isLight ? Colors.white : Colors.black,
        disabledBackgroundColor: palette.surfaceMuted,
        disabledForegroundColor: palette.textSecondary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: ThemeSpacing.x5),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeRadii.large),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: ThemeSpacing.x5),
        side: BorderSide(color: palette.divider),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeRadii.large),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.accent,
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeRadii.medium),
        ),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.surfaceMuted,
      thumbColor: palette.accent,
      overlayColor: palette.accent.withValues(alpha: 0.14),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>(
        (states) =>
            states.contains(WidgetState.selected)
                ? (palette.isLight ? Colors.white : Colors.black)
                : palette.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith<Color?>(
        (states) =>
            states.contains(WidgetState.selected)
                ? palette.accent.withValues(alpha: 0.62)
                : palette.surfaceMuted,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.accent,
      linearTrackColor: palette.surfaceMuted,
      circularTrackColor: palette.surfaceMuted,
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: 1,
      space: ThemeSpacing.x4,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: palette.surface,
      selectedColor: palette.accent,
      side: BorderSide(color: palette.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.divider),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: palette.isLight ? Colors.white : Colors.black,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface,
      hintStyle: TextStyle(color: palette.textSecondary),
      labelStyle: TextStyle(color: palette.textSecondary),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: palette.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: BorderSide(color: palette.accent),
      ),
    ),
  );
}
