import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/serial_async_queue.dart';

void main() {
  test('runs operations in submission order', () async {
    final queue = SerialAsyncQueue();
    final events = <String>[];
    final gate = Completer<void>();

    final first = queue.run(() async {
      events.add('first-start');
      await gate.future;
      events.add('first-end');
    });
    final second = queue.run(() async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);
    gate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(events, <String>['first-start', 'first-end', 'second']);
  });

  test('runs later operations after a prior operation throws', () async {
    final queue = SerialAsyncQueue();
    var completed = false;

    final failure = queue.run<void>(() async {
      throw StateError('expected');
    });
    final recovery = queue.run<void>(() async {
      completed = true;
    });

    await expectLater(failure, throwsA(isA<StateError>()));
    await recovery;
    expect(completed, isTrue);
  });
}
