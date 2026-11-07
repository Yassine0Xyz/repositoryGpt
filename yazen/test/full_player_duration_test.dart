import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/screens/player/full_player_screen.dart';

void main() {
  test('unknown and zero durations use a placeholder for the total label', () {
    expect(playbackDurationLabel(null), '--:--');
    expect(playbackDurationLabel(Duration.zero), '--:--');
  });

  test('known durations retain the existing clock format', () {
    expect(playbackDurationLabel(const Duration(seconds: 65)), '01:05');
    expect(playbackDurationLabel(const Duration(seconds: 3661)), '1:01:01');
    expect(formatPlaybackDuration(Duration.zero), '00:00');
  });
}
