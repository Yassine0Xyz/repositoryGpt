import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/scroll_performance_mode.dart';

void main() {
  testWidgets('background motion pauses until scroll settles', (tester) async {
    ScrollPerformanceMode.noteScrollActivity();
    expect(ScrollPerformanceMode.isScrolling.value, isTrue);
    ScrollPerformanceMode.noteScrollEnd();

    await tester.pump(const Duration(milliseconds: 139));
    expect(ScrollPerformanceMode.isScrolling.value, isTrue);

    await tester.pump(const Duration(milliseconds: 1));
    expect(ScrollPerformanceMode.isScrolling.value, isFalse);
  });

  testWidgets('a new scroll cancels a pending background resume', (
    tester,
  ) async {
    ScrollPerformanceMode.noteScrollActivity();
    ScrollPerformanceMode.noteScrollEnd();
    await tester.pump(const Duration(milliseconds: 100));

    ScrollPerformanceMode.noteScrollActivity();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ScrollPerformanceMode.isScrolling.value, isTrue);

    ScrollPerformanceMode.noteScrollEnd();
    await tester.pump(const Duration(milliseconds: 140));
    expect(ScrollPerformanceMode.isScrolling.value, isFalse);
  });
}
