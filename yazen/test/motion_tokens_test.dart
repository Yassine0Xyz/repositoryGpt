import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/core/theme/motion_tokens.dart';
import 'package:yazen/core/theme/theme_tokens.dart';

void main() {
  testWidgets('motion tokens provide expected timings and spring', (
    tester,
  ) async {
    Motion? motion;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            motion = Motion.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(motion!.instant, const Duration(milliseconds: 90));
    expect(motion!.fast, const Duration(milliseconds: 160));
    expect(motion!.base, const Duration(milliseconds: 260));
    expect(motion!.slow, const Duration(milliseconds: 420));
    expect(motion!.hero, const Duration(milliseconds: 520));
    expect(MotionTokens.dragSettleSpring.mass, 1);
    expect(MotionTokens.dragSettleSpring.stiffness, 320);
    expect(MotionTokens.dragSettleSpring.damping, 26);
    expect(ThemeSpacing.x1, 4);
    expect(ThemeSpacing.x8, 32);
    expect(ThemeRadii.small, 8);
    expect(ThemeRadii.hero, 28);
    expect(ThemeElevation.high, 6);
  });

  testWidgets('reduced motion returns zero durations', (tester) async {
    Motion? motion;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              motion = Motion.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(motion!.instant, Duration.zero);
    expect(motion!.fast, Duration.zero);
    expect(motion!.base, Duration.zero);
    expect(motion!.slow, Duration.zero);
    expect(motion!.hero, Duration.zero);
  });
}
