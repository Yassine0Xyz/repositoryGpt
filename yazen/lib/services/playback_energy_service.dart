import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_beat_detector.dart';
import 'linux_pcm_spectrum_service.dart';

@visibleForTesting
int estimatePlaybackPositionMs({
  required int positionMs,
  required Duration elapsed,
  required double speed,
}) {
  final advancedMs =
      (elapsed.inMicroseconds / 1000 * speed.clamp(0.25, 3.0)).round();
  return math.max(0, positionMs + advancedMs);
}

@immutable
class AudioEnergy {
  const AudioEnergy({
    required this.level,
    required this.bass,
    required this.mid,
    required this.treble,
    required this.available,
    this.beat = 0,
    this.bands = const <double>[],
  });

  const AudioEnergy.idle()
    : level = 0,
      bass = 0,
      mid = 0,
      treble = 0,
      available = false,
      beat = 0,
      bands = const <double>[];

  final double level;
  final double bass;
  final double mid;
  final double treble;
  final bool available;
  final double beat;
  final List<double> bands;
}

abstract interface class PcmSpectrumSource {
  Future<bool> start(String sourceUri);
  Future<List<double>?> read(int positionMs);
  Future<void> stop();
}

class PlatformPcmSpectrumSource implements PcmSpectrumSource {
  static const MethodChannel _channel = MethodChannel('yazen/audio_visualizer');

  @override
  Future<bool> start(String sourceUri) async {
    if (Platform.isLinux) {
      return LinuxPcmSpectrumService.instance.start(sourceUri);
    }
    if (!Platform.isAndroid) return false;
    final response = await _channel.invokeMethod<dynamic>(
      'startPcm',
      <String, Object?>{'uri': sourceUri},
    );
    return response is Map<dynamic, dynamic> && response['started'] == true;
  }

  @override
  Future<List<double>?> read(int positionMs) async {
    final response =
        Platform.isLinux
            ? LinuxPcmSpectrumService.instance.read(positionMs)
            : await _channel.invokeMethod<dynamic>('readPcm', <String, Object?>{
              'positionMs': positionMs,
            });
    if (response is! Map<dynamic, dynamic> || response['state'] != 'live') {
      return null;
    }
    final rawBands = response['bands'];
    if (rawBands is! List<dynamic>) return null;
    final bands = rawBands
        .whereType<num>()
        .map((value) => value.toDouble().clamp(0.0, 1.0))
        .toList(growable: false);
    return bands.isEmpty ? null : bands;
  }

  @override
  Future<void> stop() async {
    if (Platform.isLinux) {
      await LinuxPcmSpectrumService.instance.stop();
      return;
    }
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopPcm');
    } on MissingPluginException {
      // There is no PCM bridge on this platform.
    } on PlatformException {
      // An inactive source is already stopped.
    }
  }
}

class PlaybackEnergyConsumer {
  PlaybackEnergyConsumer._(this._service, this._id);

  final PlaybackEnergyService _service;
  final int _id;
  bool _released = false;

  void update({
    String? sourceUri,
    int? positionMs,
    bool? playing,
    bool? visible,
    double? speed,
  }) {
    if (_released) return;
    _service._updateConsumer(
      _id,
      sourceUri: sourceUri,
      positionMs: positionMs,
      playing: playing,
      visible: visible,
      speed: speed,
    );
  }

  void dispose() {
    if (_released) return;
    _released = true;
    _service._detachConsumer(_id);
  }
}

class PlaybackEnergyService extends WidgetsBindingObserver {
  PlaybackEnergyService({
    PcmSpectrumSource? source,
    bool observeLifecycle = true,
  }) : _source = source ?? PlatformPcmSpectrumSource() {
    if (observeLifecycle) {
      final binding = WidgetsBinding.instance;
      _appResumed =
          binding.lifecycleState == null ||
          binding.lifecycleState == AppLifecycleState.resumed;
      binding.addObserver(this);
    }
  }

  static final PlaybackEnergyService instance = PlaybackEnergyService();
  static const Duration _pollInterval = Duration(milliseconds: 40);
  static const Duration _attack = Duration(milliseconds: 80);
  static const Duration _release = Duration(milliseconds: 600);

