import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/diagnostics/core/diagnostics_service.dart';

void main() {
  test('records diagnostic events in the session buffer', () {
    final diagnostics = DiagnosticsService.instance;
    final before = diagnostics.retainedEventCount;

    diagnostics.record('test_event', <String, Object?>{'value': 42});

    expect(diagnostics.retainedEventCount, before + 1);
  });

  test('uses a 60 Hz fallback frame budget before native display sampling', () {
    final diagnostics = DiagnosticsService.instance;
    expect(diagnostics.frameBudgetMs, closeTo(16.6667, 0.01));
  });

  test('calculates pointer velocity from event timestamps, not callback time', () {
    final velocity = DiagnosticsService.calculateEventVelocity(
      delta: -446.875,
      previousTimestamp: const Duration(microseconds: 271446567000),
      currentTimestamp: const Duration(microseconds: 271446666000),
    );

    expect(velocity, closeTo(-4513.8889, 0.01));
  });

  test('does not calculate velocity without a positive event timestamp interval', () {
    expect(
      DiagnosticsService.calculateEventVelocity(
        delta: 100,
        previousTimestamp: null,
        currentTimestamp: const Duration(milliseconds: 10),
      ),
      isNull,
    );
    expect(
      DiagnosticsService.calculateEventVelocity(
        delta: 100,
        previousTimestamp: const Duration(milliseconds: 10),
        currentTimestamp: const Duration(milliseconds: 10),
      ),
      isNull,
    );
    expect(
      DiagnosticsService.calculateEventVelocity(
        delta: 100,
        previousTimestamp: const Duration(milliseconds: 11),
        currentTimestamp: const Duration(milliseconds: 10),
      ),
      isNull,
    );
  });

  test('creates distinct span identifiers and retains operation context', () {
    final diagnostics = DiagnosticsService.instance;
    final first = diagnostics.startSpan('test_operation');
    final second = diagnostics.startSpan('test_operation');

    expect(first.spanId, isNot(second.spanId));
    expect(first.traceId, isNot(second.traceId));

    diagnostics.endSpan(first, 'complete');
    diagnostics.endSpan(second, 'complete');
  });
}
