# Temporary Performance Diagnostics — Removal Map

> This subsystem is deliberately temporary. It is not part of the permanent YAZEN library/playback architecture. Keep this document with every diagnostic build so the next release can remove the instrumentation cleanly.

## Scope and isolation

All new Dart diagnostics code lives under `lib/diagnostics/`:

- `core/diagnostics_service.dart` — session recorder, bounded event buffer, Flutter frame timings, scroll/navigation/lifecycle events, resource snapshot bridge, JSON/TXT export.
- `screens/diagnostics_screen.dart` — temporary live monitor UI.

The Android-only bridge is the `yazen/diagnostics` MethodChannel block and its private helper methods in `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt`.

## Existing files with temporary integration edits

1. `lib/main.dart`
   - import and start `DiagnosticsService` in `main()`.
   - nested scroll-notification listener records scroll starts/updates/ends and forwards existing scroll events to `ScrollPerformanceMode`.
2. `lib/services/app_route_observer.dart`
   - diagnostics-aware route observer records push/pop/replace events.
3. `lib/widgets/media_artwork.dart`
   - records artwork load start/completion/failure and disk-cache hit/miss events.
4. `lib/services/media_library_service.dart`
   - temporary duration/item-count/error events around MediaStore song, artist, album, playlist, and video queries.
5. `lib/screens/settings/settings_screen.dart`
   - temporary diagnostics section, live monitor entry, and direct export action.
6. `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt`
   - `yazen/diagnostics` channel: process/device memory, process CPU-time snapshots, app data size, and writing reports into Downloads/YAZEN Diagnostics.
7. `.github/workflows/flutter-ci.yml`
   - temporary branch trigger for the diagnostics branch; remove it or restore the normal CI branch policy when the diagnostics experiment is retired.

## Complete removal checklist

- Delete `lib/diagnostics/`.
- Remove the diagnostics import and `DiagnosticsService.instance.start()` from `lib/main.dart`.
- Restore the original `RouteObserver<ModalRoute<dynamic>> appRouteObserver` in `lib/services/app_route_observer.dart`.
- Remove diagnostics imports and `record(...)` calls from `lib/widgets/media_artwork.dart`; keep the artwork pipeline itself unchanged.
- Remove diagnostics import and `_measure(...)` wrapper calls/helper from `lib/services/media_library_service.dart`; restore the original direct MediaStore query methods.
- Remove the `Temporary diagnostics` section, its imports, and `_exportDiagnosticLogs()` from Settings.
- Remove the `yazen/diagnostics` MethodChannel registration, `diagnosticResourceSnapshot()`, `directorySize()`, `saveDiagnosticFiles()`, and diagnostics-only imports/state from `MainActivity.kt`.
- Restore the CI branch trigger to the project's normal workflow policy.
- Run `dart format`, `flutter analyze`, `flutter test`, and the Android build. Confirm no `yazen/diagnostics` channel or `DiagnosticsService` references remain.

## Measurement semantics and limitations

- Flutter `FrameTiming` records build, raster, and total frame spans. Slow-frame counters use 16.67 ms and 33.33 ms thresholds; these are useful reference thresholds for a 60 Hz display, not a claim about the phone's configured refresh rate.
- Estimated FPS is derived from the mean frame duration captured by Flutter. It is not a direct hardware display-refresh counter.
- Scroll event samples include delta, position, extent, interval, estimated pixels/second, and start-to-first-update delay. The start-to-first-update value is event-timing resolution, not a touch-controller hardware latency measurement.
- Artwork events include request duration, success/failure, requested pixel size, local/remote classification, and disk-cache hits/misses. Track titles and file paths are intentionally not recorded.
- Android snapshots include device model/build/display details, process PSS/private memory, Java/native heap, cumulative process CPU time, CPU percentage between two snapshots, device available/total memory, and app data-directory size. CPU percentage is `-1` on the first snapshot because no prior sample exists.
- Process memory and CPU snapshots are sampled every five seconds while recording; recursive app-data directory sizing is performed only during report export to avoid repeated filesystem traversal. The report does not claim per-frame RAM/CPU sampling.
- Native Android logcat is not accessible to an ordinary app process; the report captures Flutter/Dart errors and YAZEN-owned diagnostic events, not arbitrary system logcat.
- The event buffer is capped at 12,000 events. When full, oldest events are discarded to bound memory and instrumentation overhead.
- Reports are saved to `Downloads/YAZEN Diagnostics` on Android 10+; older Android versions use the app's external documents directory. If the native bridge is unavailable, Dart falls back to the app documents directory.