  final PcmSpectrumSource _source;
  final AudioBeatDetector _beatDetector = AudioBeatDetector();
  final ValueNotifier<AudioEnergy> _energy = ValueNotifier<AudioEnergy>(
    const AudioEnergy.idle(),
  );
  final Map<int, _EnergyConsumerState> _consumers =
      <int, _EnergyConsumerState>{};

  Timer? _pollTimer;
  Future<void> _lifecycleTail = Future<void>.value();
  String? _activeUri;
  int? _activeConsumerId;
  int _nextConsumerId = 0;
  int _revision = 0;
  bool _appResumed = true;
  bool _readInFlight = false;
  DateTime? _lastFrameAt;

  ValueListenable<AudioEnergy> get energy => _energy;
  @visibleForTesting
  int get consumerCount => _consumers.length;

  PlaybackEnergyConsumer attachConsumer({
    String? sourceUri,
    int positionMs = 0,
    bool playing = false,
    bool visible = false,
    double speed = 1.0,
  }) {
    final id = ++_nextConsumerId;
    _consumers[id] = _EnergyConsumerState(
      sourceUri: sourceUri,
      positionMs: math.max(0, positionMs),
      playing: playing,
      visible: visible,
      speed: speed.clamp(0.25, 3.0).toDouble(),
      positionAnchorAt: playing ? DateTime.now() : null,
    );
    _scheduleSync();
    return PlaybackEnergyConsumer._(this, id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    _scheduleSync();
  }

  void _updateConsumer(
    int id, {
    String? sourceUri,
    int? positionMs,
    bool? playing,
    bool? visible,
    double? speed,
  }) {
    final consumer = _consumers[id];
    if (consumer == null) return;
    if (sourceUri != null) consumer.sourceUri = sourceUri;
    if (positionMs != null) {
      consumer.positionMs = math.max(0, positionMs);
      consumer.positionAnchorAt = consumer.playing ? DateTime.now() : null;
    }
    if (speed != null && speed != consumer.speed) {
      final now = DateTime.now();
      consumer.positionMs = consumer.effectivePositionMsAt(now);
      consumer.positionAnchorAt = consumer.playing ? now : null;
      consumer.speed = speed.clamp(0.25, 3.0).toDouble();
    }
    if (playing != null && playing != consumer.playing) {
      consumer.positionAnchorAt = playing ? DateTime.now() : null;
      consumer.playing = playing;
    }
    if (visible != null) consumer.visible = visible;
    _scheduleSync();
  }

  void _detachConsumer(int id) {
    if (_consumers.remove(id) == null) return;
    _scheduleSync();
  }

  void _scheduleSync() {
    ++_revision;
    _lifecycleTail = _lifecycleTail
        .then((_) => _synchronizeSource())
        .catchError((Object _) {
          _publishUnavailable();
        });
  }

  Future<void> _synchronizeSource() async {
    final desired = _desiredConsumer();
    if (desired == null) {
      await _deactivateSource();
      return;
    }

    final uri = desired.value.sourceUri!;
    if (_activeUri == uri) {
      _activeConsumerId = desired.key;
      return;
    }

    final revision = _revision;
    await _deactivateSource();
    final started = await _source.start(uri);
    if (!started) {
      _publishUnavailable();
      return;
    }
    if (revision != _revision || _desiredConsumer()?.value.sourceUri != uri) {
      await _source.stop();
      return;
    }

    _activeUri = uri;
    _activeConsumerId = desired.key;
    _lastFrameAt = null;
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(_readFrame()));
    unawaited(_readFrame());
  }

  MapEntry<int, _EnergyConsumerState>? _desiredConsumer() {
    if (!_appResumed) return null;
    for (final entry in _consumers.entries) {
      final consumer = entry.value;
      if (consumer.visible &&
          consumer.playing &&
          consumer.sourceUri != null &&
          consumer.sourceUri!.isNotEmpty) {
        return entry;
      }
    }
    return null;
  }

