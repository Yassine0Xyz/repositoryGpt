# YAZEN production-readiness guide

## Required validation

Run the following commands from a Flutter environment with Android and Linux desktop prerequisites installed:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
dart format --output=none --set-exit-if-changed lib test tool
flutter build apk --debug --split-per-abi --target-platform android-arm64
flutter build linux --debug
```

The Android command above produces an ARM64-only **debug/test APK**, not a
production release. Verify its packaged native libraries under
`lib/arm64-v8a/` and confirm no other ABI directories are present; do not
install it on a personal device without explicit authorization. Debug package
size is not comparable to an optimized, signed release APK.

Android release tasks require explicit production signing. Configure
`android/key.properties` from `android/key.properties.example` and set
`ORG_GRADLE_PROJECT_production=true` in the build environment before running
`flutter build apk --release --split-per-abi`. Keep Flutter icon tree shaking
enabled; app icons use statically referenced icon data. Without the property and
valid private keystore, Gradle stops with a clear error instead of signing a
release with the debug key.

The release candidate must pass static analysis, all automated tests, Android release packaging, and physical-device playback checks. If Linux is a release target, also run its desktop build and PCM integration test on Linux with `ffmpeg` installed. A build result alone is not evidence that a particular phone can decode every local file.

## Data boundaries

YAZEN stores lightweight local metadata such as theme, playback preferences, favorites, custom playlists, and the last local queue snapshot. Audio and video files remain owned by the device media library. The local playback layer does not resolve network stream URLs and does not include an in-app media downloader.

Songs are sorted locally by date, size, duration, name, artist, play count, or last-played time. Available library filters are favorites, imported files, and missing album metadata. Opening a folder uses the already loaded, visible library tracks; refresh the library first if the device's media contents have changed.

## Local playback checklist

Test cold start, media permission denial and recovery, local audio playback, background playback, locked-screen controls, notification controls, Bluetooth/headset interruption, becoming-noisy events, queue replacement, add/reorder/remove/clear, next and previous, repeat-off/one/all, queue restoration, favorites, playlists, local videos, artwork, lyrics, theme persistence, sleep timer, equalizer availability, and optional surround behavior.

## Visualizer checklist

For Android local audio, capture native diagnostics while opening the full player and playing a local file:

```bash
adb logcat -c
adb logcat -s YAZENVisualizer:* flutter:*
```

The expected successful path includes a PCM start message followed by `pcm ready ... frames=...`. The Flutter debug build reports the selected mode. The spectrum must be driven by decoded PCM and playback position. If decoding is unavailable, the UI must remain visibly idle or unavailable; random or timer-driven movement is not acceptable.

For Linux, install `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libpulse-dev`, `clang`, and `ffmpeg`. Run `flutter build linux --debug`, launch the application, and run the Linux PCM test. Linux uses the actual local file decoded by `ffmpeg`; it does not use Android's output-capture API.

## Privacy and operational policy

YAZEN's local-first build should document device media-library access, local artwork access, optional lyrics requests if enabled by the current lyrics service, and local preference storage. Diagnostics must not expose private file paths, track titles, or user data unnecessarily. Do not ship unused network or download configuration.

## Known compatibility boundaries

The pinned `just_audio` version remains the playback engine and `audio_service` remains the background-control boundary. The Android PCM analyzer depends on `MediaExtractor` and `MediaCodec` accepting the selected local file. The Linux analyzer depends on the system `ffmpeg` executable. Unsupported or corrupt media must fail clearly without fabricating spectrum data.

The vendored `on_audio_query_android` Android module still applies its legacy
Kotlin Gradle Plugin scripts. Flutter currently emits a future-compatibility
notice, while the configured Android debug build succeeds. Migrate that plugin
as a separately tested compatibility task rather than changing root Gradle or
Kotlin versions speculatively.

The repository targets Android and Linux. The `ios/` directory has generated
Flutter/plugin support files but no Xcode project, so iOS packaging is not
currently supported or validated.

The Android notification resource is an existing monochrome white silhouette
referenced as `drawable/yazen_notification_icon`; retain that Android small-icon
treatment. Launcher icons still use the adaptive foreground/background setup in
the app resources. `.gitignore` currently contains scoped generated-directory
rules and does not have the reported unqualified `Flutter`, `Runner`, or
`keep.xml` patterns.

## Release gates

A release is acceptable only when formatting, analyzer, automated tests, and signed Android release packaging pass, and the release candidate has passed physical-device playback checks. Run Linux build and PCM checks only when Linux is included in the release scope. Keep `android/key.properties` and the private keystore outside version control. Record playlist rename and folder browsing/persistence checks in `docs/MANUAL_TEST_CHECKLIST.md`.
