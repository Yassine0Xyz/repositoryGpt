import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/widgets/now_playing_scope.dart';
import 'package:yazen/widgets/play_pause_morph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'now-playing indicator distinguishes active, paused, and other rows',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _NowPlayingCases()));
      expect(find.bySemanticsLabel('Now playing'), findsOneWidget);
      expect(find.bySemanticsLabel('Current track, paused'), findsOneWidget);
      expect(find.byType(NowPlayingIndicator), findsNWidgets(3));
    },
  );

  testWidgets('play/pause morph exposes the right action and handles taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PlayPauseMorph(
              playing: false,
              onPressed: () => taps++,
              tooltip: 'Play',
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byType(AnimatedIcon), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(taps, 1);
  });
}

class _NowPlayingCases extends StatefulWidget {
  const _NowPlayingCases();

  @override
  State<_NowPlayingCases> createState() => _NowPlayingCasesState();
}

class _NowPlayingCasesState extends State<_NowPlayingCases>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..repeat(reverse: true);

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      NowPlayingIndicator(
        isCurrent: true,
        isPlaying: true,
        pulse: _pulse,
        color: Colors.purple,
      ),
      NowPlayingIndicator(
        isCurrent: true,
        isPlaying: false,
        pulse: _pulse,
        color: Colors.purple,
      ),
      NowPlayingIndicator(
        isCurrent: false,
        isPlaying: false,
        pulse: _pulse,
        color: Colors.purple,
      ),
    ],
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }
}
