import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yazen/core/theme/theme_provider.dart';
import 'package:yazen/services/lyrics_service.dart';
import 'package:yazen/widgets/lyrics_view.dart';

void main() {
  testWidgets('lyrics page fills the page and seeks to tapped timestamps', (
    tester,
  ) async {
    var seekTarget = Duration.zero;
    final lyrics = const SyncedLyrics(
      lines: <LyricLine>[
        LyricLine(timestamp: Duration.zero, text: 'First line'),
        LyricLine(
          timestamp: Duration(seconds: 8),
          text: 'Second line',
          words: <LyricWord>[
            LyricWord(timestamp: Duration(seconds: 8), text: 'Second'),
            LyricWord(timestamp: Duration(milliseconds: 8500), text: 'line'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: LyricsPage(
            title: 'A track title',
            artist: 'An artist',
            lyricsLoader: () async => lyrics,
            onRetry: () {},
            positionStream: Stream<Duration>.value(Duration.zero),
            onLineTap: (position) => seekTarget = position,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A track title'), findsOneWidget);
    expect(find.text('An artist'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(tester.getSize(find.byType(LyricsView)).height, greaterThan(300));

    await tester.tap(find.text('Second line', findRichText: true));
    expect(seekTarget, const Duration(seconds: 8));
  });
}
