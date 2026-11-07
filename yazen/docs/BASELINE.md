# Phase 0 — Baseline and PR #1 Review

**Recorded:** 2026-09-30
**Repository:** `Yassine0Xyz/YAZEN-PLAYER`
**Integration line:** `develop/comprehensive-ui-player`
**Phase 0 branch base:** merge commit `5a56634` (PR #1)

## Executive summary

The requested Android/Flutter build baseline was established on `origin/main` at `a5a4dfe`. The app builds and its six existing tests pass, but the analyzer reports **7 warnings and 73 informational findings**. Six Dart files needed formatting. An Android device or emulator was not attached, so device-only checks remain pending.

PR #1 was reviewed and merged into the repository's integration branch, `develop/comprehensive-ui-player`, as squash commit `5a56634`. Before merge, the branch was formatted and all 13 tests passed; arm64 debug and release APKs built. Analyzer output contained no warnings or errors, but 11 infos, so `flutter analyze` still returned a non-zero exit code. The PR also needed reproducible local forks of two legacy plugins to build against the repository's current Gradle/Android SDK configuration.

## Environment and measured baseline

| Item | Result |
|---|---|
| Measured source revision | `origin/main` — `a5a4dfe` |
| Flutter / Dart | Flutter 3.47.5 stable / Dart 3.13.4 |
| Host / Java | Ubuntu 24.04.5 / OpenJDK 21.0.12 |
| Android SDK | Build Tools 36.0.0; platforms 35 and 36 installed |
| Dependency resolution | `flutter pub get` passed; 30 packages had newer versions outside current constraints (not upgraded in baseline) |
| Formatting | Initial check found 6 files needing formatting; after `dart format`, the repeat check passed across 50 files |
| Analyzer | 80 findings: **0 errors, 7 warnings, 73 infos**; command returned non-zero |
| Unit tests | All 6 baseline tests passed |
| Debug build | `flutter build apk --debug --target-platform android-arm64` passed in 115 s; `app-debug.apk` = 94,998,829 bytes |
| Release build | `flutter build apk --release --target-platform android-arm64 --split-per-abi` passed in 82 s; arm64 APK = 32,960,585 bytes |
| Connected targets | Linux only; `adb devices` returned no Android device or emulator |

### Post-merge integration recheck

A fresh full run against the merged develop snapshot (`c6fed12`) produced 0 analyzer errors, 0 warnings, and 19 informational findings with the default `flutter analyze --no-pub` command. This supersedes the 11-info figure recorded for the earlier PR #1 run; the full integration analysis also includes informational findings from the vendored plugin.

The same snapshot's first full `flutter test --no-pub` run had 12 passing tests and one failure in `linux_pcm_spectrum_service_test.dart`. The test read the requested later-position frame as soon as any frame was live, so the service could clamp both reads to the first decoded frame. The isolated test passed when rerun. This is a readiness race to address with the visualizer tests; no PCM source was changed in Phase 1A, and the subsequent Phase 1A full test run passed.

### Baseline analyzer warnings

- Unused `tokens` in `lib/screens/party/hybrid_party_screen.dart`.
- Unused `playerSize` in `lib/screens/player/yazen_video_player.dart`.

The six files changed by the baseline formatter were `lib/main.dart`, `lib/screens/home/home_screen.dart`, `lib/screens/player/full_player_screen.dart`, `lib/services/lyrics_service.dart`, `lib/services/waveform_service.dart`, and `lib/widgets/audio_visualizer.dart`. Those changes were measured on the old `main` snapshot; they were not carried into the `develop`-based phase branch.

## Branch and integration decision

`develop/comprehensive-ui-player` was the active integration branch because PR #1 targeted it and it was substantially ahead of `main` at inspection time; the local graph showed the merged integration line 73 commits ahead and 2 behind `origin/main`. The branches are not interchangeable, so PR #1 was not retargeted to `main`.

**Decision:** merge PR #1 into `develop/comprehensive-ui-player` after fixing the reproducible Android build blockers and validating tests/builds. GitHub reported the PR as mergeable/clean, and it was squash-merged on 2026-09-30. [PR #1](https://github.com/Yassine0Xyz/YAZEN-PLAYER/pull/1) · merge commit `5a566345e0812e4ab93b4ccb9637caf40bca7147`.

## Independent PR #1 safety review

| Files / area | Review finding | Risk / disposition |
|---|---|---|
| `lib/screens/ai/ai_mixer_screen.dart`, `lib/models/stem_models.dart`, `lib/services/stem_separation_service.dart`, `stem_service/main.py`, `stem_service/requirements.txt` | The Mixer/stem-separation implementation and service/backend are removed. Search of the PR target found no active route or caller outside the removed feature code. | Safe to remove from the shipped UI graph; no live app entry point depended on the deleted backend. |
| `lib/screens/home/home_screen.dart` | Removes obsolete Explore/Party header controls and related callbacks. The actual `HomeScreen` construction did not provide these callbacks. | Dead controls; removal does not sever a wired navigation path. |
| `lib/main.dart` | Removes obsolete feature wiring/imports. | Covered by analyzer and test/build runs. |
| `lib/screens/home/widgets/track_list_tile.dart`, `lib/screens/library/local_media_screen.dart`, `lib/screens/library/entity_tracks_screen.dart`, `lib/screens/collections/favorites_screen.dart`, `lib/screens/collections/playlist_details_screen.dart`, `lib/widgets/mini_player.dart` | Artwork caching, stable keys, and scoped rebuild changes. | Behavior-preserving in code review; visual/runtime behavior still needs device smoke testing. |
| `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt` | Sets Android application ID to `com.yassine.yazen`, enables release shrinking, and removes unused Wi-Fi multicast permissions. No active LAN/NSD feature relied on those permissions. | Matches the supplied app identity. If an earlier public release used the placeholder ID, Android will treat this as a different app rather than an in-place upgrade; confirm release history before publishing. |
| `README.md` | Aligns feature claims with the local-first app. | Documentation-only. |
| `test/local_playlist_manager_test.dart` | Formatting-only correction found during independent verification. | No behavior change. |
| `pubspec.yaml`, `pubspec.lock`, `third_party/on_audio_query_android/**` | Adds a local fork with the required Android namespace for the old `on_audio_query_android` plugin. | Required for the existing dependency to configure under AGP 9; media-query behavior is retained. A non-fatal future Kotlin-plugin compatibility notice remains. |
| `third_party/video_thumbnail/**` | Adds a local copy of `video_thumbnail` 0.5.6, replaces removed `jcenter()` repositories with Maven Central, and sets plugin compile SDK to 36; Dart/native thumbnail behavior is unchanged. | Required for Gradle 9 and current AndroidX metadata; preserves local-video thumbnails. License retained and local patch documented in the directory. |

### PR #1 verification before merge

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | Passed |
| `flutter analyze` | 0 errors, 0 warnings, 11 infos; returned non-zero because infos remain |
| `flutter test` | All 13 tests passed |
| Android arm64 debug APK | Passed; 97,230,263 bytes |
| Android arm64 split-per-ABI release APK | Passed; 29,947,386 bytes |
| `git diff --check` | Passed |
| GitHub status checks | No check runs were reported for the PR |

The release build emits a non-fatal Flutter notice that `on_audio_query_android` still applies Kotlin Gradle Plugin. Neither the PR build nor the baseline build was run on a physical Android device or emulator in this environment.

## Pending device checks

Use [the manual checklist](MANUAL_TEST_CHECKLIST.md) on an Android device/emulator before release. Priority items are playback interruptions/audio focus, Bluetooth controls, background playback/notification actions, media-permission transitions, large-library scrolling, Arabic/RTL and 200% text scaling, video/Picture-in-Picture behavior, sleep timer/fade-out, and release-build startup with R8 enabled.
