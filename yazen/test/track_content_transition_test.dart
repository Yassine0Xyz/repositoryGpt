import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/screens/player/full_player_screen.dart';

void main() {
  const transitionCurve = Curves.easeInOutCubic;

  testWidgets('outgoing content fades and slides with the swipe direction', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 190),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TrackContentTransition(
              animation: controller,
              swipeDirection: -1,
              incoming: false,
              dragOffset: -18,
              dragOffsetDuration: Duration.zero,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );

    controller.value = 0.5;
    await tester.pump();

    final progress = transitionCurve.transform(0.5);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(1 - progress, 0.001),
    );
    final transition = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('track-content-transition-slide')),
    );
    expect(transition.transform.storage[12], closeTo(-56 * progress, 0.001));
    final drag = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('track-content-drag-offset')),
    );
    expect(drag.transform!.storage[12], closeTo(-18, 0.001));
  });

  testWidgets('incoming content starts opposite the swipe and fades in', (
    tester,
  ) async {
    final controller = AnimationController(
      vsync: tester,
      duration: const Duration(milliseconds: 190),
      value: 1,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TrackContentTransition(
              animation: controller,
              swipeDirection: -1,
              incoming: true,
              dragOffset: 0,
              dragOffsetDuration: Duration.zero,
              child: const SizedBox(width: 80, height: 80),
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0);
    var transition = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('track-content-transition-slide')),
    );
    expect(transition.transform.storage[12], closeTo(56, 0.001));

    controller.value = 0.5;
    await tester.pump();
    final progress = transitionCurve.transform(0.5);
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(1 - progress, 0.001),
    );
    transition = tester.widget<Transform>(
      find.byKey(const ValueKey<String>('track-content-transition-slide')),
    );
    expect(transition.transform.storage[12], closeTo(56 * progress, 0.001));
  });
}
