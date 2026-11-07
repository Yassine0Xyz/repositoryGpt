import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/playback_energy_service.dart';

class _FakePcmSource implements PcmSpectrumSource {
  bool started = false;
  int startCount = 0;
  int stopCount = 0;
  int readCount = 0;
  List<double> bands = List<double>.filled(40, 1.0);

  @override
  Future<bool> start(String sourceUri) async {
    started = true;
    startCount++;
    return true;
  }

  @override
  Future<List<double>?> read(int positionMs) async {
    if (!started) return null;
    readCount++;
    return bands;
  }

  @override
  Future<void> stop() async {
    started = false;
    stopCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('playback-time estimate follows speed', () {
    for (final speed in <double>[0.25, 0.5, 1, 1.5, 2, 3]) {
      expect(
        estimatePlaybackPositionMs(
          positionMs: 10000,
          elapsed: const Duration(seconds: 2),
          speed: speed,
        ),
        10000 + (2000 * speed).round(),
      );
    }
  });

  test(
    'starts one visible source only and publishes smoothed real energy',
    () async {
      final source = _FakePcmSource();
      final service = PlaybackEnergyService(
        source: source,
        observeLifecycle: false,
      );
      final first = service.attachConsumer(
        sourceUri: 'file:///first.mp3',
        playing: true,
        visible: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 65));
      expect(source.startCount, 0);

      first.update(visible: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(source.startCount, 1);
      expect(service.energy.value.available, isTrue);
      expect(service.energy.value.level, greaterThan(0));
      expect(service.energy.value.level, lessThan(1));
      expect(source.readCount, inInclusiveRange(2, 6));

      final second = service.attachConsumer(
        sourceUri: 'file:///first.mp3',
        playing: true,
        visible: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(source.startCount, 1);

      first.dispose();
      expect(source.stopCount, 0);
      second.update(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(source.stopCount, 1);
      expect(service.energy.value.available, isFalse);
      expect(service.consumerCount, 1);

      second.dispose();
      await service.disposeForTesting();
    },
  );
}
