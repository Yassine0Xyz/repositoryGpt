# YAZEN Performance Intelligence — Source Audit & Targeted Fixes

**Baseline:** `Yassine0Xyz/repositoryGpt` commit `256896942d3a23e8a664082b96a2efe4bccd02a5`
**Scope:** Diagnostics accuracy, artwork-cache observability, and the two modal surfaces implicated by the ListTile/Material warning.

## Findings and changes

### 1. Pointer and scroll velocity telemetry

The previous pointer velocity calculation divided movement by the time at which the callback was processed (`Stopwatch` capture interval), even though each `PointerEvent` already supplied its own timestamp. Batched/coalesced input could therefore produce implausibly high speeds.

- Pointer velocity now uses the positive delta between consecutive Flutter `PointerEvent.timeStamp` values.
- Capture-clock intervals are retained separately as `captureIntervalUs`; they are no longer used as finger velocity.
- The journal now labels the timestamp clock as `flutter_pointer_event`. The legacy `deviceTimestampUs` field remains for compatibility, alongside the clearer `pointerEventTimestampUs` field. This is a Flutter event timestamp, not a raw hardware sensor timestamp.
- Scroll velocity now uses `ScrollStartNotification` / `ScrollUpdateNotification` drag source timestamps when available. Ballistic and programmatic scroll updates are still recorded, but have no fabricated velocity estimate when a drag timestamp is absent.
- Added unit tests for the observed 99 ms interval example and for missing, equal, or reversed timestamps.

### 2. Artwork disk-cache observability

The previous disk-write span combined waiting for the serialized write gate with actual filesystem work. Disk reads also swallowed errors without exposing whether the miss was caused by a missing file, malformed cache data, or an I/O error.

- Disk reads now emit a nested I/O span with hit/miss reason, payload size, and failure details.
- Disk writes now separate gate wait from filesystem write duration and report queue/active/rejected counts.
- Cache trimming is timed and reports files inspected/deleted.
- `ArtworkDiskCache.write` returns whether a write actually succeeded; a bounded-gate drop is no longer reported as a successful write by the outer artwork span.
- Existing concurrency policy is unchanged: one disk write at a time, bounded queue of 24. Artwork loading remains two concurrent loads with a newest-first queue of 12. No concurrency increase was made.

### 3. Material ink surfaces

The Home “More” sheet and “Sort and filter” sheet placed interactive `ListTile` / `RadioListTile` content inside decorated containers. They now use a clipped `Material` surface with the same background color and rounded top corners, so ink feedback is painted by the correct Material layer. Layout and colors are preserved.

## Areas deliberately not changed

- **Artwork concurrency and cache policy:** the Debug session shows queue pressure and slow cache writes, but does not prove that raising concurrency improves frame times. The new spans will separate write-gate wait from filesystem time in the next run.
- **Library query strategy:** Songs/Artists/Albums/Playlists are measured through `on_audio_query`; that plugin implementation is outside this repository. The app already records query and Dart mapping spans, and the Android `queryVideos` path uses a dedicated worker executor. The trace does not prove that the secondary audio queries block the Dart UI isolate. No speculative query rewrite was made.
- **Widget rebuild architecture:** the current trace identifies expensive Build frames but does not isolate the exact widget subtree. Broad rebuild changes are deferred until a Profile trace can identify the source.

## Validation status

The following repository source-level guardrails passed after these changes:

- Temporary Diagnostics: **19/19**
- V5 performance architecture: **18/18**
- V6 UI performance: **5/5**
- Library evolution: **15/15**

The new Dart unit tests were added but **not executed** because the available environment has no Flutter or Dart SDK. `dart format`, `flutter analyze`, `flutter test`, Android build, and Galaxy A52 Profile benchmark have **not** been run. These source checks do not establish runtime correctness or performance improvement.

The existing CI formatting failure affecting 21 Dart files is separate and remains unresolved by this targeted patch. Run `dart format` in the Flutter SDK environment before expecting the current CI workflow to proceed to analyze/tests/build.

## Next measurement

Install a Profile build on the Galaxy A52 and repeat the same navigation and swipe scenario. Export a fresh session, then compare:

1. frame percentiles and over-budget rates;
2. pointer/drag speeds using event timestamps;
3. artwork gate wait vs disk I/O vs disk write-gate wait vs disk write I/O;
4. warm-cache disk hit rate after force-closing and reopening the app;
5. library query duration and UI frame overlap.

Do not classify an active span overlapping a slow frame as the cause without additional evidence.
