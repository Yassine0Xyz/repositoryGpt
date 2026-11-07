import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/widgets/mini_player_gesture_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('horizontal swipe follows the drag and advances the track', (
    tester,
  ) async {
    var nextCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MiniPlayerGestureSurface(
              onNext: () => nextCount++,
              onPrevious: () {},
              onExpand: () {},
              child: const SizedBox(width: 300, height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(MiniPlayerGestureSurface),
      const Offset(-68, 0),
    );
    await tester.pumpAndSettle();
    expect(nextCount, 1);
  });

  testWidgets('a slow intentional horizontal swipe still advances the track', (
    tester,
  ) async {
    var nextCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MiniPlayerGestureSurface(
              onNext: () => nextCount++,
              onPrevious: () {},
              onExpand: () {},
              child: const SizedBox(width: 300, height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.timedDrag(
      find.byType(MiniPlayerGestureSurface),
      const Offset(-68, 0),
      const Duration(milliseconds: 500),
    );
    await tester.pumpAndSettle();
    expect(nextCount, 1);
  });

  testWidgets('upward flick expands to the full player', (tester) async {
    var expandCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MiniPlayerGestureSurface(
              onNext: () {},
              onPrevious: () {},
              onExpand: () => expandCount++,
              child: const SizedBox(width: 300, height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(MiniPlayerGestureSurface),
      const Offset(0, -58),
    );
    await tester.pumpAndSettle();
    expect(expandCount, 1);
  });

  testWidgets('downward drag does not expand the full player', (tester) async {
    var expandCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MiniPlayerGestureSurface(
              onNext: () {},
              onPrevious: () {},
              onExpand: () => expandCount++,
              child: const SizedBox(width: 300, height: 80),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(MiniPlayerGestureSurface),
      const Offset(0, 60),
    );
    await tester.pumpAndSettle();
    expect(expandCount, 0);
  });
}
