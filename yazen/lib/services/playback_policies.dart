import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';

/// Actions the audio handler may take for an interruption event.
enum InterruptionAction { none, pause, duck, restoreDuck, resume }

/// Coordinates interruption ownership so automatic resume never overrides a
/// user's explicit pause or volume change.
class InterruptionCoordinator {
  bool _pausedByInterruption = false;
  AudioInterruptionType? _pausedInterruptionType;
  double? _duckedBaseVolume;
  double? _pendingDuckRestoreVolume;

  bool get pausedByInterruption => _pausedByInterruption;

  InterruptionAction handle({
    required bool begin,
    required AudioInterruptionType type,
    required bool isPlaying,
    required double currentVolume,
  }) {
    if (begin) {
      switch (type) {
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (!isPlaying) return InterruptionAction.none;
          _pausedByInterruption = true;
          _pausedInterruptionType = type;
          return InterruptionAction.pause;
        case AudioInterruptionType.duck:
          if (_duckedBaseVolume != null) return InterruptionAction.none;
          _duckedBaseVolume = currentVolume;
          return InterruptionAction.duck;
      }
    }

    switch (type) {
      case AudioInterruptionType.pause:
        if (!_pausedByInterruption ||
            _pausedInterruptionType != AudioInterruptionType.pause) {
          return InterruptionAction.none;
        }
        _pausedByInterruption = false;
        _pausedInterruptionType = null;
        return InterruptionAction.resume;
      case AudioInterruptionType.unknown:
        _pausedByInterruption = false;
        _pausedInterruptionType = null;
        return InterruptionAction.none;
      case AudioInterruptionType.duck:
        final baseVolume = _duckedBaseVolume;
        _duckedBaseVolume = null;
        if (baseVolume == null) return InterruptionAction.none;
        final expectedDucked = baseVolume * 0.3;
        if ((currentVolume - expectedDucked).abs() > 0.001) {
          return InterruptionAction.none;
        }
        _pendingDuckRestoreVolume = baseVolume;
        return InterruptionAction.restoreDuck;
    }
  }

  InterruptionAction handleBecomingNoisy({required bool isPlaying}) =>
      isPlaying ? InterruptionAction.pause : InterruptionAction.none;

  /// A user pause takes ownership away from an interruption.
  void onUserPause() {
    _pausedByInterruption = false;
    _pausedInterruptionType = null;
  }

  /// A user resume means a later interruption end must not issue another play.
  void onUserPlay() => onUserPause();

  double? takeDuckRestoreVolume() {
    final volume = _pendingDuckRestoreVolume;
    _pendingDuckRestoreVolume = null;
    return volume;
  }
}

enum SleepTimerMode { duration, endOfCurrentTrack }

/// Returns the linear volume factor for a sleep fade.
double sleepFadeFactor({
  required Duration elapsed,
  required Duration fadeDuration,
}) {
  if (fadeDuration <= Duration.zero) return 0.0;
  return (1.0 - elapsed.inMicroseconds / fadeDuration.inMicroseconds)
      .clamp(0.0, 1.0)
      .toDouble();
}

Duration sleepFadeDuration(Duration timerDuration) {
  const maximum = Duration(seconds: 12);
  return timerDuration < maximum ? timerDuration : maximum;
}

/// Formats a remaining timer value without truncating short durations to zero.
String formatSleepTimerCountdown(Duration remaining) {
  final totalSeconds = remaining.inSeconds.clamp(0, 24 * 60 * 60);
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  if (totalSeconds >= 3600) {
    final hours = totalSeconds ~/ 3600;
    final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

AudioServiceRepeatMode nextRepeatMode(AudioServiceRepeatMode mode) {
  return switch (mode) {
    AudioServiceRepeatMode.none => AudioServiceRepeatMode.one,
    AudioServiceRepeatMode.one => AudioServiceRepeatMode.all,
    AudioServiceRepeatMode.all => AudioServiceRepeatMode.none,
    AudioServiceRepeatMode.group => AudioServiceRepeatMode.none,
  };
}

bool repeatModeIsEnabled(AudioServiceRepeatMode mode) =>
    mode != AudioServiceRepeatMode.none;

bool shouldFinishSleepTimerOnTrackChange({
  required SleepTimerMode mode,
  required int? targetIndex,
  required int currentIndex,
}) =>
    mode == SleepTimerMode.endOfCurrentTrack &&
    targetIndex != null &&
    targetIndex != currentIndex;
