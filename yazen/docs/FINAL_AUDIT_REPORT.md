# YAZEN PLAYER — Final Audit Report

## Repository replacement and remote CI validation — 2026-10-25

The connected `Yassine0Xyz/YAZEN-PLAYER` repository was replaced on `main` with
the verified audited source package. The prior `main` commit was
`a5a4dfebc07bbb3f00ca0063195e00b5fc182a48`; it remains recoverable on the
remote branch `backup/pre-yazen-player-replacement-20261025`. The final
repository `main` commit is
`bfe0cb7e64d2f49696db48d0d653ef3f35be7f56`.

The final GitHub Actions run,
[40150115428](https://github.com/Yassine0Xyz/YAZEN-PLAYER/actions/runs/40150115428),
passed on Ubuntu x64 with Flutter 3.47.8. All workflow stages passed:

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze --no-fatal-infos` (warnings/errors remain fatal; the source
  reports informational lints only)
- Focused regression tests: 44 passed
- Full Flutter test suite: 122 passed, 1 skipped
- Android debug validation: `flutter build apk --debug --target-platform android-arm64`

The runner produced `build/app/outputs/flutter-apk/app-debug.apk`. This remote
CI result supersedes the earlier local ARM64 environment blocker for source,
test, and debug-build validation. It does not replace manual device testing,
release signing, visual verification, or production APK/AAB release validation.

**Audit date:** 2026-10-24  
**Source reviewed:** current working tree at `/home/ubuntu/work/yazen-player`, based on the Steps 2–4 source package and including the earlier Step 1 changes.  
**Scope:** final source audit only; no APK/AAB generation or delivery.

## Flutter validation follow-up — 2026-10-25

The requested Flutter/Dart validation was attempted safely from the audited
source. The environment is Ubuntu 24.04.5 LTS on ARM64 (`aarch64`) with 40 GB
free disk space, approximately 6.4 GB available memory, six CPUs, Java/OpenJDK
21.0.12, and working access to the official Flutter release manifest.

The project requires Dart `>=3.7.0 <4.0.0` and Flutter `>=3.47.0`. No Flutter,
Dart, Android SDK, ADB, SDK manager, or Gradle installation was present. The
official Linux Flutter release manifest was checked and contains stable Linux
x64 archives only; it has no official Linux ARM64 stable archive. Installing
the x64 archive on this ARM64 environment would not be a valid validation path,
so no SDK or unrelated system package was installed and no existing tool was
overwritten.

| Command/check | Result |
|---|---|
| `uname -a`, `/etc/os-release`, `df -h`, `free -h`, `nproc` | Passed; environment recorded above. |
| Official Flutter release-manifest network check | Passed; official manifest reachable. |
| `flutter --version` | Blocked: `flutter: command not found`. |
| `dart --version` | Blocked: `dart: command not found`. |
| Java inspection | Available: OpenJDK 21.0.12. |
| Android SDK/ADB/Gradle inspection | Unavailable; no commands or SDK directory found. |
| Project constraint inspection | Passed; Flutter `>=3.47.0`, Dart `>=3.7.0 <4.0.0`. |
| Official ARM64 Flutter archive check | Blocked; no Linux ARM64 stable archive published in the manifest. |
| `flutter pub get` | Not run because compatible Flutter is unavailable. |
| `dart format --output=none --set-exit-if-changed .` | Not run because Dart is unavailable. |
| `flutter analyze` | Not run because Flutter is unavailable. |
| Focused Flutter tests and full `flutter test` | Not run because Flutter is unavailable. |
| Android debug APK validation | Not run because Flutter and Android SDK are unavailable. |

No source-code files were changed during this follow-up. Only this report and
the README Recent Activity were updated with the environment result. The
previous source-level foundation validator remains passing, but that check is
not a substitute for Dart analysis or Flutter tests. Exact next steps are to
run the documented commands on an x64 Linux/macOS/Windows machine with Flutter
3.47+ and Android SDK tooling if Android build validation is required.

## Executive summary

The audit traced the real implementations for playlist artwork history and palettes, playback completion and queue mutation, independent Songs/Videos library controls, Full Player state and feedback, gestures/transitions, media permissions and video playback, persistence, asynchronous cleanup, tests, and project configuration.

Several evidence-backed, narrowly scoped defects were found and corrected. The corrections cover artwork cache identity, palette refresh triggers, persisted playing-state restore, stale now-playing state after removing the last queue item, queue reorder-to-end handling, stale videos after permission loss, unsupported native video-control channels, paused Full Player queue selection, reduced-motion route behavior, the vendored `video_thumbnail` SDK constraint, and the stale foundation validator. A focused palette cache regression test was added.

The source now has a successful remote CI validation for dependency resolution,
formatting, analysis, focused/full tests, and an Android debug build. It is not
yet a release-signing or device-validation result: native behavior, real
`just_audio` repeat/shuffle completion, video URI compatibility, visual
fidelity, and several persistence failure paths still require manual/device
verification.

## Step 1 presence

Step 1 is present in the final source. The following earlier behavior remains in the reviewed tree:

- Playlist addition history is persisted and used to recover the latest remaining artwork after reorder/removal.
- Legacy playlist data without addition history has a fallback path.
- Favorites and custom playlist cards use the latest available track artwork while empty collections retain icons.
- Artwork-derived palettes are independently cached and have contrast-aware fallback behavior.
- Existing playlist manager regression tests remain present.

The audit found and fixed a cache-identity defect in this Step 1 area: palette cache entries were keyed only by `track.id`, and collection cards refreshed only on ID changes. Cache keys and card refresh identity now include source, media kind, and artwork URI, while theme accent/surface changes also trigger a fresh request.

## Confirmed changes made during Step 5

### Playback and queue

- `restoreLastPlayback()` now calls `play()` when the persisted `PlaybackSnapshot.playing` value is true. A paused snapshot remains paused.
- Removing the final queue item now clears `_activeTrack` and publishes `mediaItem.add(null)` in addition to clearing persisted playback state.
- Queue reorder callbacks normalize Flutter’s end-position index before calling the handler, so dragging an item to the final position is not rejected.
- Full Player queue-peek selection now uses the serialized `playQueueIndex()` API, so selecting a queued item while paused starts playback consistently with queue-row playback.

### Artwork and library/media state

- `ArtworkPaletteService` now keys its cache by track ID, source, media kind, and artwork URI.
- Collection-card palette requests now refresh when artwork identity or theme contrast inputs change, even when the track ID is unchanged.
- Permission-loss handling now clears device videos as well as audio-derived library state, preventing stale video results from surviving denied/revoked permission.
- Android-only volume, brightness, and picture-in-picture channel calls now catch `MissingPluginException`/`PlatformException` and show graceful unavailable feedback on unsupported platforms.

### Motion and tooling

- Full Player route transitions now bypass visual route animation when reduced motion is enabled, and fixed Full Player AnimatedSwitcher/artwork durations use the project’s `Motion` abstraction.
- The vendored `third_party/video_thumbnail` package constraint was corrected from `<3.0.0` to `<4.0.0`, removing the direct contradiction with the app’s Dart `>=3.7.0 <4.0.0` constraint.
- `tool/validate_foundation.py` was updated to the current source tree, dependency set, and actual Android activity path. Its unreliable raw delimiter-count heuristic was removed.
- `test/artwork_palette_service_test.dart` now covers same-ID tracks with changed artwork identities.
- The README test inventory now includes `test/track_content_transition_test.dart`.

## Feature-by-feature result

| Area | Result | Evidence and notes |
|---|---|---|
| Playlist addition history, removal, reorder, legacy data | **Pass — source review** | Persistence and fallback paths are present; Flutter execution was unavailable. |
| Playlist artwork fallback and card palette identity | **Issue Fixed** | Cache/card identity defects were confirmed and corrected; widget-level runtime verification remains unexecuted. |
| Global palette/dynamic-color integration | **Unverified** | Source paths are present, but device artwork loading and visual contrast were not tested. |
| Repeat Off / Repeat One / Repeat All natural completion | **Unverified** | Handler maps modes to `just_audio` loop modes and has a guarded Repeat All fallback, but no executable test of real processing-state completion was possible. |
| Shuffle and repeat boundaries | **Unverified** | Persisted and forwarded in source; shuffle order, one-item Repeat All, and manual boundary behavior need Flutter/audio tests. |
| Persisted playback restore | **Issue Fixed** | `playing=true` is now honored; no runtime fake-player test could be executed. |
| Queue removal and active media state | **Issue Fixed** | Final-item removal now clears active/media-item state. Runtime stream verification remains pending. |
| Queue reorder to final position | **Issue Fixed** | UI end-index normalization was added. A widget/integration test remains recommended. |
| Serialized queue playback | **Pass — source review** | Queue-row and Full Player queue-peek paths use the serialized handler API. Race tests were not run in this environment. |
| Songs/Videos search/sort/filter isolation | **Pass — controller source review** | State is tab-keyed; PageView/widget transition behavior remains unverified. |
| Songs/Videos layout and density persistence | **Pass — source review** | Separate persisted fields and toolbar controls exist; Flutter persistence test was not run. |
| Video permission/error UI | **Issue / Unverified** | Stale videos on permission loss were fixed. Video-tab permission/error rendering and platform recovery still need widget/device tests. |
| Video playback and native controls | **Issue Fixed — source level** | Missing native control channels now degrade safely; URI/plugin playback still needs Android/Linux verification. |
| Full Player artwork style | **Pass — source review** | Reactive sheet state and serialized preference writes are present; preference failure behavior remains untested. |
| Full Player queue selection | **Issue Fixed** | Paused queue selection now starts playback through the handler. |
| Sleep timer lifecycle and feedback | **Unverified** | Source includes activation, cancellation, expiration, and live status; timer lifecycle and native pause failure paths need runtime tests. |
| Equalizer and surround feedback | **Unverified** | Equalizer rollback was improved earlier, but preset/native failure and surround reactivity still lack focused executable tests. |
| Mini Player gesture mechanics | **Pass — source review** | Axis locking/bounds/cancellation paths are structurally present; runtime checks unavailable. |
| Full Player swipe transitions and reduced motion | **Issue Fixed / Unverified** | Reduced-motion route handling was corrected; diagonal, cancellation, disposal, and transition-race tests remain unexecuted. |
| Lyrics, favorites, navigation, visualizers | **Pass — source review / runtime unverified** | Existing implementations and tests were inspected; no current Flutter test run was possible. |
| Persistence and asynchronous ordering | **Unverified risk** | Several stores ignore false `SharedPreferences` return values or lack comprehensive last-write-wins protection. These were documented rather than broadly refactored. |
| Dependency and foundation tooling | **Issue Fixed — source level** | Vendored SDK contradiction and stale validator were corrected; `pub get` was unavailable. |
| Android/Linux build readiness | **Unverified** | Native build tools and Flutter CLI were unavailable. |

## Files inspected

The audit inspected, among other relevant files:

- `lib/services/local_playlist_manager.dart`
- `lib/services/artwork_palette_service.dart`
- `lib/widgets/media_artwork.dart`
- `lib/models/media_track.dart`
- `lib/services/hybrid_audio_handler.dart`
- `lib/services/playback_state_store.dart`
- `lib/services/playback_policies.dart`
- `lib/services/serial_async_queue.dart`
- `lib/controllers/hybrid_music_controller.dart`
- `lib/screens/home/home_screen.dart`
- `lib/screens/library/local_media_screen.dart`
- `lib/services/library_display_settings.dart`
- `lib/screens/settings/settings_screen.dart`
- `lib/screens/player/full_player_screen.dart`
- `lib/screens/player/yazen_video_player.dart`
- `lib/screens/player/yazen_video_player_screen.dart`
- `lib/widgets/mini_player.dart`
- `lib/widgets/mini_player_gesture_surface.dart`
- `lib/services/media_library_service.dart`
- `test/artwork_palette_service_test.dart`
- `test/local_playlist_manager_test.dart`
- `test/hybrid_audio_queue_race_test.dart`
- `test/playback_state_store_test.dart`
- `test/playback_policies_test.dart`
- `test/library_display_settings_test.dart`
- `test/track_content_transition_test.dart`
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`
- `third_party/video_thumbnail/pubspec.yaml`
- `tool/validate_foundation.py`
- Android and Linux project configuration files

## Files modified

- `lib/services/artwork_palette_service.dart`
- `lib/screens/library/local_media_screen.dart`
- `lib/services/hybrid_audio_handler.dart`
- `lib/controllers/hybrid_music_controller.dart`
- `lib/screens/queue/queue_screen.dart`
- `lib/screens/player/full_player_screen.dart`
- `lib/screens/player/yazen_video_player.dart`
- `third_party/video_thumbnail/pubspec.yaml`
- `tool/validate_foundation.py`
- `test/artwork_palette_service_test.dart`
- `README.md`
- `docs/FINAL_AUDIT_REPORT.md`

## Checks actually executed

The following checks were actually run in this environment:

1. `command -v flutter` and `command -v dart` — both unavailable.
2. `python3 -m py_compile tool/validate_foundation.py` — passed.
3. `python3 tool/validate_foundation.py` — passed after updating the validator.
4. A Python dependency/source consistency script — passed after correction: app SDK is `>=3.7.0 <4.0.0`, vendored video-thumbnail SDK is `>=2.16.0 <4.0.0`, and the lockfile points to the local package.
5. A lightweight required-file/source-presence check over all modified files — passed.
6. Source inspection and structured parallel audit of eight feature areas plus synthesis — completed; findings are source-review findings, not runtime test results.

## Checks not executed

These checks were not executed because Flutter/Dart and the corresponding build tools were unavailable:

- `dart format --output=none --set-exit-if-changed ...`
- `flutter pub get`
- `flutter analyze`
- Focused Flutter tests, including the newly updated palette test and display-settings tests.
- Full `flutter test`.
- Android APK/AAB builds and Android emulator/device tests.
- Linux Flutter/CMake build and Linux runtime tests.
- Native MediaStore, content-URI, video thumbnail, notification, audio completion, and platform-channel tests.

Historical README entries mention prior Flutter/analyzer/test/build runs from earlier project activities. Those historical claims were not independently rerun during this final audit and are not treated as current validation evidence.

## Remaining confirmed or source-level risks

The following concerns remain because broad refactoring or speculative behavior changes were outside the authorized scope:

- Real `just_audio` LoopMode One/All completion, shuffle ordering, one-item Repeat All, manual skip boundaries, and queue replacement behavior require executable handler tests.
- Several persistence stores ignore `SharedPreferences` methods that return `false`, and some settings/equalizer paths can still race without a complete last-write-wins protocol. The project needs a defined failure policy before broad persistence changes are made.
- Equalizer preset/native failure feedback, surround-stream reactivity, artwork preference write failures, and sleep-timer pause failure feedback remain insufficiently covered.
- Video permission/error rendering, Android partial visual-media access, MediaStore content URIs, thumbnail behavior after revocation, and Linux player-control degradation need platform tests.
- Full Player gesture arbitration, cancellation, queue changes during animation, disposal, Hero transitions, and reduced-motion widget behavior need Flutter widget tests.
- The PageView architecture supplies controller state based on the globally selected tab; adjacent-page/swipe behavior should be confirmed with a widget test before changing architecture.
- Imported Linux files are held in memory only; persistence expectations should be confirmed before changing that behavior.

## Recommended manual test scenarios

1. Launch with a saved queue whose snapshot has `playing=true` and verify playback resumes; repeat with `playing=false`.
2. Remove the last queue item and confirm queue, Mini Player, Full Player, notification media item, and persisted state all clear.
3. Drag queue items upward, downward, and to the final slot; test while playback is active and while paused.
4. Exercise Repeat Off, Repeat One, and Repeat All with one and multiple tracks, including Shuffle and manual next/previous at boundaries.
5. Create/reorder/remove playlist tracks and verify the latest remaining artwork, legacy data fallback, missing artwork, and readable palette contrast.
6. Change artwork URI/source while retaining a track ID and change the app theme; verify collection-card palette refresh.
7. Revoke media permission while Videos is visible, resume the app, restore permission, and confirm stale device videos do not remain.
8. Open a video from a file URI and content URI on Android and a file URI on Linux; test thumbnail, playback, vertical controls, and Picture-in-Picture fallback.
9. Open Full Player while paused, select another queue item, and verify playback starts; test artwork style, timer Off/duration/end-of-track, equalizer failure, lyrics, favorites, and rapid controls.
10. Enable reduced animations and verify route entry, track transitions, and swipe settling are visually immediate and stable.
11. Test Mini Player diagonal drags, cancellation, boundary swipes, rapid push/pop, and Full Player disposal during a transition.

## Final readiness assessment

**Overall: source-audited, targeted corrections applied, but not release-ready.**

The codebase has a coherent implementation and the requested Step 1–4 work is present. The highest-confidence defects found by source audit were corrected without redesigning the product. However, the absence of Flutter/Dart/build tooling prevents the checks that would establish compile correctness, dependency resolution, test behavior, native integration, and device readiness. A Flutter-enabled validation pass is required before release or production-readiness claims.