  Future<void> _deactivateSource() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    final wasActive = _activeUri != null;
    _activeUri = null;
    _activeConsumerId = null;
    _readInFlight = false;
    _lastFrameAt = null;
    _publishUnavailable();
    if (wasActive) await _source.stop();
  }

  Future<void> _readFrame() async {
    if (_readInFlight || _activeUri == null) return;
    final consumer =
        _activeConsumerId == null ? null : _consumers[_activeConsumerId];
    if (consumer == null) return;
    _readInFlight = true;
    final uri = _activeUri;
    try {
      final bands = await _source.read(consumer.effectivePositionMs);
      if (uri != _activeUri || _activeConsumerId == null) return;
      if (bands == null || bands.isEmpty) {
        _publishUnavailable();
      } else {
        _publishBands(bands);
      }
    } on MissingPluginException {
      _publishUnavailable();
      _scheduleSync();
    } on PlatformException {
      _publishUnavailable();
    } finally {
      _readInFlight = false;
    }
  }

  void _publishBands(List<double> bands) {
    final targets = _summarize(bands);
    final now = DateTime.now();
    final elapsed =
        _lastFrameAt == null ? _pollInterval : now.difference(_lastFrameAt!);
    _lastFrameAt = now;
    final previous = _energy.value;
    final level = _smooth(previous.level, targets.$1, elapsed);
    final bass = _smooth(previous.bass, targets.$2, elapsed);
    final mid = _smooth(previous.mid, targets.$3, elapsed);
    final treble = _smooth(previous.treble, targets.$4, elapsed);
    final beat = _beatDetector.process(bands, timestamp: now);
    _energy.value = AudioEnergy(
      level: level,
      bass: bass,
      mid: mid,
      treble: treble,
      available: true,
      beat: beat,
      bands: List<double>.unmodifiable(bands),
    );
  }

  (double, double, double, double) _summarize(List<double> bands) {
    double average(int start, int end) {
      final safeStart = start.clamp(0, bands.length);
      final safeEnd = end.clamp(safeStart, bands.length);
      if (safeEnd <= safeStart) return 0;
      var sum = 0.0;
      for (var index = safeStart; index < safeEnd; index++) {
        sum += bands[index].clamp(0.0, 1.0);
      }
      return sum / (safeEnd - safeStart);
    }

    final count = bands.length;
    final bass = average(0, math.max(1, (count * 0.25).round()));
    final midStart = (count * 0.25).round();
    final midEnd = (count * 0.7).round();
    final mid = average(midStart, math.max(midStart + 1, midEnd));
    final treble = average(midEnd, count);
    return ((bass + mid + treble) / 3, bass, mid, treble);
  }

  double _smooth(double current, double target, Duration elapsed) {
    final timeConstant = target >= current ? _attack : _release;
    final seconds =
        math.max(0.0, elapsed.inMicroseconds) / Duration.microsecondsPerSecond;
    final alpha =
        1.0 -
        math.exp(
          -seconds /
              (timeConstant.inMicroseconds / Duration.microsecondsPerSecond),
        );
    return (current + (target - current) * alpha).clamp(0.0, 1.0);
  }

  void _publishUnavailable() {
    _beatDetector.reset();
    final current = _energy.value;
    if (!current.available &&
        current.level == 0 &&
        current.bass == 0 &&
        current.mid == 0 &&
        current.treble == 0 &&
        current.bands.isEmpty) {
      return;
    }
    _energy.value = const AudioEnergy.idle();
  }

  @visibleForTesting
  Future<void> disposeForTesting() async {
    _consumers.clear();
    await _deactivateSource();
    WidgetsBinding.instance.removeObserver(this);
    _energy.dispose();
  }
}

class _EnergyConsumerState {
  _EnergyConsumerState({
    required this.sourceUri,
    required this.positionMs,
    required this.playing,
    required this.visible,
    required this.positionAnchorAt,
    required this.speed,
  });

  String? sourceUri;
  int positionMs;
  bool playing;
  bool visible;
  DateTime? positionAnchorAt;
  double speed;

  int get effectivePositionMs {
    return effectivePositionMsAt(DateTime.now());
  }

  int effectivePositionMsAt(DateTime now) {
    final anchor = positionAnchorAt;
    final elapsed =
        playing && anchor != null ? now.difference(anchor) : Duration.zero;
    return estimatePlaybackPositionMs(
      positionMs: positionMs,
      elapsed: elapsed,
      speed: speed,
    );
  }
}
