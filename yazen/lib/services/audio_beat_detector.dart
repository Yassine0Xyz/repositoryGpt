import 'dart:math' as math;
import 'dart:typed_data';

/// Detects short musical onsets from successive normalized PCM spectrum frames.
///
/// The returned envelope peaks on a new transient and decays over 180 ms. A
/// refractory interval rejects multiple flashes from the same bass hit.
class AudioBeatDetector {
  AudioBeatDetector({this.refractory = const Duration(milliseconds: 170)});

  final Duration refractory;
  Float32List _previousBands = Float32List(0);
  DateTime? _lastSampleAt;
  DateTime? _lastBeatAt;
  double _noiseFloor = 0.012;
  double _pulse = 0;

  double process(List<double> bands, {DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    final previousSampleAt = _lastSampleAt;
    if (previousSampleAt != null) {
      final elapsedSeconds =
          math.max(0, now.difference(previousSampleAt).inMicroseconds) /
          Duration.microsecondsPerSecond;
      _pulse *= math.exp(-elapsedSeconds / 0.18);
    } else {
      _pulse = 0;
    }
    _lastSampleAt = now;

    if (bands.isEmpty) {
      _previousBands = Float32List(0);
      return _pulse;
    }
    if (_previousBands.length != bands.length) {
      _previousBands = Float32List(bands.length);
      _copyBands(bands);
      return _pulse;
    }

    final bassCount = math.max(1, (bands.length * 0.3).round());
    var totalFlux = 0.0;
    var bassFlux = 0.0;
    for (var index = 0; index < bands.length; index++) {
      final current = bands[index].clamp(0.0, 1.0);
      final rise = math.max(0.0, current - _previousBands[index]);
      totalFlux += rise;
      if (index < bassCount) bassFlux += rise;
    }

    final flux = totalFlux / bands.length;
    final bassFluxMean = bassFlux / bassCount;
    final onset = math.max(flux * 2.6, bassFluxMean * 2.2);
    final threshold = math.max(0.035, _noiseFloor * 2.4);
    final lastBeatAt = _lastBeatAt;
    final outsideRefractory =
        lastBeatAt == null || now.difference(lastBeatAt) >= refractory;
    if (onset > threshold && outsideRefractory) {
      final strength = ((onset - threshold) / 0.30).clamp(0.0, 1.0);
      _pulse = math.max(_pulse, 0.35 + strength * 0.65);
      _lastBeatAt = now;
    }

    // Track the local flux floor slowly; a loud sustained passage should not
    // be mistaken for a series of new beats.
    final adaptation = flux < _noiseFloor ? 0.16 : 0.025;
    _noiseFloor = (_noiseFloor + (flux - _noiseFloor) * adaptation).clamp(
      0.006,
      0.10,
    );
    _copyBands(bands);
    return _pulse.clamp(0.0, 1.0);
  }

  void reset() {
    _previousBands = Float32List(0);
    _lastSampleAt = null;
    _lastBeatAt = null;
    _noiseFloor = 0.012;
    _pulse = 0;
  }

  void _copyBands(List<double> bands) {
    for (var index = 0; index < bands.length; index++) {
      _previousBands[index] = bands[index].clamp(0.0, 1.0);
    }
  }
}
