# YAZEN Performance Intelligence — Removal Map

> This subsystem is deliberately temporary. It is an investigative layer, not a permanent dependency of the YAZEN playback/library architecture. Keep this document with every diagnostic build so the instrumentation can be removed cleanly after the performance investigation.

## Scope and isolation

- `lib/diagnostics/core/diagnostics_service.dart` — session lifecycle, append-only JSONL journal, event sequence IDs, monotonic timestamps, bounded dashboard cache, pointer/scroll capture, frame timing, trace/span registry, resource sampling, export snapshot boundary, and full-journal analysis.
- `lib/diagnostics/screens/diagnostics_screen.dart` — temporary control/inspection UI.
- Android `yazen/diagnostics` MethodChannel block in `MainActivity.kt` — process/device memory, process CPU, per-thread raw CPU tick deltas, ART GC stats, and streamed journal export.

## Existing files with temporary integration edits

1. `lib/main.dart`
   - import/start the service at application startup.
   - root `Listener` records pointer down/move/up/cancel and pointer signals.
   - `NotificationListener<ScrollNotification>` records every Flutter scroll start/update/end delivered to the root listener, including axis/depth and velocity.
2. `lib/services/app_route_observer.dart`
   - diagnostics-aware route observer records push/pop/replace.
3. `lib/widgets/media_artwork.dart`
   - records memory/disk-cache hits/misses and creates spans for gate wait, disk reads/writes, source fetch, image descriptor decode, content crop, and full artwork load.
4. `lib/services/media_library_service.dart`
   - `_measure` creates spans around MediaStore song, artist, album, playlist, and video query operations; the library data engine adds index-build, sort/filter, and search spans.
5. `lib/controllers/hybrid_music_controller.dart`
   - records playback selection/toggle/repeat events, library tab/search/sort/filter changes, and library snapshot rebuild spans.
6. `lib/services/hybrid_audio_handler.dart`
   - records player state changes, play/pause/stop/seek/next/previous, queue transitions, playback progress checkpoints, repeat/shuffle/speed/volume, sleep timer, EQ, and audio interruption events.
7. `lib/screens/settings/settings_screen.dart`
   - temporary Performance Intelligence section, live monitor entry, and export action.
8. `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt`
   - `yazen/diagnostics` channel, native resource/thread snapshots, GC stats, and background streaming copy of the JSONL journal to Downloads.
9. `.github/workflows/flutter-ci.yml`
   - temporary diagnostics branch trigger; remove or restore the normal CI branch policy when the experiment is retired.
10. `tool/validate_temp_diagnostics.py`, `test/diagnostics_service_test.dart`, and `docs/YAZEN_PERFORMANCE_INTELLIGENCE_V1.md`
   - temporary validation, tests, and implementation notes.

## Complete removal checklist

- Delete `lib/diagnostics/`.
- Remove the diagnostics import and `DiagnosticsService.instance.start()` from `lib/main.dart`; remove the root pointer and scroll instrumentation while preserving `ScrollPerformanceMode` behavior.
- Restore the original route observer in `lib/services/app_route_observer.dart`.
- Remove diagnostics imports, disk-cache event records, and artwork spans from `lib/widgets/media_artwork.dart`; preserve artwork loading/cache behavior.
- Remove diagnostics import and `_measure` span wrapper from `lib/services/media_library_service.dart`; restore direct query calls.
- Remove diagnostics import and all event/span calls from `lib/controllers/hybrid_music_controller.dart`; preserve controller behavior.
- Remove diagnostics import and event records from `lib/services/hybrid_audio_handler.dart`; preserve playback and timer behavior.
- Remove the Performance Intelligence section, imports, and export method from Settings.
- Remove the `yazen/diagnostics` MethodChannel, resource/thread snapshot helpers, journal export helper, and diagnostics-only fields/imports from `MainActivity.kt`.
- Restore the CI branch trigger and remove the temporary validator/test/docs if no longer needed.
- Remove app-private `yazen_performance_sessions` files only through an explicit cleanup/migration policy; do not delete user exports in Downloads automatically.
- Run `dart format`, `flutter analyze`, `flutter test`, and Android build. Confirm no `yazen/diagnostics` channel or `DiagnosticsService` references remain.

## Measurement semantics and limitations

- Every Flutter `FrameTiming` callback received while recording is journaled. Frame budget uses the latest sampled display refresh rate, with a 60 Hz fallback until the first native snapshot. Percentiles in the live dashboard are a rolling recent window; export analysis computes full-journal frame percentiles.
- Pointer down/move/up/cancel and pointer-scroll signal events delivered to Flutter are captured. Pointer movement samples include coordinates, deltas, intervals, and per-axis velocity. Hover movement and raw touchscreen-controller samples are not captured.
- Scroll start/update/end notifications are captured separately from pointer samples, including scroll axis/depth, deltas, intervals, and pixels/second velocity.
- Every event has an increasing sequence, event ID, session ID, UTC wall timestamp, monotonic elapsed microseconds, route, event type, payload, and optional trace/span IDs.
- The append-only JSONL journal is the complete event source. The in-memory dashboard cache is capped at 12,000 events and is not used as the export source.
- The pending write queue is bounded to protect app responsiveness. Queue overflow, serialization errors, or file I/O failures are counted and cause the export to be marked incomplete. Export analysis checks JSONL line validity, sequence gaps, out-of-order events, and persisted-event count before declaring completeness. App force-stop/power loss can still interrupt the last buffered batch.
- Export freezes a consistent event-sequence boundary, flushes prior events, snapshots the journal, and exports JSONL + JSON analysis + Markdown report. Events after that boundary remain in the live session journal for a later export.
- Artwork, MediaStore, library snapshot rebuild, and selected playback/controller operations have trace spans. Frame events capture active spans/gestures so export can report temporal correlations. Correlation is not proof of causation.
- Android snapshots include device/display details, process PSS/private memory, Java/native heap, process CPU, per-thread raw Linux CPU tick deltas, ART runtime GC stats, device memory, and app data size on export. Raw thread ticks are not normalized CPU percentages; use Android Perfetto for scheduling/CPU attribution.
- Maximum Investigation enables Flutter widget-build/layout/paint timeline profiling in Debug/Profile-capable builds; inspect these spans in Flutter DevTools. Dart heap, exact per-widget memory, arbitrary OS-internal activity, and every kernel/filesystem operation cannot be fully attributed by this in-app system. Flutter DevTools and Perfetto remain required for deeper external profiling.
- Native logcat is not captured. The system records Flutter errors and YAZEN-owned events only.
- The service runs in Hybrid mode: process/resource snapshots are sampled every five seconds normally and every second in Maximum Investigation mode. Frame and interaction journaling remains active to preserve the requested session history; its overhead must be measured on-device.
