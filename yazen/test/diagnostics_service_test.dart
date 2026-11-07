import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/diagnostics/core/diagnostics_service.dart';

void main() {
  test('records diagnostic events in the session buffer', () {
    final diagnostics = DiagnosticsService.instance;
    final before = diagnostics.retainedEventCount;

    diagnostics.record('test_event', <String, Object?>{'value': 42});

    expect(diagnostics.retainedEventCount, before + 1);
  });
}
