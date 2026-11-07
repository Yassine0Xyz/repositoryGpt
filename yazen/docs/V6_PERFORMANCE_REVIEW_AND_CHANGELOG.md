# YAZEN Player V6 — Performance Review & Changelog

## Base and provenance

- Base source: `YAZEN-PLAYER-V5-COMPREHENSIVE.zip` (the newest complete project archive available in this workspace).
- GitHub reference checked separately: `Yassine0Xyz/YAZEN-PLAYER`, branch `main`, commit `28cc70feddcad8feda08593638e3a8d36d421889`.
- The GitHub branch is not treated as the V5 archive: it is an older, separately tracked source state. No GitHub branch, commit, or remote file was changed.

## V6 changes

### Adaptive custom-background rendering

File: `lib/core/theme/theme_provider.dart`

- Removed the always-on full-screen blur at sigma 18.
- Custom backgrounds now use a lower sigma 10 while idle.
- During active scrolling, the `ImageFiltered` blur is removed entirely and the background image is painted directly.
- Kept the existing `RepaintBoundary` and theme scrim.
- Set the background image `filterQuality` to `low`, appropriate for a cover image that is scaled to fill the viewport and sits behind a scrim.

Rationale: a full-screen blur is a raster/GPU cost that does not improve interaction while a user is rapidly scrolling. The change is reversible and does not alter library data, playback, navigation, or stored preferences.

## Re-validated inherited V5 guardrails

- `tool/validate_foundation.py`: passed.
- `tool/validate_v5_performance.py`: 18/18 passed.

These are source-level guardrail checks, not Dart analyzer, Flutter test, Android compile, or device frame-time measurements.

## Explicitly not claimed as completed

The following larger changes are still outstanding and have deliberately not been approximated with unsafe partial implementations:

1. True paginated audio-library loading from MediaStore. The current `on_audio_query` call returns a complete song list; changing this correctly requires a coordinated Android plugin API + Dart model conversion + controller snapshot/queue reconciliation.
2. Moving search/filter/sort work for very large libraries off the UI isolate. The current query engine still performs its final filtering/search/sort synchronously.
3. A lifecycle-safe MediaStore `ContentObserver` with debouncing and permission-change handling, connected to controller refresh without duplicate scans.
4. Device profiling at 100 / 500 / 2,000 / 10,000 tracks, including frame-time, raster-time, memory, and scroll-jank measurements.
5. Full `dart format`, `flutter analyze`, Flutter tests, Kotlin/Gradle build, and device regression testing.

## Risk assessment

- V6 change is limited to background rendering and has low behavioral risk.
- The custom background remains visible during scrolling; only the blur is skipped temporarily.
- No playback engine, MediaStore query semantics, queue, playlist persistence, or user data format was changed.
- The inherited V5 vendored `video_thumbnail` patch remains a maintenance point and should be reviewed against the exact upstream version before future dependency upgrades.

## Next engineering milestone

Implement MediaStore paging end-to-end as a dedicated change, with stable ordering and ID-based reconciliation so active queue items, favorites, and custom playlists remain intact across pages and refreshes. Do not merge a partial paging implementation that silently truncates the library.
