import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/core/theme/app_theme.dart';
import 'package:yazen/core/theme/theme_tokens.dart';

void main() {
  test('shared theme styles keep app surfaces and controls consistent', () {
    final theme = buildAppTheme();

    expect(
      theme.bottomSheetTheme.backgroundColor,
      ThemeTokens.fromPreset(EchoThemePreset.oledBlack).surfaceElevated,
    );
    expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    expect(theme.sliderTheme.trackHeight, 4);
    expect(
      theme.filledButtonTheme.style?.minimumSize?.resolve(
        const <WidgetState>{},
      ),
      const Size(48, 48),
    );
  });
}
