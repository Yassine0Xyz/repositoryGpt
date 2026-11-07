import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/audio_beat_detector.dart';

void main() {
  test(
    'bass transients create a pulse and sustained energy does not retrigger',
    () {
      final detector = AudioBeatDetector();
      final start = DateTime.utc(2026, 1, 1);
      final quiet = List<double>.filled(40, 0.12);
      final kick = List<double>.filled(40, 0.12)..fillRange(0, 12, 0.68);

      expect(detector.process(quiet, timestamp: start), 0);
      final pulse = detector.process(
        kick,
        timestamp: start.add(const Duration(milliseconds: 40)),
      );
      expect(pulse, greaterThan(0.8));

      final sustained = detector.process(
        kick,
        timestamp: start.add(const Duration(milliseconds: 80)),
      );
      expect(sustained, lessThan(pulse));
      expect(sustained, greaterThan(0));
    },
  );

  test('a new beat after the refractory interval triggers a fresh pulse', () {
    final detector = AudioBeatDetector();
    final start = DateTime.utc(2026, 1, 1);
    final quiet = List<double>.filled(40, 0.1);
    final kick = List<double>.filled(40, 0.1)..fillRange(0, 12, 0.7);
    detector.process(quiet, timestamp: start);
    detector.process(
      kick,
      timestamp: start.add(const Duration(milliseconds: 40)),
    );
    detector.process(
      kick,
      timestamp: start.add(const Duration(milliseconds: 80)),
    );

    detector.process(
      quiet,
      timestamp: start.add(const Duration(milliseconds: 250)),
    );
    final nextPulse = detector.process(
      kick,
      timestamp: start.add(const Duration(milliseconds: 290)),
    );
    expect(nextPulse, greaterThan(0.9));
  });

  test('silent and unavailable inputs decay to zero without false beats', () {
    final detector = AudioBeatDetector();
    final start = DateTime.utc(2026, 1, 1);
    final quiet = List<double>.filled(32, 0.0);
    expect(detector.process(quiet, timestamp: start), 0);
    expect(
      detector.process(quiet, timestamp: start.add(const Duration(seconds: 1))),
      0,
    );
    detector.reset();
    expect(detector.process(const <double>[], timestamp: start), 0);
  });
}
