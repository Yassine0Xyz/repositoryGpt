import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/startup_restore.dart';

void main() {
  testWidgets('runs persisted playback restore after the first frame', (
    tester,
  ) async {
    var firstFrameRendered = false;
    var restoreStarted = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      firstFrameRendered = true;
    });
    schedulePlaybackRestoreAfterFirstFrame(() async {
      restoreStarted = firstFrameRendered;
    });

    expect(restoreStarted, isFalse);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('YAZEN'))),
    );

    expect(find.text('YAZEN'), findsOneWidget);
    expect(restoreStarted, isTrue);
  });

  testWidgets('contains a restore failure after the first frame', (
    tester,
  ) async {
    schedulePlaybackRestoreAfterFirstFrame(() async {
      throw StateError('stale saved media');
    });
    await tester.pumpWidget(const MaterialApp(home: Text('YAZEN')));
    await tester.pump();
    expect(find.text('YAZEN'), findsOneWidget);
  });
}
