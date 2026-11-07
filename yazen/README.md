# YAZEN Player

YAZEN is a local-first Flutter music and video player for Android and Linux.
It combines a device media library, local playback, playlists, a persistent
queue, artwork, lyrics, and playback-aware visual effects in a dark, premium
interface.

> This README documents the implementation and project configuration present
> in this source tree. Platform behavior and media format support can vary with
> the Android device, operating system codecs, and Linux system libraries.

## Contents

- [Product scope](#product-scope)
- [Features](#features)
- [Supported platforms](#supported-platforms)
- [Project requirements](#project-requirements)
- [Getting started](#getting-started)
- [Building Android](#building-android)
- [Building Linux](#building-linux)
- [Architecture](#architecture)
- [Source tree](#source-tree)
- [Dependencies](#dependencies)
- [Permissions, privacy, and network use](#permissions-privacy-and-network-use)
- [Automated and manual testing](#automated-and-manual-testing)
- [Known limitations](#known-limitations)
- [Release signing and secret handling](#release-signing-and-secret-handling)
- [Current build measurements](#current-build-measurements)
- [Project documentation](#project-documentation)

## Recent Activity

### Recent Activity: 2026-11-03 — V5 comprehensive performance and reliability pass

Built a source-level V5 iteration on the cumulative Iteration 5 source archive.
The pass targets avoidable library browsing work, particularly Android video
MediaStore scans and thumbnail extraction, plus search-cache invalidation,
dynamic sort callbacks, viewport memory, and continuous player decoration
while scrolling. It retains the existing YAZEN audio engine and service
architecture.

The foundation validator and all 18 V5 source guardrails passed on this source tree. Flutter/Dart, Gradle, and
the Android SDK are unavailable in the editing environment, so formatting,
analysis, Flutter tests, Android compilation, GitHub Actions for V5, and
real-device profiling have not been run. The added sort regression test is
source-only until run in CI. No claim of zero lag or release readiness is made.

See [the comprehensive V5 engineering audit and change log](docs/V5_COMPREHENSIVE_AUDIT_AND_CHANGELOG.md)
and [the V5 device validation matrix](docs/V5_DEVICE_TEST_MATRIX.md) for exact
file changes, Lark findings, retained architecture, known limits, and the
manual test plan.

Files changed in this V5 pass relative to the supplied Iteration 5 baseline:

- `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt`
- `lib/screens/library/local_media_screen.dart`
- `lib/screens/player/yazen_video_player.dart`
- `lib/screens/search/search_screen.dart`
- `lib/services/artwork_disk_cache.dart`
- `lib/services/library_data_engine.dart`
- `lib/widgets/echo_motion.dart`
- `lib/widgets/media_artwork.dart`
- `lib/widgets/video_thumbnail.dart`
- `third_party/video_thumbnail/android/src/main/java/xyz/justsoft/video_thumbnail/VideoThumbnailPlugin.java`
- `third_party/video_thumbnail/LOCAL_PATCHES.md`
- `test/library_data_engine_test.dart`
- `tool/validate_v5_performance.py`
- `README.md`
- `docs/V5_COMPREHENSIVE_AUDIT_AND_CHANGELOG.md`
- `docs/V5_DEVICE_TEST_MATRIX.md`

### Recent Activity: 2026-10-25 — Repository replacement and remote CI validation

The connected `Yassine0Xyz/YAZEN-PLAYER` repository was replaced on `main` with
the verified audited source package. The previous `main` commit was
`a5a4dfebc07bbb3f00ca0063195e00b5fc182a48`; it remains recoverable on the
remote backup branch
`backup/pre-yazen-player-replacement-20261025`. The final `main` commit is
`bfe0cb7e64d2f49696db48d0d653ef3f35be7f56`.

GitHub Actions run
[40150115428](https://github.com/Yassine0Xyz/YAZEN-PLAYER/actions/runs/40150115428)
passed on Ubuntu x64 using Flutter 3.47.8. Formatting, analysis, 44 focused
regression tests, the full suite (122 passed, 1 skipped), and
`flutter build apk --debug --target-platform android-arm64` all passed. The CI
analyzer uses `--no-fatal-infos` because the audited source has informational
lints; warnings and errors remain fatal. The Android build emitted the expected
debug APK at `build/app/outputs/flutter-apk/app-debug.apk` on the runner.

### Recent Activity: 2026-10-25 — Flutter validation environment check

The requested Flutter/Dart validation was attempted without modifying the
audited source. This environment is Ubuntu 24.04.5 LTS on ARM64 with Java 21,
working network access, 40 GB free disk space, and approximately 6.4 GB
available memory, but it has no Flutter, Dart, Android SDK, ADB, SDK manager,
or Gradle installation. The project requires Flutter `>=3.47.0` and Dart
`>=3.7.0 <4.0.0`.

The official Flutter Linux release manifest was reachable, but provides stable
Linux x64 archives only and no Linux ARM64 archive. Installing the x64 SDK on
this ARM64 environment would not be a valid validation path, so installation
was stopped safely without overwriting tools or changing source code.

Consequently, `flutter pub get`, Dart formatting, `flutter analyze`, focused
tests, full `flutter test`, and Android APK validation remain blocked by the
environment. The exact command results and next steps are recorded in
`docs/FINAL_AUDIT_REPORT.md`. No release-readiness claim is made.

### Recent Activity: 2026-10-24 — Step 5 final audit and targeted corrections

Completed a source-only final audit of Steps 1–4 across playlist artwork and
palettes, playback completion and queue mutations, Songs/Videos library state,
Full Player controls, gestures/transitions, media permissions/video playback,
persistence, and project tooling. Confirmed and fixed targeted issues for
artwork cache identity and card refresh, persisted playing-state restore,
last-item queue cleanup, reorder-to-end handling, stale videos after permission
loss, unsupported video-control channels, paused Full Player queue selection,
reduced-motion route behavior, the vendored video-thumbnail SDK constraint, and
the stale foundation validator. Added focused palette cache regression coverage.

The updated source-level foundation validator passes, but Flutter/Dart are not
available in this environment. Therefore `flutter pub get`, formatting,
analyzer, Flutter tests, Android/Linux builds, and device/runtime verification
remain unexecuted for this audit. See `docs/FINAL_AUDIT_REPORT.md` for the
feature table, exact checks, remaining risks, and manual test plan.

Files changed for this audit:

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

### Recent Activity: 2026-10-24 — Steps 2, 3 & 4 core features

Implemented the requested Repeat All, independent library controls, and Full
Player fixes without changing the Step 1 playlist artwork/color behavior.
Repeat All now has a guarded queue-boundary fallback in the existing completion
path, and queue-row Play now uses serialized handler state. Songs and Local
Videos now keep independent search, sort/filter, and presentation state;
Videos has its own persisted List/Grid and density settings, video-relevant
sort options, and an in-section search/presentation toolbar. The Full Player
artwork-style selector is reactive while its sheet remains open, preference
writes are last-write-wins, sleep-timer chips/status respond to the handler's
live state, and equalizer state rolls back with feedback when application fails.

Files changed for these steps:

- `lib/services/hybrid_audio_handler.dart`
- `lib/services/library_display_settings.dart`
- `lib/controllers/hybrid_music_controller.dart`
- `lib/screens/home/home_screen.dart`
- `lib/screens/library/local_media_screen.dart`
- `lib/screens/player/full_player_screen.dart`
- `lib/screens/queue/queue_screen.dart`
- `test/library_display_settings_test.dart`
- `README.md`

Validation performed on 2026-10-24:

- Source-level review, targeted reference checks, archive exclusion checks, and
  expected-file checks were performed.
- Flutter and Dart executables were unavailable in this environment, so
  formatting, analyzer, focused Flutter tests, the full test suite, and APK
  builds were not run. No APK was built or delivered.

### Recent Activity: 2026-10-24 — Playlist artwork and card palettes

Implemented **Step 1 — Playlist Artwork & Dynamic Colors** only. Custom playlist
cover selection now persists addition history, so the cover is the most recently
added remaining track even after list reordering or removal. Favorites and custom
playlist cards show the latest available track artwork when non-empty; empty
collections retain their recognizable icons. Playlist cards use independently
cached artwork-derived tonal palettes with readable contrast and a stable theme
fallback when artwork is unavailable. Existing global Dynamic Colors, Ambient
Color Flow, Mini Player, Full Player, and library controls were not changed.

Files changed for this step:

- `lib/services/local_playlist_manager.dart`
- `lib/services/artwork_palette_service.dart`
- `lib/screens/library/local_media_screen.dart`
- `test/local_playlist_manager_test.dart`
- `README.md`

Validation performed on 2026-10-24:

- Source inspection and static change review completed.
- Flutter and Dart SDK executables were not available in this environment, so
  formatting, analyzer, focused tests, and the full test suite could not be
  executed. No APK build was run, per the source-only delivery requirement.
- ZIP integrity and expected source-file inclusion were verified after export.

### Recent Activity: 2026-10-24

Implemented **Step 1 — Player Experience** only. The Full Player now uses a
more compact vertical layout, combines `NOW PLAYING` and `LOCAL AUDIO` into one
top context row, and keeps the existing dynamic artwork colors and real PCM
visualizer. Horizontal track navigation now provides live drag feedback and a
short settle animation before the queue advances; the existing swipe, queue,
and previous/next behavior remains in place. The Mini Player to Full Player
route transition now uses a shorter fade/slide/scale transition that works with
the existing artwork/title Hero elements. The library Selection Panel was
reduced to a single compact action row while retaining exit, select/clear all,
playlist, queue, favorites, and more-actions behavior.

Files changed for this step:

- `lib/screens/player/full_player_screen.dart`
- `lib/screens/library/local_media_screen.dart`
- `README.md`

Validation performed on 2026-10-24:

- `dart format` completed for the four player/library motion files; only
  `full_player_screen.dart` required formatting changes.
- `flutter analyze --no-fatal-infos --no-fatal-warnings` completed without
  errors. Remaining output is informational lint in pre-existing areas such as
  async context usage in `home_screen.dart` and the vendored thumbnail plugin.
- Focused tests passed: `audio_visualizer_test.dart`,
  `now_playing_widgets_test.dart`, `playback_state_store_test.dart`, and
  `playback_policies_test.dart` (`25` tests passed).
- A full `flutter test` run was also executed during this activity. It did not
  pass completely: existing `hybrid_audio_queue_race_test.dart` cases failed
  around folder-library refresh/play-history/permission recovery. The tested
  visualizer, now-playing, playback-state, and playback-policy groups passed.
- `flutter build apk --debug --target-platform android-arm64` completed
  successfully after these changes. The generated debug APK was 91 MB and its
  SHA-256 was
  `939cfa12b484dd0a93f9720b29bf8dcdcd87fdb9e418111bbb204bfa170fe21e`.
- No physical Android-device or screenshot-based visual verification was
  performed in this step.

### Full Player swipe transition follow-up — 2026-10-24

Root cause: the swipe path mixed queue-index direction with physical finger
direction. The queue-index listener could overwrite the direction while the
incoming phase was being built, and the accepted-swipe parent translation
opposed the outgoing content translation, nearly cancelling visible motion.
That parent transform also moved the visualizer and transport controls.

The fix uses a separate physical swipe direction and one 190 ms controller
shared by the artwork and keyed track metadata. At the midpoint, after the
outgoing content is hidden, the existing serialized skip runs once and the
actual handler-provided track is shown sliding/fading in from the opposite
side. If the item changes while the outgoing animation is running, the swipe
does not add a second skip. Cancelled, boundary/no-op, and failed operations
restore the current content; animation state is cleared on completion or route
disposal. Drag motion is limited to artwork and metadata; the PCM visualizer
and transport controls remain in place and connected to live playback state.
The existing keyed switchers continue to handle track changes initiated
outside this swipe transition.

Files changed for this follow-up:

- `lib/screens/player/full_player_screen.dart`
- `test/track_content_transition_test.dart`
- `README.md`

Validation performed in this environment:

- `dart format lib/screens/player/full_player_screen.dart test/track_content_transition_test.dart` completed.
- `flutter test test/track_content_transition_test.dart` passed (2 tests), checking the actual opacity and direction-driven slide values.
- `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` completed without errors; 12 informational lints remain in other existing project files.
- The full `flutter test` run had 115 passing tests and 4 failures in existing library/permission cases: `opening a folder reuses the loaded library tracks`, `folder queries use the refreshed library snapshot`, `play-history updates retain identities of cached library lists`, and `permission denial is recovered on resume, refresh, and request` in `hybrid_audio_queue_race_test.dart`.
- `flutter build apk --debug --target-platform android-arm64` succeeded with
  Flutter 3.47.8 and Android SDK 36. The output was
  `build/app/outputs/flutter-apk/app-debug.apk` (91 MB); SHA-256:
  `574973a329ab85cf7c59f4c173e64974854bdfee4b63b77b90f19dfdabad74c7`.
- No real Android-device, emulator, or screenshot-based visual verification has been performed.

### Player polish and gesture reliability refinement — 2026-10-24

The Mini Player keeps its approved proportions, artwork placement, title and
transport controls, while its surface now uses a restrained vertical tonal
blend, slightly clearer active border treatment, and a low-intensity active
accent shadow. The progress treatment and Dynamic Colors behavior remain
unchanged.

The Full Player swipe recognizer was accepting only long, relatively fast
gestures. The acceptance rules now allow a deliberate slow horizontal drag,
retain a shorter fast-flick path, require horizontal dominance over vertical
movement, and derive next/previous direction from the actual travelled
direction rather than a noisy release velocity. The existing serialized
track-change guard and coordinated slide/fade transition remain the single
transition path, so rapid duplicate skips and boundary no-ops continue to be
protected.

The Mini Player gesture surface now locks to the first intentional axis,
follows upward motion farther and more naturally, and only expands for an
upward gesture. Horizontal playback gestures therefore do not compete with
the expand action, and downward/incomplete drags settle without navigation.

Files changed for this refinement:

- `lib/widgets/mini_player.dart`
- `lib/widgets/mini_player_gesture_surface.dart`
- `lib/screens/player/full_player_screen.dart`
- `test/mini_player_gesture_surface_test.dart`
- `README.md`

Validation status in this environment:

- The supplied ZIP was extracted and the changed source and existing gesture
  tests were inspected.
- `flutter` and `dart` were not installed in the execution environment, so
  `dart format`, Flutter analysis, focused tests, the broader test suite, and
  the debug APK build could not be run here.
- No physical-device, emulator, screenshot, or runtime gesture verification
  was performed. The Flutter-enabled environment should run formatting,
  analysis, the focused Mini Player and transition tests, the full suite, and
  a debug APK build before release.

## Product scope

YAZEN is designed to play audio and video files available locally on the
device or selected by the user. Android uses the device media library. Linux
provides a desktop file picker. Playback and library data are local-first.

### Project identity

- Flutter package name: `yazen`.
- Product name: `YAZEN`.
- Manifest version: `0.1.3+12` (`versionName` / `versionCode`).
- Android application ID and namespace: `com.yassine.yazen`.
- Android launcher label: `YAZEN`.
- Linux runner binary name: `hybrid_music_player`.

The Settings screen reads the displayed app version from `package_info_plus`,
while `pubspec.yaml` remains the authoritative package/build version.

YAZEN is a local-first music and video player focused on the device media library, background playback, playlists, lyrics, visualizer, and playback controls.

Lyrics are the exception to the local-only media model: optional lyrics lookup
can use public lyrics services after local and embedded sources have been
checked. See [Lyrics](#lyrics).

## Features

### Library and browsing

- Android audio and video library discovery through `on_audio_query`.
- Runtime media permission handling, refresh, and permission recovery.
- Linux audio and video file selection through the desktop file picker.
- Songs, videos, artists, albums, folders, device playlists, Favorites, custom
  playlists, and Hidden Files views.
- In-memory search across local track metadata.
- Sorting by supported library fields, including name, artist, duration,
  date, size, play count, and last played.
- Favorites, imported-file, and missing-album-metadata filters.
- List and Grid presentation, with persisted layout and density preferences.
- Folder selection based on normalized full paths rather than partial-name
  matching. Opening a folder filters the loaded library snapshot; refresh the
  library after device media changes.
- Multi-selection actions for supported library and playlist operations.

### Audio playback

- Local playback through `just_audio`, integrated with Flutter's `audio_service`
  background media controls.
- Queue replacement, append, reorder, remove, clear, next, previous, and
  automatic next-track behavior.
- Repeat Off, Repeat One, and Repeat All.
- Persistent playback and queue restoration where the platform and source file
  permit it.
- Playback speed controls.
- Android notification, lock-screen, headset, and media-button integration.
- Mini player and full player.
- Audio-session/focus handling and interruption policies.
- Android equalizer controls and optional surround effect where available.
- Sleep timer options, including end-of-track/end-of-queue behavior and
  fade-out.

### Video playback

- Local video discovery on Android and video file selection on Linux.
- Video playback UI and thumbnail generation through `video_player` and the
  project's `video_thumbnail` plugin fork.
- Platform-supported picture-in-picture and screen-on behavior where available.

### Playlists and personal library state

- Persistent user playlists, independent of device playlists.
- Add and remove tracks, playlist cover selection, and playlist rename.
- Playlist names are trimmed; blank names are rejected. Duplicate names are
  allowed, while playlist IDs and contents remain separate.
- Favorites, hidden-track state, play history, play counts, and per-track
  metadata overrides.
- User state is stored locally using `shared_preferences`; original media files
  are not copied into the app's playlist store.
- Linux playlists can refer to local file URIs. Moving or deleting a source file
  may make that playlist entry unavailable.

### Artwork, lyrics, and visual effects

- Local artwork display with caching and content-aware crop handling.
- Cached artwork palette extraction used by optional dynamic artwork colors.
- Optional artwork-derived control and mini-player accent colors; the selected
  theme remains the fallback.
- Ambient Color Flow: an optional, artwork-informed ambient player effect.
- Playback-aware audio visualizer based on real PCM and FFT data. It does not
  fabricate spectrum motion when audio data is unavailable.
- Beat detection and playback-energy support for visual effects.
- Motion preferences, reduced-motion awareness, haptics, and animated controls.
- Lyrics from local sidecars, embedded ID3 metadata, local cache, and optional
  online lookup.

### Lyrics

Lyrics resolution checks local sources before network services:

1. Sidecar `.lrc`, `.txt`, or supported lyrics files beside the media file.
2. Embedded ID3 USLT/SYLT data where supported.
3. Previously cached lyrics.
4. LRCLIB exact/validated lookup.
5. Lyrics.ovh plain-text fallback where available.

Synchronized lines and word-level timing are shown when the source provides
that timing. Network lookup is optional; failure to reach a lyrics service
should not prevent local playback.

### Settings and presentation

- Dark/light themes and theme customization.
- List/Grid library presentation and density preferences.
- Playback speed and platform equalizer settings.
- Visualizer and Ambient Color Flow controls.
- Dynamic artwork palette controls.
- Sleep timer and fade-out controls.
- Motion and haptic preferences.

## Supported platforms

| Platform | Current support |
|---|---|
| Android | Primary mobile target. Debug and signed Release APKs can be built. Device media access and playback depend on permissions and platform codecs. |
| Linux desktop | Supported development target. Uses a file picker for local files; PCM spectrum analysis depends on the system `ffmpeg` executable. |
| iOS | Not currently a build target. The directory contains generated Flutter/plugin support files but no Xcode project. |
| Web / Windows / macOS | Not documented or validated as supported application targets. Some dependencies may include platform packages transitively. |

## Project requirements

- Flutter **3.47 or newer**.
- Dart **3.7 or newer**.
- Android SDK/NDK versions selected by the installed Flutter SDK and Android
  Gradle configuration. The current project compiles against Android SDK API
  36.
- Java 17 for the configured Android Gradle build.
- Linux builds additionally require CMake, Ninja, GTK 3 development headers,
  PulseAudio development headers, Clang, and `ffmpeg`.

Check the actual local toolchain with:

```powershell
flutter --version
flutter doctor -v
```

## Getting started

Run commands from the project root:

```powershell
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
dart format --output=none --set-exit-if-changed lib test tool
```

`pubspec.lock` records the resolved package versions. Do not run dependency
upgrades as part of routine setup; update dependencies as a separate reviewed
change.

## Building Android

### ARM64 Debug APK

Create an ARM64-only Debug APK:

```powershell
flutter build apk --debug --split-per-abi --target-platform android-arm64
```

Expected output:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk
```

The `--split-per-abi` option matters: `--target-platform android-arm64` by
itself can still package additional small ABI libraries from plugins. Inspect
the APK's `lib/` entries and confirm only `lib/arm64-v8a/` is present before
calling it ARM64-only.

Debug APKs contain development/runtime diagnostics and are not representative
of optimized Release size or performance.

### Signed ARM64 Release APK

Release builds are guarded by the app Gradle configuration. A Release build
must use a local production keystore and `android/key.properties`; the build
must not silently fall back to Android's debug signing key.

The properties file follows this shape (use the actual local values; do not
commit the real file):

```properties
storePassword=YOUR_LOCAL_STORE_PASSWORD
keyPassword=YOUR_LOCAL_KEY_PASSWORD
keyAlias=YOUR_LOCAL_ALIAS
storeFile=C:/absolute/path/to/private-keystore.jks
```

The project currently keeps its private keystore outside the project folder.
`android/key.properties`, JKS, and keystore files are excluded by existing
ignore rules. **Never put actual passwords, private keys, or keystore bytes in
this README or in source control.** Keep a secure independent backup of the
keystore and credentials; losing the signing key can prevent compatible
updates to an already distributed app.

PowerShell command (the Gradle property is passed explicitly to the Gradle JVM):

```powershell
$env:ORG_GRADLE_PROJECT_production = "true"
$env:GRADLE_OPTS = "-Dorg.gradle.project.production=true"
try {
    flutter build apk --release --target-platform android-arm64 --split-per-abi
}
finally {
    Remove-Item Env:ORG_GRADLE_PROJECT_production -ErrorAction SilentlyContinue
    Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue
}
```

Expected output:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

The Release build enables Android code shrinking and resource shrinking, and
Flutter's normal Release pipeline uses AOT compilation and tree-shakes statically
referenced Material icons. Always verify the resulting APK signature with
Android `apksigner verify --verbose --print-certs` and inspect its actual ABI
contents. Building an APK alone does not establish that it has been tested on
a physical device.

### Android signing safeguard

`android/app/build.gradle.kts`:

- Reads `android/key.properties` only when the production Gradle property is
  enabled.
- Checks the required signing values and verifies that the configured keystore
  file exists.
- Fails Release tasks unless production signing was explicitly enabled.
- Applies minification and resource shrinking to the Release build type.

Do not bypass these checks or replace production signing with debug signing for
distribution.

## Building Linux

Install the platform development packages on a supported Linux distribution.
For Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  cmake ninja-build pkg-config libgtk-3-dev libpulse-dev ffmpeg clang
```

Then build and optionally run:

```bash
flutter build linux --debug
flutter run -d linux
```

Linux's PCM visualizer decodes the selected local audio file via the system
`ffmpeg` executable; it does not use Android's audio capture APIs. Linux has no
Android-style automatic MediaStore scan or Android runtime media permission
flow.

## Architecture

```text
Flutter UI
  HomeScreen / library, search, collection, queue, player and settings screens
       |
       +-- HybridMusicController
       |     Library snapshot, filters, sorting, selection and UI actions
       |
       +-- HybridAudioHandler
       |     just_audio player, queue, playback state, audio session,
       |     notification integration, equalizer and sleep timer
       |
       +-- Services
             MediaLibraryService       Android media query and permissions
             LocalPlaylistManager      Favorites, playlists and local metadata
             LibrarySearchService      In-memory local search
             LyricsService             Sidecar/embedded/cache/optional network
             ArtworkPaletteService     Artwork color extraction/cache
             PlaybackEnergyService     Playback energy and PCM coordination
             LinuxPcmSpectrumService   Linux ffmpeg PCM path
```

`MediaTrack` is the shared local-media model. `HybridMusicController` owns
library-facing state and delegates playback to `HybridAudioHandler`.
`LocalPlaylistManager` persists user-created collections and metadata. Flutter
`Provider` is used to expose state to screens while the audio handler publishes
playback state through `audio_service`.

## Source tree

```text
.
├── android/
│   ├── app/
│   │   ├── build.gradle.kts             Android app, signing guards, shrinking
│   │   └── src/main/
│   │       ├── AndroidManifest.xml      App components and Android permissions
│   │       ├── java/                    Generated Flutter plugin registration
│   │       ├── kotlin/                  YAZEN Android platform bridge
│   │       └── res/                     Launcher, notification and app resources
│   ├── build.gradle.kts                 Shared Android Gradle build directory
│   ├── gradle.properties                AndroidX and Gradle options
│   ├── key.properties.example           Safe template; contains no credentials
│   └── settings.gradle.kts              AGP/Kotlin/Flutter plugin versions
├── assets/
│   ├── fonts/                           Plus Jakarta Sans variable font
│   ├── yazen_app_icon_master.png        Runtime Flutter home logo
│   ├── yazen_app_icon_source.png        Original design/source artwork
│   └── yazen_notification_icon.png      Source notification artwork
├── docs/                                Design, readiness and manual test docs
├── lib/
│   ├── controllers/                     Library/UI state coordination
│   ├── core/                            Haptics and theme primitives
│   ├── models/                          MediaTrack and local domain models
│   ├── screens/
│   │   ├── collections/                 Favorites and playlist details
│   │   ├── effects/                     Equalizer UI
│   │   ├── home/                        Main shell, tabs and track rows
│   │   ├── library/                     Local media and entity tracks
│   │   ├── player/                      Audio and video players
│   │   ├── queue/                       Playback queue UI
│   │   ├── search/                      Local search screen
│   │   └── settings/                    App and playback settings
│   ├── services/                        Playback, library and persistence logic
│   ├── widgets/                         Reusable player, artwork and motion UI
│   └── main.dart                        Service setup, providers and app entry
├── linux/
│   ├── CMakeLists.txt                   Linux Flutter/GTK build
│   └── runner/                          Native GTK application runner
├── test/                                Dart unit and Flutter widget tests
├── third_party/
│   ├── on_audio_query_android/          Local Android compatibility fork
│   └── video_thumbnail/                Local thumbnail plugin fork
├── tool/                                Project validation/helper scripts
├── pubspec.yaml                         Flutter app and dependency manifest
├── pubspec.lock                         Resolved dependency versions
└── README.md                            Project guide
```

Generated build output, Flutter package metadata, Gradle caches, and local
machine configuration are not source deliverables and should not be committed.
The `ios/` directory currently contains generated support material only; it is
not a complete iOS application target.

### Important implementation files

| File | Responsibility |
|---|---|
| `lib/main.dart` | Initializes audio service/session, theme, local playlists and providers; schedules playback restore after the first frame. |
| `lib/models/media_track.dart` | Local track model shared by library, queue, playlists and players. |
| `lib/controllers/hybrid_music_controller.dart` | Library state, refresh, search/filter/sort integration, selection and playback commands. |
| `lib/services/hybrid_audio_handler.dart` | Audio player lifecycle, playback state, queue, notifications, repeat, speed, equalizer and sleep timer. |
| `lib/services/media_library_service.dart` | Android library queries, permission state and media conversion. |
| `lib/services/local_playlist_manager.dart` | Favorites, custom playlists, metadata overrides, hidden IDs and play history persistence. |
| `lib/services/library_search_service.dart` | In-memory local library search and filtering support. |
| `lib/services/folder_identity.dart` | Full-path folder normalization, identity and track matching. |
| `lib/services/lyrics_service.dart` | Sidecar, embedded, cached, and optional remote lyrics resolution. |
| `lib/services/embedded_id3_lyrics.dart` | Embedded ID3 lyric parsing. |
| `lib/services/artwork_content_cropper.dart` | Content-aware artwork crop decisions. |
| `lib/services/artwork_palette_service.dart` | Artwork palette extraction and cache. |
| `lib/services/playback_energy_service.dart` | Playback energy/PCM work coordination for visual effects. |
| `lib/services/linux_pcm_spectrum_service.dart` | Linux `ffmpeg` decode-to-PCM and spectrum service. |
| `lib/services/playback_state_store.dart` | Local playback/queue snapshot persistence. |
| `lib/services/equalizer_settings_store.dart` | Equalizer and surround preference persistence. |
| `lib/widgets/media_artwork.dart` | Shared local artwork rendering. |
| `lib/widgets/mini_player.dart` | Persistent compact player controls. |
| `lib/widgets/audio_visualizer.dart` | PCM-derived visualizer rendering. |
| `lib/widgets/ambient_color_flow.dart` | Ambient player color effect. |
| `lib/widgets/lyrics_view.dart` | Synchronized/plain lyrics presentation. |
| `lib/screens/library/local_media_screen.dart` | Songs, videos, folders and other library tab UI. |
| `lib/screens/player/full_player_screen.dart` | Full audio player interface. |
| `lib/screens/player/yazen_video_player_screen.dart` | Local video playback interface. |
| `lib/screens/search/search_screen.dart` | Local media search UI. |
| `lib/screens/settings/settings_screen.dart` | Theme, library, playback and visual settings. |

### Dart source inventory

This inventory describes the current Dart source layout; generated Flutter
files and build products are intentionally omitted.

```text
lib/main.dart
lib/controllers/hybrid_music_controller.dart
lib/core/haptics.dart
lib/core/theme/app_theme.dart
lib/core/theme/motion_tokens.dart
lib/core/theme/theme_provider.dart
lib/core/theme/theme_tokens.dart
lib/models/media_track.dart
lib/screens/collections/favorites_screen.dart
lib/screens/collections/playlist_details_screen.dart
lib/screens/effects/equalizer_screen.dart
lib/screens/home/home_screen.dart
lib/screens/home/widgets/library_tabs.dart
lib/screens/home/widgets/track_list_tile.dart
lib/screens/library/entity_tracks_screen.dart
lib/screens/library/local_media_screen.dart
lib/screens/player/full_player_screen.dart
lib/screens/player/yazen_video_player.dart
lib/screens/player/yazen_video_player_screen.dart
lib/screens/queue/queue_screen.dart
lib/screens/search/search_screen.dart
lib/screens/settings/settings_screen.dart
lib/services/ambient_color_flow_settings.dart
lib/services/app_route_observer.dart
lib/services/artwork_content_cropper.dart
lib/services/artwork_palette_service.dart
lib/services/audio_beat_detector.dart
lib/services/dynamic_color_settings.dart
lib/services/embedded_id3_lyrics.dart
lib/services/equalizer_settings_store.dart
lib/services/folder_identity.dart
lib/services/haptic_settings.dart
lib/services/hybrid_audio_handler.dart
lib/services/library_display_settings.dart
lib/services/library_search_service.dart
lib/services/linux_pcm_spectrum_service.dart
lib/services/local_playlist_manager.dart
lib/services/lyrics_service.dart
lib/services/media_library_service.dart
lib/services/media_track_codec.dart
lib/services/playback_energy_service.dart
lib/services/playback_policies.dart
lib/services/playback_state_store.dart
lib/services/serial_async_queue.dart
lib/services/startup_restore.dart
lib/services/visualizer_settings.dart
lib/widgets/alive_effects.dart
lib/widgets/ambient_color_flow.dart
lib/widgets/audio_visualizer.dart
lib/widgets/echo_motion.dart
lib/widgets/lyrics_view.dart
lib/widgets/media_artwork.dart
lib/widgets/mini_player.dart
lib/widgets/mini_player_gesture_surface.dart
lib/widgets/now_playing_scope.dart
lib/widgets/play_pause_morph.dart
lib/widgets/playlist_picker_sheet.dart
lib/widgets/shimmer_skeleton.dart
lib/widgets/theme_picker_sheet.dart
lib/widgets/video_thumbnail.dart
```

## Dependencies

Direct runtime dependencies declared in `pubspec.yaml`:

| Package | Project use |
|---|---|
| `just_audio` | Local audio player and Android audio effects pipeline. |
| `audio_service` | Background playback, media notification and OS transport controls. |
| `audio_session` | Audio focus/session configuration. |
| `on_audio_query` | Android device audio/video metadata and library queries. |
| `video_player` | Local video playback. |
| `video_thumbnail` | Video thumbnail generation; locally overridden by a project fork. |
| `file_picker` | Linux local file selection and cross-platform picker interface. |
| `provider` | UI state dependency injection and listening. |
| `shared_preferences` | Local preferences and serialized user library state. |
| `path` | File path normalization and local file handling. |
| `http` | Optional lyrics lookups. |

Declared version constraints include `just_audio ^0.10.6`,
`audio_service ^0.18.19`, `audio_session ^0.2.2`,
`on_audio_query ^2.9.0`, `video_player ^2.9.2`,
`video_thumbnail ^0.5.3`, `file_picker ^13.1.0`,
`provider ^6.1.5+1`, `shared_preferences ^2.5.3`, `package_info_plus ^10.2.2`,
`path ^1.9.1`, and `http ^1.5.0`. Consult `pubspec.yaml` and `pubspec.lock` for the
authoritative constraints and resolved versions.

`flutter_test` and `flutter_lints` are development dependencies. The
`on_audio_query_android` and `video_thumbnail` dependencies are overridden to
local source under `third_party/`; review those forks when changing plugin
behavior. Do not remove playback, media-library, video, thumbnail, or metadata
packages solely because they appear large.

## Permissions, privacy, and network use

The Android manifest declares access needed for local media, notifications,
network-based lyrics availability, audio-service operation, and wake locks.
Runtime media permission handling is implemented by `MediaLibraryService`.
Android versions differ in audio/video permission requirements and notification
permission behavior.

YAZEN stores local preferences and user-created library metadata on-device.
Audio and video files remain at their original paths and are not uploaded by the
player. Lyrics may be requested from LRCLIB or Lyrics.ovh when available; this
is optional network use. Android cleartext traffic is disabled in the app
manifest.

Do not include personal media, device paths, credentials, `android/key.properties`,
keystores, or local SDK paths in issue reports or source archives.

## Automated and manual testing

Run the automated checks:

```powershell
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
dart format --output=none --set-exit-if-changed lib test tool
```

Current test suites are grouped around:

- Ambient color and visual-effect settings.
- Artwork content cropping, palette caching, and theme behavior.
- Beat detection, playback energy, motion, and audio visualizer rendering.
- Equalizer settings and playback policies.
- Folder identity, media library queries, and `MediaTrack` serialization.
- Library search and display preferences.
- Playlist persistence, rename, favorites, and hidden tracks.
- Queue races, queue state persistence, and playback restoration.
- Lyrics parsing, service fallback, and synchronized lyrics UI.
- Mini-player gesture/stop behavior and now-playing widgets.
- Linux PCM spectrum service (the integration test requires Linux and is
  skipped on unsupported hosts).

Test files currently present:

```text
test/ambient_color_flow_test.dart
test/artwork_content_cropper_test.dart
test/artwork_palette_service_test.dart
test/audio_beat_detector_test.dart
test/audio_visualizer_test.dart
test/echo_motion_test.dart
test/equalizer_settings_store_test.dart
test/folder_identity_test.dart
test/full_player_duration_test.dart
test/haptic_settings_test.dart
test/hybrid_audio_queue_race_test.dart
test/library_display_settings_test.dart
test/library_search_service_test.dart
test/linux_pcm_spectrum_service_test.dart
test/local_playlist_manager_test.dart
test/lyrics_service_test.dart
test/lyrics_view_test.dart
test/media_library_service_test.dart
test/media_track_test.dart
test/mini_player_gesture_surface_test.dart
test/mini_player_stop_test.dart
test/motion_tokens_test.dart
test/now_playing_widgets_test.dart
test/playback_energy_service_test.dart
test/playback_policies_test.dart
test/playback_state_store_test.dart
test/serial_async_queue_test.dart
test/startup_restore_test.dart
test/track_content_transition_test.dart
test/visual_effect_settings_test.dart
```

Manual device scenarios—including permissions, local playback, queue, search,
Favorites, playlist rename, List/Grid, artwork, background controls, video, and
visualizer—are recorded in [`docs/MANUAL_TEST_CHECKLIST.md`](docs/MANUAL_TEST_CHECKLIST.md).
Automated tests do not replace a real device smoke test.

Additional validation guidance is in
[`docs/production_readiness.md`](docs/production_readiness.md).

## Known limitations

- Actual supported media formats depend on device/system decoders and the
  selected media file; a successful build is not proof of playback on every
  device.
- Android media access depends on granted permissions and refreshed media
  library state.
- Linux local-file playback and spectrum behavior depend on installed system
  libraries and `ffmpeg`.
- The local `on_audio_query_android` fork currently emits a Flutter notice
  about legacy Kotlin Gradle Plugin usage. The current Android build has
  succeeded; plugin migration should be handled as a separately tested
  compatibility change.
- The vendored `video_thumbnail` code has analyzer `info` notices. These are
  tracked separately from application errors.
- No complete iOS Xcode project is present.
- Device-specific visual, performance, audio focus, and video PiP behavior must
  be checked on representative hardware.

## Release signing and secret handling

Release signing is local and guarded. The project uses an ignored
`android/key.properties` file that points to a private keystore stored outside
the source tree. Keep both in secure local storage and maintain a protected
backup. Never commit the real `key.properties` or keystore, include them in a
ZIP, or paste passwords into documentation, build logs, issue trackers, or
chat.

This repository has no guarantee of Git metadata in every source distribution.
Before publishing or sharing a source copy, independently inspect its contents
and verify that no local secrets or build products are included.

## Current build measurements

The following are measurements of local artifacts created during the
2026-10-14 stabilization session. They are build artifacts, **not committed
source files**, and future builds may differ:

| Artifact | Mode / ABI | Size |
|---|---|---:|
| ARM64 Debug APK after launcher asset optimization | Debug, `arm64-v8a` only | 95,020,473 bytes (95.020 MB / 90.619 MiB) |
| Signed ARM64 Release APK | Release, `arm64-v8a` only | 22,401,821 bytes (22.402 MB / 21.364 MiB) |

The measured Release APK was verified with Android `apksigner`; its certificate
matched the local signing keystore. These size numbers are not a guarantee of
the next build's size and do not imply physical-device testing.

## Project documentation

- [`docs/BASELINE.md`](docs/BASELINE.md) — recorded baseline and project
  observations.
- [`docs/MANUAL_TEST_CHECKLIST.md`](docs/MANUAL_TEST_CHECKLIST.md) — manual
  regression and device test cases.
- [`docs/MOTION.md`](docs/MOTION.md) — motion behavior and design notes.
- [`docs/external_sources.md`](docs/external_sources.md) — external source
  references.
- [`docs/production_readiness.md`](docs/production_readiness.md) — build,
  signing, validation, and release-readiness guidance.
- `third_party/on_audio_query_android/` and `third_party/video_thumbnail/`
  contain locally maintained plugin forks with their own README, license, and
  change notes.

## References

- [Flutter Linux documentation](https://docs.flutter.dev/platform-integration/linux)
- [`just_audio`](https://pub.dev/packages/just_audio)
- [`audio_service`](https://pub.dev/packages/audio_service)
- [`on_audio_query`](https://pub.dev/packages/on_audio_query)
- [FFmpeg documentation](https://ffmpeg.org/documentation.html)
