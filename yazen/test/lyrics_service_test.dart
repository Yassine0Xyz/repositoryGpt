import 'package:flutter_test/flutter_test.dart';

import 'package:yazen/services/lyrics_service.dart';

void main() {
  group('LyricsService.parseLrc', () {
    final service = LyricsService();

    tearDown(service.dispose);

    test('parses timestamps and removes them from displayed text', () {
      final lyrics = service.parseLrc(
        '''[00:03.50] First line\n[00:08] Second line''',
      );

      expect(lyrics, hasLength(2));
      expect(lyrics[0].timestamp, const Duration(milliseconds: 3500));
      expect(lyrics[0].text, 'First line');
      expect(lyrics[1].text, 'Second line');
    });

    test('supports multiple timestamps on one line', () {
      final lyrics = service.parseLrc('[00:01.00][00:02.00] Same line');

      expect(lyrics.map((line) => line.timestamp.inSeconds), [1, 2]);
      expect(lyrics.every((line) => line.text == 'Same line'), isTrue);
    });
  });

  test('reads old cache entries without words', () {
    final lyrics = SyncedLyrics.fromJson({
      'lines': [
        {'timestampMs': 1200, 'text': 'Legacy line'},
      ],
      'plainText': null,
    });

    expect(lyrics.lines.single.text, 'Legacy line');
    expect(lyrics.lines.single.words, isEmpty);
  });
}
