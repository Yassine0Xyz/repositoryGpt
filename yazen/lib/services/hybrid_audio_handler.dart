import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../models/media_track.dart';
import 'playback_state_store.dart';
import 'playback_policies.dart';
import 'serial_async_queue.dart';
import 'equalizer_settings_store.dart';

/// Single source of truth for local audio playback and queue metadata.
class HybridAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  static const String _notificationStopAction = 'yazen.stop';

  factory HybridAudioHandler({
    AudioPlayer? player,
    PlaybackStateStore? playbackStore,
    AndroidEqualizer? equalizer,
    EqualizerSettingsStore? equalizerSettingsStore,
  }) {
    final resolvedEqualizer = equalizer ?? AndroidEqualizer();
    final resolvedPlayer =
        player ??
        AudioPlayer(
          handleInterruptions: false,
          maxSkipsOnError: 2,
          audioPipeline: AudioPipeline(
            androidAudioEffects: <AndroidAudioEffect>[resolvedEqualizer],
          ),
        );
    return HybridAudioHandler._(
      player: resolvedPlayer,
      playbackStore: playbackStore ?? const PlaybackStateStore(),
      equalizer: resolvedEqualizer,
      equalizerSettingsStore:
          equalizerSettingsStore ?? const EqualizerSettingsStore(),
    );
  }

  HybridAudioHandler._({
    required AudioPlayer player,
    required PlaybackStateStore playbackStore,
    required AndroidEqualizer equalizer,
    required EqualizerSettingsStore equalizerSettingsStore,
  }) : _player = player,
       _playbackStore = playbackStore,
       _equalizer = equalizer,
       _equalizerSettingsStore = equalizerSettingsStore {
    _equalizerAvailable = Platform.isAndroid;
    _equalizerEnabledController = StreamController<bool>.broadcast(sync: true);
    _surroundEnabledController = StreamController<bool>.broadcast(sync: true);
    _equalizerSettingsReady = _loadEqualizerSettings();
    _sleepRemainingController = StreamController<Duration?>.broadcast(
      sync: true,
    );
    _subscriptions.add(
      _player.playbackEventStream.listen((_) => _broadcastPlaybackState()),
    );
    _subscriptions.add(
      _player.playerStateStream.listen((_) => _handlePlayerStateChanged()),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen(_onCurrentIndexChanged),
    );
    _subscriptions.add(
      _player.positionStream.listen(_onSleepTimerPositionChanged),
    );
    _subscriptions.add(
      _player.processingStateStream.listen(_onProcessingStateChanged),
    );
    _subscriptions.add(
      _player.androidAudioSessionIdStream.listen(_onAudioSessionIdChanged),
    );
  }

  final AudioPlayer _player;
  final PlaybackStateStore _playbackStore;
  final AndroidEqualizer _equalizer;
  final EqualizerSettingsStore _equalizerSettingsStore;
  late final Future<void> _equalizerSettingsReady;
  late final StreamController<bool> _equalizerEnabledController;
  late final StreamController<bool> _surroundEnabledController;
  Future<AndroidEqualizerParameters>? _equalizerParametersFuture;
  AndroidEqualizerParameters? _equalizerParameters;
  final Map<int, Timer> _equalizerBandTimers = <int, Timer>{};
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<MediaTrack> _queueTracks = <MediaTrack>[];
  int _queueGeneration = 0;
  int _selectionRequest = 0;
  int _queueMutationDepth = 0;
  int? _selectionSourceLoadRequest;
  int? _selectionInterruptRequest;
  Future<void>? _selectionInterruptFuture;
  final SerialAsyncQueue _queueOperations = SerialAsyncQueue();
  bool _autoAdvanceInFlight = false;
  Timer? _resumeTimer;
  Timer? _equalizerSaveTimer;
  Timer? _equalizerRetryTimer;
  Timer? _sleepTimer;
  Timer? _sleepFadeTimer;
  Timer? _sleepCountdownTimer;
  DateTime? _sleepDeadline;
  SleepTimerMode _sleepTimerMode = SleepTimerMode.duration;
  int? _sleepTrackIndex;
  late final StreamController<Duration?> _sleepRemainingController;
  final InterruptionCoordinator _interruptionCoordinator =
      InterruptionCoordinator();
  static const _effectsChannel = MethodChannel('yazen/audio_effects');
  bool _threeDSurroundEnabled = false;
  // The effect is attached through just_audio's AudioPipeline on Android.
  // The native platform reports parameter failures through the guarded methods.
  bool _equalizerAvailable = false;
  bool _equalizerEnabled = true;
  String _equalizerPreset = 'Flat';
  List<double> _equalizerBandGains = <double>[];
  String? _equalizerError;
  int _equalizerRetryAttempt = 0;
  int? _equalizerRetrySessionId;
  bool _endingTrackForSleepTimer = false;
  MediaTrack? _activeTrack;
  bool _isDisposed = false;
  Future<void>? _disposeFuture;
  double _volume = 1.0;
  double _playbackSpeed = 1.0;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;

  AudioPlayer get player => _player;
  MediaTrack? get activeTrack => _activeTrack;
  AndroidEqualizer get equalizer => _equalizer;
  bool get threeDSurroundEnabled => _threeDSurroundEnabled;
  bool get equalizerAvailable => _equalizerAvailable;
  bool get equalizerEnabled => _equalizerEnabled;
  Stream<bool> get equalizerEnabledStream => _equalizerEnabledController.stream;
  Stream<bool> get threeDSurroundEnabledStream =>
      _surroundEnabledController.stream;
  String get equalizerPreset => _equalizerPreset;
  String? get equalizerError => _equalizerError;
  Future<void> get equalizerSettingsReady => _equalizerSettingsReady;
  double get playbackSpeed => _playbackSpeed;
  AudioServiceRepeatMode get repeatMode => _repeatMode;
  AudioServiceShuffleMode get shuffleMode => _shuffleMode;
  SleepTimerMode get sleepTimerMode => _sleepTimerMode;
  Stream<Duration?> get sleepTimerRemainingStream =>
      _sleepRemainingController.stream;
  List<MediaTrack> get queueTracks =>
      List<MediaTrack>.unmodifiable(_queueTracks);
  int get currentQueueIndex => _player.currentIndex ?? 0;
  Duration? get sleepTimerRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final remaining = deadline.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _handlePlayerStateChanged() {
    _broadcastPlaybackState();
    _syncProgressSaveTimer();
  }

  void _syncProgressSaveTimer() {
    if (_isDisposed || !_player.playing) {
      _resumeTimer?.cancel();
      _resumeTimer = null;
      return;
    }
    _resumeTimer ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (_player.playing) _persistPlayback();
    });
  }

  Future<T> _runQueueMutation<T>(Future<T> Function() operation) {
    return _queueOperations.run<T>(() async {
      _queueMutationDepth++;
      try {
        return await operation();
      } finally {
        _queueMutationDepth--;
        if (_queueMutationDepth == 0) {
          await _repairQueueInvariant();
          final index = _player.currentIndex;
          if (index != null) _onCurrentIndexChanged(index);
        }
      }
    });
  }

  void _interruptSupersededSelection() {
    final request = _selectionSourceLoadRequest;
    if (request == null || request == _selectionRequest || _isDisposed) return;
    if (_selectionInterruptRequest == request) return;

    // Interrupt only the native source-swap window, not while the old track
    // is still playing or while a large queue is being prepared. The active
    // mutation awaits this one shared stop before the next selection can run.
    _selectionInterruptRequest = request;
    _selectionInterruptFuture = _player.stop().catchError((Object _) {
      // The stale source may already have completed or been stopped.
    });
  }

  Future<void> _finishSelectionSourceLoad(int request) async {
    if (_selectionSourceLoadRequest != request) return;
    final interrupt =
        _selectionInterruptRequest == request
            ? _selectionInterruptFuture
            : null;
    if (interrupt != null) await interrupt;
    if (_selectionSourceLoadRequest == request) {
      _selectionSourceLoadRequest = null;
    }
    if (_selectionInterruptRequest == request) {
      _selectionInterruptRequest = null;
      _selectionInterruptFuture = null;
    }
  }

  Future<void> _repairQueueInvariant() async {
    if (_player.sequence.length == _queueTracks.length) return;
    try {
      await _player.stop();
      await _player.clearAudioSources();
    } catch (_) {
      // Clearing local state is still safer than publishing a mismatched queue.
    }
    _queueTracks.clear();
    _activeTrack = null;
    queue.add(const <MediaItem>[]);
    mediaItem.add(null);
    try {
      await _playbackStore.clear();
    } catch (_) {
      // Storage recovery will retry through its serialized operation queue.
    }
  }

  Future<void> configureAudioSession(AudioSession session) async {
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) => _handleBecomingNoisy()),
    );
    // Keep playback alive when another media app opens. Android may still
    // attenuate or revoke audio focus for calls, alarms, or exclusive apps,
    // but YAZEN must not pause itself in response to a normal app switch.
    // just_audio owns activation requests through handleAudioSessionActivation;
    // interruption policy is explicit because handleInterruptions is disabled.
    _subscriptions.add(
      session.interruptionEventStream.listen(_handleInterruption),
    );
  }

  void setSleepTimer(
    Duration? duration, {
    SleepTimerMode mode = SleepTimerMode.duration,
  }) {
    _cancelSleepTimer();
    if (mode == SleepTimerMode.duration &&
        (duration == null || duration <= Duration.zero)) {
      return;
    }
    _sleepTimerMode = mode;
    if (mode == SleepTimerMode.endOfCurrentTrack) {
      _sleepTrackIndex = _player.currentIndex;
      _sleepRemainingController.add(null);
      _onSleepTimerPositionChanged(_player.position);
      return;
    }
    final timerDuration = duration!;
    _sleepDeadline = DateTime.now().add(timerDuration);
    _sleepRemainingController.add(timerDuration);
    _sleepCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sleepRemainingController.add(sleepTimerRemaining);
    });
    final fadeDuration = sleepFadeDuration(timerDuration);
    final fadeStart = timerDuration - fadeDuration;
    _sleepTimer = Timer(fadeStart, () {
      final startedAt = DateTime.now();
      _sleepFadeTimer = Timer.periodic(const Duration(milliseconds: 250), (
        timer,
      ) {
        final elapsed = DateTime.now().difference(startedAt);
        final factor = sleepFadeFactor(
          elapsed: elapsed,
          fadeDuration: fadeDuration,
        );
        unawaited(_player.setVolume(_volume * factor));
        _sleepRemainingController.add(sleepTimerRemaining);
        if (factor <= 0) {
          timer.cancel();
          _sleepFadeTimer = null;
          _sleepTimer = null;
          _finishSleepTimer();
        }
      });
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepFadeTimer?.cancel();
    _sleepCountdownTimer?.cancel();
    _sleepTimer = null;
    _sleepFadeTimer = null;
    _sleepCountdownTimer = null;
    _sleepDeadline = null;
    _sleepTimerMode = SleepTimerMode.duration;
    _sleepTrackIndex = null;
    _endingTrackForSleepTimer = false;
    _sleepRemainingController.add(null);
    unawaited(_player.setVolume(_volume));
  }

  void _finishSleepTimer() {
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = null;
    _endingTrackForSleepTimer = false;
    _sleepCountdownTimer?.cancel();
    _sleepCountdownTimer = null;
    _sleepDeadline = null;
    _sleepTimerMode = SleepTimerMode.duration;
    _sleepTrackIndex = null;
    _sleepRemainingController.add(null);
    unawaited(pause());
    unawaited(_player.setVolume(_volume));
  }

  void _onSleepTimerPositionChanged(Duration position) {
    if (_sleepTimerMode != SleepTimerMode.endOfCurrentTrack ||
        _endingTrackForSleepTimer ||
        _sleepTrackIndex == null ||
        _player.currentIndex != _sleepTrackIndex) {
      return;
    }
    final duration = _player.duration;
    if (duration == null || duration <= Duration.zero) return;
    if (duration - position > const Duration(milliseconds: 300)) return;

    _endingTrackForSleepTimer = true;
    final startedAt = DateTime.now();
    const fadeDuration = Duration(milliseconds: 250);
    _sleepFadeTimer?.cancel();
    _sleepFadeTimer = Timer.periodic(const Duration(milliseconds: 25), (timer) {
      final factor = sleepFadeFactor(
        elapsed: DateTime.now().difference(startedAt),
        fadeDuration: fadeDuration,
      );
      unawaited(_player.setVolume(_volume * factor));
      if (factor <= 0) {
        timer.cancel();
        _sleepFadeTimer = null;
        _finishSleepTimer();
      }
    });
  }

  Future<void> _handleBecomingNoisy() async {
    if (!_player.playing) return;
    await pause();
  }

  Future<void> _handleInterruption(AudioInterruptionEvent event) async {
    // Another media app commonly emits a pause-type focus event. Do not turn
    // that external focus change into a YAZEN pause; Android may still duck or
    // revoke focus when system policy requires it.
    if (event.begin && event.type == AudioInterruptionType.pause) return;
    final action = _interruptionCoordinator.handle(
      begin: event.begin,
      type: event.type,
      isPlaying: _player.playing,
      currentVolume: _player.volume,
    );
    switch (action) {
      case InterruptionAction.none:
        return;
      case InterruptionAction.pause:
        await _player.pause();
        _persistPlayback();
      case InterruptionAction.duck:
        await _player.setVolume(_player.volume * 0.3);
      case InterruptionAction.restoreDuck:
        final restoreVolume = _interruptionCoordinator.takeDuckRestoreVolume();
        if (restoreVolume != null) await _player.setVolume(restoreVolume);
      case InterruptionAction.resume:
        await _player.play();
        _persistPlayback();
    }
  }

  Future<bool> setEqualizerEnabled(bool enabled) async {
    await _equalizerSettingsReady;
    final previous = _equalizerEnabled;
    _equalizerEnabled = enabled;
    _equalizerEnabledController.add(enabled);
    _resetEqualizerRetry();
    await _persistEqualizerSettingsNow();
    if (!_equalizerAvailable) {
      _equalizerEnabled = previous;
      _equalizerEnabledController.add(previous);
      return false;
    }
    try {
      await _equalizer.setEnabled(enabled);
      _equalizerError = null;
      _equalizerRetryAttempt = 0;
      _equalizerRetryTimer?.cancel();
      return true;
    } catch (error) {
      _recordEqualizerFailure(error);
      _equalizerEnabled = previous;
      _equalizerEnabledController.add(previous);
      return false;
    }
  }

  Future<bool> setEqualizerBandGain(int bandIndex, double gain) async {
    await _equalizerSettingsReady;
    if (!_equalizerAvailable || bandIndex < 0 || bandIndex >= 32) return false;
    final parameters = _equalizerParameters;
    final maxGain = parameters?.maxDecibels ?? 15.0;
    final minGain = parameters?.minDecibels ?? -15.0;
    while (_equalizerBandGains.length <= bandIndex) {
      _equalizerBandGains.add(0.0);
    }
    _equalizerBandGains[bandIndex] = gain.clamp(minGain, maxGain).toDouble();
    _scheduleEqualizerSettingsSave();
    _equalizerBandTimers.remove(bandIndex)?.cancel();
    _equalizerBandTimers[bandIndex] = Timer(
      const Duration(milliseconds: 75),
      () => unawaited(_applyEqualizerBandGain(bandIndex)),
    );
    return true;
  }

  Future<void> setEqualizerPreset(String preset) async {
    await _equalizerSettingsReady;
    _equalizerPreset = preset;
    _scheduleEqualizerSettingsSave();
  }

  Future<void> setThreeDSurroundEnabled(bool enabled) async {
    await _equalizerSettingsReady;
    _threeDSurroundEnabled = enabled;
    _surroundEnabledController.add(enabled);
    _resetEqualizerRetry();
    await _persistEqualizerSettingsNow();
    if (!_equalizerAvailable || _player.androidAudioSessionId == null) return;
    try {
      await _applyVirtualizer(enabled, _player.androidAudioSessionId!);
      _equalizerError = null;
    } catch (error) {
      _recordEqualizerFailure(error);
    }
  }

  Future<void> _loadEqualizerSettings() async {
    try {
      final settings = await _equalizerSettingsStore.load();
      _equalizerEnabled = settings.enabled;
      _threeDSurroundEnabled = settings.surroundEnabled;
      _equalizerEnabledController.add(_equalizerEnabled);
      _surroundEnabledController.add(_threeDSurroundEnabled);
      _equalizerPreset = settings.preset;
      _equalizerBandGains = List<double>.of(settings.bandGains);
      if (_player.androidAudioSessionId != null) {
        unawaited(_applyEqualizerSettings());
      }
    } catch (error) {
      _recordEqualizerFailure(error);
    }
  }

  void _onAudioSessionIdChanged(int? sessionId) {
    if (sessionId != _equalizerRetrySessionId) {
      _equalizerRetrySessionId = sessionId;
      _resetEqualizerRetry();
    }
    if (sessionId == null || !_equalizerAvailable || _isDisposed) return;
    unawaited(_equalizerSettingsReady.then((_) => _applyEqualizerSettings()));
  }

  void _resetEqualizerRetry() {
    _equalizerRetryAttempt = 0;
    _equalizerRetryTimer?.cancel();
    _equalizerRetryTimer = null;
  }

  Future<AndroidEqualizerParameters> _getEqualizerParameters() {
    return _equalizerParametersFuture ??= _equalizer.parameters.then((value) {
      _equalizerParameters = value;
      return value;
    });
  }

  Future<void> _applyEqualizerSettings() async {
    if (!_equalizerAvailable ||
        _isDisposed ||
        _player.androidAudioSessionId == null) {
      return;
    }
    Object? failure;
    try {
      final parameters = await _getEqualizerParameters();
      if (_isDisposed || _player.androidAudioSessionId == null) return;
      for (
        var index = 0;
        index < parameters.bands.length && index < _equalizerBandGains.length;
        index++
      ) {
        final gain =
            _equalizerBandGains[index]
                .clamp(parameters.minDecibels, parameters.maxDecibels)
                .toDouble();
        await parameters.bands[index].setGain(gain);
        if (_isDisposed) return;
      }
      await _equalizer.setEnabled(_equalizerEnabled);
    } catch (error) {
      failure = error;
    }
    try {
      final sessionId = _player.androidAudioSessionId;
      if (sessionId != null) {
        await _applyVirtualizer(_threeDSurroundEnabled, sessionId);
      }
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) {
      _recordEqualizerFailure(failure);
    } else {
      _equalizerError = null;
      _equalizerRetryAttempt = 0;
      _equalizerRetryTimer?.cancel();
    }
  }

  Future<void> _applyEqualizerBandGain(int bandIndex) async {
    if (_isDisposed || _player.androidAudioSessionId == null) return;
    try {
      final parameters = await _getEqualizerParameters();
      if (_isDisposed || _player.androidAudioSessionId == null) return;
      if (bandIndex >= parameters.bands.length ||
          bandIndex >= _equalizerBandGains.length) {
        return;
      }
      final gain =
          _equalizerBandGains[bandIndex]
              .clamp(parameters.minDecibels, parameters.maxDecibels)
              .toDouble();
      _equalizerBandGains[bandIndex] = gain;
      await parameters.bands[bandIndex].setGain(gain);
      _equalizerError = null;
    } catch (error) {
      _recordEqualizerFailure(error);
    }
  }

  Future<void> _applyVirtualizer(bool enabled, int sessionId) async {
    try {
      await _effectsChannel.invokeMethod<void>(
        'setVirtualizerEnabled',
        <String, dynamic>{'enabled': enabled, 'audioSessionId': sessionId},
      );
    } on MissingPluginException {
      // The native virtualizer is optional on devices without the plugin.
    }
  }

  EqualizerSettings _equalizerSettingsSnapshot() => EqualizerSettings(
    enabled: _equalizerEnabled,
    surroundEnabled: _threeDSurroundEnabled,
    preset: _equalizerPreset,
    bandGains: List<double>.unmodifiable(_equalizerBandGains),
  );

  Future<void> _persistEqualizerSettingsNow() async {
    try {
      await _equalizerSettingsStore.save(_equalizerSettingsSnapshot());
    } catch (error) {
      _equalizerError = error.toString();
    }
  }

  void _scheduleEqualizerSettingsSave() {
    _equalizerSaveTimer?.cancel();
    _equalizerSaveTimer = Timer(const Duration(milliseconds: 250), () {
      if (_isDisposed) return;
      unawaited(_persistEqualizerSettingsNow());
    });
  }

  void _recordEqualizerFailure(Object error) {
    _equalizerError = error.toString();
    if (_isDisposed ||
        !_equalizerAvailable ||
        _equalizerRetryTimer != null ||
        _equalizerRetryAttempt >= 5) {
      return;
    }
    final delaySeconds = (1 << _equalizerRetryAttempt).clamp(1, 30).toInt();
    _equalizerRetryAttempt++;
    _equalizerRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      _equalizerRetryTimer = null;
      unawaited(_applyEqualizerSettings());
    });
  }

  Future<void> playTrack(MediaTrack track, {bool autoPlay = true}) {
    final request = ++_selectionRequest;
    _queueGeneration++;
    _interruptSupersededSelection();
    final generation = _queueGeneration;
    return _runQueueMutation(() async {
      if (_isDisposed || request != _selectionRequest) return;
      await _playTrackInternal(
        track,
        request: request,
        autoPlay: autoPlay,
        generation: generation,
        isCurrent: () => request == _selectionRequest,
      );
    });
  }

  Future<void> _playTrackInternal(
    MediaTrack track, {
    required int request,
    required int generation,
    bool autoPlay = true,
    bool Function()? isCurrent,
  }) async {
    bool stillCurrent() =>
        generation == _queueGeneration && (isCurrent?.call() ?? true);
    if (!stillCurrent()) return;
    final item = track.toMediaItem();
    final source = _resolveSource(track, item);
    if (!stillCurrent()) return;

    // Keep the active song running while the new source is prepared. pause()
    // changes just_audio's local playing flag immediately, which ensures that
    // preload:false below does not turn into an expensive decoder load.
    await _player.pause();
    if (!stillCurrent()) return;
    _selectionSourceLoadRequest = request;
    try {
      await _player.setAudioSource(source, preload: false);
    } catch (error) {
      if (!stillCurrent()) return;
      rethrow;
    } finally {
      await _finishSelectionSourceLoad(request);
    }
    if (!stillCurrent()) return;
    _queueTracks
      ..clear()
      ..add(track);
    _publishQueueState(<MediaItem>[item], 0);
    _persistQueueAndProgress();
    if (autoPlay && stillCurrent()) _startPlaybackWithoutHoldingQueue();
  }

  Future<void> playTrackQueue(List<MediaTrack> tracks, {int initialIndex = 0}) {
    if (tracks.isEmpty || _isDisposed) return Future<void>.value();
    final requestedTracks = List<MediaTrack>.unmodifiable(tracks);
    final request = ++_selectionRequest;
    _queueGeneration++;
    _interruptSupersededSelection();
    final generation = _queueGeneration;
    final safeIndex = initialIndex.clamp(0, requestedTracks.length - 1).toInt();
    return _runQueueMutation(() async {
      if (request != _selectionRequest) return;
      await _playLocalTrackQueue(
        requestedTracks,
        initialIndex: safeIndex,
        request: request,
        generation: generation,
        isCurrent: () => request == _selectionRequest,
      );
    });
  }

  Future<void> _playLocalTrackQueue(
    List<MediaTrack> tracks, {
    required int initialIndex,
    required int request,
    required int generation,
    required bool Function() isCurrent,
  }) async {
    bool stillCurrent() =>
        generation == _queueGeneration && isCurrent() && !_isDisposed;
    if (!stillCurrent()) return;
    if (_hasSameLoadedQueue(tracks)) {
      await _player.seek(Duration.zero, index: initialIndex);
      if (!stillCurrent()) return;
      final selectedTrack = _queueTracks[initialIndex];
      _activeTrack = selectedTrack;
      mediaItem.add(selectedTrack.toMediaItem());
      _broadcastPlaybackState();
      _persistPlayback();
      _startPlaybackWithoutHoldingQueue();
      return;
    }

    final items = tracks.map((track) => track.toMediaItem()).toList();
    final sources = <AudioSource>[];
    for (var index = 0; index < tracks.length; index++) {
      if (!stillCurrent()) return;
      sources.add(_resolveSource(tracks[index], items[index]));
      if ((index + 1) % 128 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (!stillCurrent()) return;

    await _player.pause();
    if (!stillCurrent()) return;

    _selectionSourceLoadRequest = request;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        preload: false,
      );
    } catch (error) {
      if (!stillCurrent()) return;
      rethrow;
    } finally {
      await _finishSelectionSourceLoad(request);
    }
    if (!stillCurrent()) return;

    _queueTracks
      ..clear()
      ..addAll(tracks);
    _publishQueueState(items, initialIndex);
    _persistQueueAndProgress();
    _startPlaybackWithoutHoldingQueue();
  }

  bool _hasSameLoadedQueue(List<MediaTrack> tracks) {
    if (_player.processingState == ProcessingState.loading ||
        _queueTracks.length != tracks.length ||
        _player.sequence.length != tracks.length) {
      return false;
    }
    for (var index = 0; index < tracks.length; index++) {
      final current = _queueTracks[index];
      final requested = tracks[index];
      if (current.id != requested.id ||
          current.uri != requested.uri ||
          current.artworkUri != requested.artworkUri ||
          current.title != requested.title ||
          current.artist != requested.artist ||
          current.album != requested.album ||
          current.duration != requested.duration ||
          current.source != requested.source ||
          current.kind != requested.kind) {
        return false;
      }
    }
    return true;
  }

  Future<void> addToQueue(MediaTrack track) => _runQueueMutation(() async {
    if (_isDisposed) return;
    final item = track.toMediaItem();
    final source = _resolveSource(track, item);
    await _player.addAudioSource(source);
    _queueTracks.add(track);
    queue.add(<MediaItem>[...queue.value, item]);
    _persistQueueAndProgress();
  });

  Future<void> addTracksToQueue(Iterable<MediaTrack> tracks) =>
      _runQueueMutation(() async {
        if (_isDisposed) return;
        final additions = tracks.toList(growable: false);
        if (additions.isEmpty) return;
        final items = additions.map((track) => track.toMediaItem()).toList();
        final sources = List<AudioSource>.generate(
          additions.length,
          (index) => _resolveSource(additions[index], items[index]),
          growable: false,
        );
        await _player.addAudioSources(sources);
        _queueTracks.addAll(additions);
        queue.add(<MediaItem>[...queue.value, ...items]);
        _persistQueueAndProgress();
      });

  Future<void> restoreLastPlayback() => _runQueueMutation(() async {
    final snapshot = await _playbackStore.load();
    if (snapshot == null || _isDisposed) return;
    try {
      final items = <MediaItem>[];
      final sources = <AudioSource>[];
      final restoredTracks = <MediaTrack>[];
      final restoredSourceIndexes = <int>[];
      var allTracksMissing = snapshot.queue.isNotEmpty;
      final savedCurrentIndex = snapshot.currentIndex.clamp(
        0,
        snapshot.queue.length - 1,
      );
      var restoredIndex = -1;
      for (
        var sourceIndex = 0;
        sourceIndex < snapshot.queue.length;
        sourceIndex++
      ) {
        final track = snapshot.queue[sourceIndex];
        try {
          if (!await _isRestorableTrack(track)) {
            final uri = track.uri;
            final isDefinitivelyMissingFile =
                track.isLocal && uri?.scheme == 'file';
            if (!isDefinitivelyMissingFile) allTracksMissing = false;
            continue;
          }
          // A file that exists, or a content URI that must be resolved by
          // Android, means the snapshot is not safe to discard on failure.
          allTracksMissing = false;
          final item = track.toMediaItem();
          final source = _resolveSource(track, item);
          if (sourceIndex == savedCurrentIndex) restoredIndex = items.length;
          items.add(item);
          sources.add(source);
          restoredTracks.add(track);
          restoredSourceIndexes.add(sourceIndex);
        } catch (error, stackTrace) {
          allTracksMissing = false;
          developer.log(
            'Skipping one saved playback entry during restore',
            name: 'yazen.playback',
            error: error,
            stackTrace: stackTrace,
          );
          // Drop unavailable entries while retaining the restorable queue.
        }
      }
      if (sources.isEmpty) {
        await _player.stop();
        await _player.clearAudioSources();
        _queueTracks.clear();
        queue.add(const <MediaItem>[]);
        mediaItem.add(null);
        _activeTrack = null;
        if (allTracksMissing) await _playbackStore.clear();
        return;
      }
      final savedCurrentTrackSurvived = restoredIndex >= 0;
      if (!savedCurrentTrackSurvived) {
        final nextTrackIndex = restoredSourceIndexes.indexWhere(
          (sourceIndex) => sourceIndex >= savedCurrentIndex,
        );
        restoredIndex = nextTrackIndex >= 0 ? nextTrackIndex : items.length - 1;
      }
      final index = restoredIndex;
      await _player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition:
            savedCurrentTrackSurvived ? snapshot.position : Duration.zero,
      );
      _queueTracks
        ..clear()
        ..addAll(restoredTracks);
      _playbackSpeed = snapshot.speed;
      _repeatMode = AudioServiceRepeatMode.values.elementAt(
        snapshot.repeatMode.clamp(0, AudioServiceRepeatMode.values.length - 1),
      );
      _shuffleMode = AudioServiceShuffleMode.values.elementAt(
        snapshot.shuffleMode.clamp(
          0,
          AudioServiceShuffleMode.values.length - 1,
        ),
      );
      await _player.setSpeed(_playbackSpeed);
      await setRepeatMode(_repeatMode);
      await setShuffleMode(_shuffleMode);
      _publishQueueState(items, index);
      if (snapshot.playing) {
        await _player.play();
      }
      if (restoredTracks.length != snapshot.queue.length ||
          index != snapshot.currentIndex) {
        _persistQueueAndProgress();
      }
    } catch (error, stackTrace) {
      developer.log(
        'Saved playback restore failed; preserving persisted queue',
        name: 'yazen.playback',
        error: error,
        stackTrace: stackTrace,
      );
      _queueTracks.clear();
      await _player.stop();
      await _player.clearAudioSources();
    }
  });

  Future<void> removeFromQueue(int index) => _runQueueMutation(() async {
    if (index < 0 || index >= _queueTracks.length) return;
    await _player.removeAudioSourceAt(index);
    _queueTracks.removeAt(index);
    queue.add(
      _queueTracks.map((track) => track.toMediaItem()).toList(growable: false),
    );
    if (_queueTracks.isEmpty) {
      _activeTrack = null;
      mediaItem.add(null);
      await _playbackStore.clear();
    } else {
      _persistQueueAndProgress();
    }
  });

  Future<void> moveInQueue(int oldIndex, int newIndex) => _runQueueMutation(
    () async {
      if (oldIndex < 0 ||
          oldIndex >= _queueTracks.length ||
          newIndex < 0 ||
          newIndex >= _queueTracks.length) {
        return;
      }
      await _player.moveAudioSource(oldIndex, newIndex);
      final track = _queueTracks.removeAt(oldIndex);
      _queueTracks.insert(newIndex, track);
      queue.add(
        _queueTracks.map((item) => item.toMediaItem()).toList(growable: false),
      );
      _persistQueueAndProgress();
    },
  );

  Future<void> clearQueue() {
    _cancelSleepTimer();
    _selectionRequest++;
    _queueGeneration++;
    _interruptSupersededSelection();
    return _runQueueMutation(() async {
      await _player.stop();
      await _player.clearAudioSources();
      _queueTracks.clear();
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      _activeTrack = null;
      await _playbackStore.clear();
    });
  }

  AudioSource _resolveSource(MediaTrack track, MediaItem item) {
    final uri = track.uri;
    if (uri == null) throw StateError('The track is missing a source URI.');
    if (track.isRemote) {
      if (uri.scheme != 'https' && uri.scheme != 'http') {
        throw StateError('Remote audio must use HTTP or HTTPS.');
      }
      return AudioSource.uri(uri, headers: track.headers, tag: item);
    }
    if (!track.isLocal) throw StateError('Unsupported media source.');
    return AudioSource.uri(uri, tag: item);
  }

  Future<bool> _isRestorableTrack(MediaTrack track) async {
    final uri = track.uri;
    if (uri == null) return false;
    if (track.isRemote) {
      return uri.scheme == 'http' || uri.scheme == 'https';
    }
    if (!track.isLocal) return false;
    if (uri.scheme == 'file') return File.fromUri(uri).exists();
    // Content URIs are resolved by Android's MediaProvider; File.exists cannot
    // validate them, so leave validation to the platform audio source.
    return uri.scheme == 'content';
  }

  @override
  Future<void> play() async {
    _interruptionCoordinator.onUserPlay();
    final playback = _player.play();
    _syncProgressSaveTimer();
    _persistPlayback();
    _broadcastPlaybackState();
    await playback;
    _syncProgressSaveTimer();
    _persistPlayback();
  }

  void _startPlaybackWithoutHoldingQueue() {
    unawaited(
      play().catchError((Object _) {
        // The player streams report ongoing state; don't hold the queue lock
        // while just_audio's play future waits for the track to finish.
      }),
    );
  }

  @override
  Future<void> pause() async {
    _interruptionCoordinator.onUserPause();
    await _player.pause();
    _syncProgressSaveTimer();
    _persistPlayback();
  }

  @override
  Future<void> stop() {
    _cancelSleepTimer();
    // Stop is the explicit close action from the notification/mini-player.
    // Cancel pending selections and clear just_audio's native sources and our
    // mirrored queue so old media cannot be resurrected by next/previous.
    _selectionRequest++;
    _queueGeneration++;
    _interruptSupersededSelection();
    return _runQueueMutation(() async {
      await _player.stop();
      _syncProgressSaveTimer();
      await _player.clearAudioSources();
      _queueTracks.clear();
      _activeTrack = null;
      queue.add(const <MediaItem>[]);
      mediaItem.add(null);
      await _playbackStore.clear();
      await super.stop();
    });
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == _notificationStopAction) {
      await stop();
      return null;
    }
    return super.customAction(name, extras);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _persistPlayback();
  }

  @override
  Future<void> skipToNext() => _runQueueMutation(() async {
    final circularIndex = _circularQueueTargetIndex(1);
    if (circularIndex != null) {
      await _seekAndStartQueueIndex(circularIndex);
      return;
    }
    if (_player.hasNext) {
      await _player.seekToNext();
      return;
    }
  });

  Future<void> playQueueIndex(int index) => _runQueueMutation(() async {
    if (index < 0 ||
        index >= _queueTracks.length ||
        index >= _player.sequence.length) {
      return;
    }
    await _player.seek(Duration.zero, index: index);
    _startPlaybackWithoutHoldingQueue();
  });

  @override
  Future<void> skipToPrevious() => _runQueueMutation(() async {
    final circularIndex = _circularQueueTargetIndex(-1);
    if (circularIndex != null) {
      await _seekAndStartQueueIndex(circularIndex);
      return;
    }
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  });

  void _onProcessingStateChanged(ProcessingState state) {
    if (state != ProcessingState.completed || _autoAdvanceInFlight) return;
    _autoAdvanceInFlight = true;
    unawaited(_advanceAfterCompletion());
  }

  Future<void> _advanceAfterCompletion() async {
    final generation = _queueGeneration;
    final request = _selectionRequest;
    bool stillCurrent() =>
        generation == _queueGeneration && request == _selectionRequest;
    try {
      if (!stillCurrent()) return;
      if (_sleepTimerMode == SleepTimerMode.endOfCurrentTrack) {
        _finishSleepTimer();
        return;
      }
      // A queue created from Library, a Playlist, or a custom list is a
      // continuous listening session. Keep automatic completion aligned with
      // the circular Next action instead of stopping at the final item.
      final nextQueueIndex = _circularQueueTargetIndex(1);
      if (nextQueueIndex != null) {
        await _player.seek(Duration.zero, index: nextQueueIndex);
        if (stillCurrent()) _startPlaybackWithoutHoldingQueue();
      }
    } finally {
      _autoAdvanceInFlight = false;
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    _playbackSpeed = speed.clamp(0.25, 3.0).toDouble();
    await _player.setSpeed(_playbackSpeed);
    _persistPlayback();
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0).toDouble();
    await _player.setVolume(_volume);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _player.setShuffleModeEnabled(
      shuffleMode != AudioServiceShuffleMode.none,
    );
    _shuffleMode = shuffleMode;
    await super.setShuffleMode(shuffleMode);
    _broadcastPlaybackState();
    _persistPlayback();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = switch (repeatMode) {
      AudioServiceRepeatMode.none => LoopMode.off,
      AudioServiceRepeatMode.one => LoopMode.one,
      // Repeat All is advanced explicitly so the final item always wraps,
      // even on platforms where just_audio does not emit a usable next item.
      AudioServiceRepeatMode.all => LoopMode.off,
      AudioServiceRepeatMode.group => LoopMode.off,
    };
    await _player.setLoopMode(loopMode);
    _repeatMode = repeatMode;
    await super.setRepeatMode(repeatMode);
    _broadcastPlaybackState();
    _persistPlayback();
  }

  int? _circularQueueTargetIndex(int direction) {
    final queueLength = _queueTracks.length;
    if (queueLength == 0 || _player.sequence.length < queueLength) {
      return null;
    }
    final currentIndex = _player.currentIndex;
    if (currentIndex == null) return null;
    final normalizedIndex = currentIndex % queueLength;
    return (normalizedIndex + direction + queueLength) % queueLength;
  }

  Future<void> _seekAndStartQueueIndex(int index) async {
    await _player.seek(Duration.zero, index: index);
    _startPlaybackWithoutHoldingQueue();
  }

  void _onCurrentIndexChanged(int? index) {
    if (_isDisposed ||
        _queueMutationDepth > 0 ||
        index == null ||
        index < 0 ||
        index >= _queueTracks.length) {
      return;
    }
    final shouldFinishTimer = shouldFinishSleepTimerOnTrackChange(
      mode: _sleepTimerMode,
      targetIndex: _sleepTrackIndex,
      currentIndex: index,
    );
    if (_sleepTimerMode == SleepTimerMode.endOfCurrentTrack &&
        _sleepTrackIndex == null) {
      _sleepTrackIndex = index;
    }
    final track = _queueTracks[index];
    _activeTrack = track;
    mediaItem.add(track.toMediaItem());
    _broadcastPlaybackState();
    _persistPlayback();
    if (shouldFinishTimer) _finishSleepTimer();
  }

  void _publishQueueState(List<MediaItem> items, int index) {
    if (_queueTracks.isEmpty || items.isEmpty) return;
    final safeIndex = index.clamp(0, _queueTracks.length - 1).toInt();
    _activeTrack = _queueTracks[safeIndex];
    // These synchronous subjects are updated in one method so consumers do
    // not receive a newly selected item with an old queue context.
    queue.add(List<MediaItem>.unmodifiable(items));
    mediaItem.add(items[safeIndex]);
    _broadcastPlaybackState();
  }

  void _persistPlayback() {
    if (_isDisposed || _queueTracks.isEmpty) {
      return;
    }
    final index =
        (_player.currentIndex ?? 0).clamp(0, _queueTracks.length - 1).toInt();
    unawaited(
      _playbackStore
          .saveProgress(
            currentIndex: index,
            position: _player.position,
            playing: _player.playing,
            repeatMode: _repeatMode.index,
            shuffleMode: _shuffleMode.index,
            speed: _playbackSpeed,
          )
          .catchError((Object error, StackTrace stackTrace) {
            developer.log(
              'Unable to persist playback progress',
              name: 'yazen.playback',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void _persistQueueAndProgress() {
    if (_isDisposed || _queueTracks.isEmpty) {
      return;
    }
    final queueSnapshot = List<MediaTrack>.unmodifiable(_queueTracks);
    final index =
        (_player.currentIndex ?? 0).clamp(0, queueSnapshot.length - 1).toInt();
    unawaited(
      _playbackStore
          .save(
            queue: queueSnapshot,
            currentIndex: index,
            position: _player.position,
            playing: _player.playing,
            repeatMode: _repeatMode.index,
            shuffleMode: _shuffleMode.index,
            speed: _playbackSpeed,
          )
          .catchError((Object error, StackTrace stackTrace) {
            developer.log(
              'Unable to persist playback queue',
              name: 'yazen.playback',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void _broadcastPlaybackState() {
    if (_isDisposed) return;

    final processingState = switch (_player.processingState) {
      ProcessingState.idle => AudioProcessingState.idle,
      ProcessingState.loading => AudioProcessingState.loading,
      ProcessingState.buffering => AudioProcessingState.buffering,
      ProcessingState.ready => AudioProcessingState.ready,
      ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          const MediaControl(
            androidIcon: 'drawable/yazen_notification_close',
            label: 'Stop and close player',
            action: MediaAction.stop,
          ),
        ],
        systemActions: const <MediaAction>{MediaAction.seek},
        androidCompactActionIndices: const <int>[0, 1, 2],
        processingState: processingState,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        repeatMode: _repeatMode,
        shuffleMode: _shuffleMode,
        queueIndex: _player.currentIndex ?? 0,
      ),
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // Android may call this when the user swipes YAZEN away from Recents.
    // Keep the media foreground service alive so an active local track keeps
    // playing. The explicit Stop/X media control remains the only user-facing
    // action that terminates playback and releases the service.
    await super.onTaskRemoved();
  }

  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _isDisposed = true;
    _resumeTimer?.cancel();
    _cancelSleepTimer();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _queueOperations.idle;
    await _playbackStore.idle;
    await _equalizerSettingsReady;
    _equalizerRetryTimer?.cancel();
    _equalizerSaveTimer?.cancel();
    for (final timer in _equalizerBandTimers.values) {
      timer.cancel();
    }
    await _persistEqualizerSettingsNow();
    await _equalizerEnabledController.close();
    await _surroundEnabledController.close();
    await _sleepRemainingController.close();
    await _player.dispose();
  }
}
