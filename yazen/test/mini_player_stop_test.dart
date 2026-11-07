import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yazen/core/theme/theme_provider.dart';
import 'package:yazen/widgets/mini_player.dart';

void main() {
  testWidgets('mini-player X invokes stop and dismiss', (tester) async {
    var dismissCount = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 380,
                child: MiniPlayer(
                  item: const MediaItem(id: 'test-song', title: 'Test song'),
                  isPlaying: false,
                  onPlayPause: () {},
                  onStop: () {},
                  onDismiss: () => dismissCount++,
                  onPrevious: () {},
                  onNext: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final closeButton = find.byTooltip('Stop and close mini player');
    expect(closeButton, findsOneWidget);
    await tester.tap(closeButton);
    await tester.pump();

    expect(dismissCount, 1);
  });
}
