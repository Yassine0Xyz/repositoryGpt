# YAZEN Player V6 — Artwork Pipeline Iteration 1

## Baseline and scope

- Baseline: `YAZEN-PLAYER-V6-ROLLBACK-BASELINE.zip` (kept unchanged outside this working copy).
- Scope: bounded artwork-load admission and diagnostics only.
- No player engine, MediaStore query strategy, library viewport, row layout, theme, or playback behavior was rewritten.

## Changes

1. `BoundedLoadGate` now exposes a monotonic `rejectedLoads` counter. It increments both for immediate rejection (`maxQueued == 0`) and for queued work evicted on overflow.
2. `YazenMediaArtwork` no longer treats the first gate rejection as the final result. It waits 140 ms and makes one additional prioritized admission attempt. The retry is finite (at most two attempts total); queue and concurrency limits remain unchanged.
3. Debug/profile diagnostics now log bounded-gate state when an artwork request is still rejected after its retry.
4. Debug/profile counters record artwork loads started/completed/failed and disk-cache hits/misses. A compact metrics log is emitted every 32 completed/failed artwork loads. Existing per-load timeline tracing remains in place.
5. `bounded_load_gate_test.dart` now verifies rejection accounting and queue-overflow eviction accounting.

## Deliberately deferred

A negative cache was **not** added. The current platform read path can return `null` for multiple reasons, including genuinely absent embedded art and transient permission/platform/read failures. Caching every `null` as “no artwork” would risk persisting transient failures. A safe negative cache requires a typed result from the Android/native and MediaStore paths (for example: `found`, `confirmedNoArtwork`, `temporaryFailure`, `unsupported`) before adding TTL behavior.

The current bounded retry also does not claim to cancel native work already in progress. It only gives a request rejected while waiting one more bounded opportunity to enter the gate.

## Validation status

- Source changes and test additions were inspected.
- Flutter/Dart SDK executables were not available in the working environment; `dart format`, `flutter analyze`, and `flutter test` could not be run.
- No APK build, emulator run, or device profiling was performed.
- Therefore this iteration is a source-level change, not a verified runtime performance result. Validate with `flutter test test/bounded_load_gate_test.dart`, then profile fast-scroll on the target Android device.

## Files changed

- `lib/services/bounded_load_gate.dart`
- `lib/widgets/media_artwork.dart`
- `test/bounded_load_gate_test.dart`
