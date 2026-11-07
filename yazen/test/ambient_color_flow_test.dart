import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/widgets/ambient_color_flow.dart';

void main() {
  testWidgets('keeps a static blurred tint until the artwork color changes', (
    tester,
  ) async {
    const firstColor = Color(0xFF8C50C8);
    const secondColor = Color(0xFFDF6682);

    Widget playerWithTint(Color color) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              AmbientColorFlow(color: color),
              const Center(child: Text('Track title')),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(playerWithTint(firstColor));
    expect(find.text('Track title'), findsOneWidget);
    expect(find.byType(AmbientColorFlow), findsOneWidget);

    final before = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AmbientColorFlow),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(before.painter, isA<CustomPainter>());

    await tester.pump(const Duration(seconds: 2));
    final afterStaticFrame = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AmbientColorFlow),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(identical(afterStaticFrame.painter, before.painter), isTrue);

    await tester.pumpWidget(playerWithTint(secondColor));
    final afterTrackChange = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(AmbientColorFlow),
        matching: find.byType(CustomPaint),
      ),
    );
    expect(afterTrackChange.painter!.shouldRepaint(before.painter!), isTrue);
    expect(tester.takeException(), isNull);
  });
}
