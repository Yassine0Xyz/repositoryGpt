import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yazen/services/playback_policies.dart';

void main() {
  group('interruption coordinator', () {
    test('pauses playing audio and resumes on matching pause end', () {
      final policy = InterruptionCoordinator();

      expect(
        policy.handle(
          begin: true,
          type: AudioInterruptionType.pause,
          isPlaying: true,
          currentVolume: 1.0,
        ),
        InterruptionAction.pause,
      );
      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.pause,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.resume,
      );
    });

    test('an unknown begin is not resumed by a later pause end', () {
      final policy = InterruptionCoordinator();
      policy.handle(
        begin: true,
        type: AudioInterruptionType.unknown,
        isPlaying: true,
        currentVolume: 1.0,
      );

      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.pause,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.none,
      );
    });

    test('unknown interruptions never auto-resume', () {
      final policy = InterruptionCoordinator();

      expect(
        policy.handle(
          begin: true,
          type: AudioInterruptionType.unknown,
          isPlaying: true,
          currentVolume: 1.0,
        ),
        InterruptionAction.pause,
      );
      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.unknown,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.none,
      );
    });

    test('duck attenuates without pausing and restores unchanged volume', () {
      final policy = InterruptionCoordinator();

      expect(
        policy.handle(
          begin: true,
          type: AudioInterruptionType.duck,
          isPlaying: true,
          currentVolume: 0.8,
        ),
        InterruptionAction.duck,
      );
      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.duck,
          isPlaying: true,
          currentVolume: 0.24,
        ),
        InterruptionAction.restoreDuck,
      );
      expect(policy.takeDuckRestoreVolume(), 0.8);
    });

    test('already-paused audio is never resumed by an interruption end', () {
      final policy = InterruptionCoordinator();

      expect(
        policy.handle(
          begin: true,
          type: AudioInterruptionType.pause,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.none,
      );
      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.pause,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.none,
      );
    });

    test('a user pause prevents an unintended interruption resume', () {
      final policy = InterruptionCoordinator();
      policy.handle(
        begin: true,
        type: AudioInterruptionType.pause,
        isPlaying: true,
        currentVolume: 1.0,
      );
      policy.onUserPause();

      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.pause,
          isPlaying: false,
          currentVolume: 1.0,
        ),
        InterruptionAction.none,
      );
    });

    test('duck end does not overwrite a user volume change', () {
      final policy = InterruptionCoordinator();
      policy.handle(
        begin: true,
        type: AudioInterruptionType.duck,
        isPlaying: true,
        currentVolume: 0.8,
      );

      expect(
        policy.handle(
          begin: false,
          type: AudioInterruptionType.duck,
          isPlaying: true,
          currentVolume: 0.5,
        ),
        InterruptionAction.none,
      );
      expect(policy.takeDuckRestoreVolume(), isNull);
    });

    test('becoming noisy pauses only when playback is active', () {
      final policy = InterruptionCoordinator();

      expect(
        policy.handleBecomingNoisy(isPlaying: true),
        InterruptionAction.pause,
      );
      expect(
        policy.handleBecomingNoisy(isPlaying: false),
        InterruptionAction.none,
      );
    });
  });

  group('repeat mode policy', () {
    test('cycles full-player repeat through off, one, and all', () {
      expect(
        nextRepeatMode(AudioServiceRepeatMode.none),
        AudioServiceRepeatMode.one,
      );
      expect(
        nextRepeatMode(AudioServiceRepeatMode.one),
        AudioServiceRepeatMode.all,
      );
      expect(
        nextRepeatMode(AudioServiceRepeatMode.all),
        AudioServiceRepeatMode.none,
      );
      expect(repeatModeIsEnabled(AudioServiceRepeatMode.none), isFalse);
      expect(repeatModeIsEnabled(AudioServiceRepeatMode.all), isTrue);
    });
  });

  group('sleep countdown label', () {
    test('shows mm:ss under an hour and h:mm:ss for longer timers', () {
      expect(formatSleepTimerCountdown(const Duration(seconds: 35)), '00:35');
      expect(
        formatSleepTimerCountdown(const Duration(minutes: 12, seconds: 4)),
        '12:04',
      );
      expect(
        formatSleepTimerCountdown(
          const Duration(hours: 2, minutes: 3, seconds: 4),
        ),
        '2:03:04',
      );
    });
  });

  group('sleep fade math', () {
    test('short timers fade across their full duration', () {
      expect(
        sleepFadeDuration(const Duration(seconds: 5)),
        const Duration(seconds: 5),
      );
      expect(
        sleepFadeFactor(
          elapsed: const Duration(seconds: 2, milliseconds: 500),
          fadeDuration: const Duration(seconds: 5),
        ),
        closeTo(0.5, 0.0001),
      );
    });

    test('long timers cap the fade at twelve seconds', () {
      expect(
        sleepFadeDuration(const Duration(minutes: 20)),
        const Duration(seconds: 12),
      );
      expect(
        sleepFadeFactor(
          elapsed: const Duration(seconds: 12),
          fadeDuration: const Duration(seconds: 12),
        ),
        0.0,
      );
    });
  });

  group('end-of-current-track sleep timer', () {
    test('finishes only after the captured track index changes', () {
      expect(
        shouldFinishSleepTimerOnTrackChange(
          mode: SleepTimerMode.endOfCurrentTrack,
          targetIndex: 3,
          currentIndex: 3,
        ),
        isFalse,
      );
      expect(
        shouldFinishSleepTimerOnTrackChange(
          mode: SleepTimerMode.endOfCurrentTrack,
          targetIndex: 3,
          currentIndex: 4,
        ),
        isTrue,
      );
      expect(
        shouldFinishSleepTimerOnTrackChange(
          mode: SleepTimerMode.duration,
          targetIndex: 3,
          currentIndex: 4,
        ),
        isFalse,
      );
    });
  });
}
