import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/widgets/echo_motion.dart';

void main() {
  testWidgets('a recycled list item reveals only once per session', (
    tester,
  ) async {
    final session = EchoRevealSession();

    Widget screen(bool visible) => MaterialApp(
      home: Scaffold(
        body:
            visible
                ? EchoReveal(
                  key: const ValueKey<String>('reveal-wrapper'),
                  session: session,
                  revealKey: 'track-1',
                  duration: const Duration(seconds: 1),
                  child: const Text('Track'),
                )
                : const SizedBox.shrink(),
      ),
    );

    await tester.pumpWidget(screen(true));
    await tester.pump(const Duration(milliseconds: 120));
    final initialOpacity =
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('reveal-wrapper')),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value;
    expect(initialOpacity, lessThan(1));

    await tester.pumpWidget(screen(false));
    await tester.pump();
    await tester.pumpWidget(screen(true));
    await tester.pump();

    final recycledOpacity =
        tester
            .widget<FadeTransition>(
              find.descendant(
                of: find.byKey(const ValueKey<String>('reveal-wrapper')),
                matching: find.byType(FadeTransition),
              ),
            )
            .opacity
            .value;
    expect(recycledOpacity, 1);
  });

  testWidgets('reduced motion bypasses the reveal animation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: EchoReveal(
              key: ValueKey<String>('reduced-reveal'),
              child: Text('No motion'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No motion'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('reduced-reveal')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
  });
}
