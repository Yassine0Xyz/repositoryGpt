# YAZEN Performance Intelligence V1.2 — Source Audit

Date: 2026-11-08
Source baseline: `YAZEN-PLAYER-PERFORMANCE-INTELLIGENCE-V1.1-SOURCE-FIXES.zip`
Latest reviewed session: `yazen-2026-11-08T16-19-13.514682Z` (export generated around 16:22 UTC; build 12)

## 1. Evidence from the latest diagnostic session

The latest session contained 29,541 persisted JSONL events, with no malformed lines, sequence gaps, out-of-order events, or reported dropped events. It ran for about 195 seconds.

- 7,945 frames at a reported 90 Hz refresh rate; 4,311 frames (54.3%) exceeded the 11.11 ms budget and 1,614 (20.3%) exceeded twice that budget.
- Average frame span was about 23.49 ms. Full-session P99 was about 327.55 ms.
- The worst frame was about 2,189 ms, including about 1,815 ms of build duration. Raster duration was only about 17 ms. Library queries and artwork/cache operations overlapped that frame. This is temporal correlation, not proof that any one operation caused the stall.
- Artists, albums, and playlists queries took about 2.06 s, 2.24 s, and 2.27 s respectively. They were started concurrently. The video query for 40 items averaged about 2.66 s.
- Artwork pipeline reported 573 terminal loads: 503 successful source fetch/load results and 70 null results. The old `loadsFailed=0` figure counted thrown exceptions only, not unsuccessful null results.
- Artwork gate recorded 599 rejected waits. The report did not distinguish queue eviction from queue-capacity rejection.
- All 573 disk-cache reads reported `file_missing`. This can be normal for a cold cache; a warm-cache restart test is still required before calling it a cache defect.
- Seven cache trims averaged about 1.16 s and reached about 2.72 s, while deleting zero files. Repeated full directory enumeration/stat work was unnecessary when the cache was below its size limit.
- 27 repeated Flutter framework reports referenced a `ListTile`/`DecoratedBox`/`Material` warning. These are framework reports, not evidence of 27 application crashes.
- Peak process PSS was about 542 MiB and average PSS about 410 MiB. Average process CPU was about 135% (roughly 1.35 CPU cores), not 135% of the whole device.
- The session metadata explicitly said `debugMode=true`, `profileMode=false`, `releaseMode=false`. It is a Debug diagnostic session, not a valid Profile/Release performance benchmark.

## 2. Source findings and changes in V1.2

### Diagnostics accuracy and completeness

- Artwork loads now distinguish successful results, null/no-artwork results, and exception failures. `loadsFailed` no longer silently excludes null results; the separate counters preserve the distinction.
- Artwork source fetch records safe failure reasons and attempted source types (MediaStore artwork, embedded-art fallback, or HTTP result) without journaling raw media paths or URLs.
- Recent frame percentiles retain fractional milliseconds instead of truncating to whole milliseconds.
- Frame-to-frame intervals now use Flutter engine `vsyncStart` timestamps. The old callback-processing gap is retained separately as `callbackGapUs`, so batched timing callbacks cannot masquerade as actual frame cadence.
- Framework Flutter reports are counted separately from uncaught asynchronous errors and failed operation spans. The event includes exception type, context, stack source, and limited diagnostic-node type information. If Flutter does not supply a stack, the handler captures a fallback stack.
- Per-thread CPU aggregation is keyed by thread ID rather than merging unrelated threads that happen to share a name. Values remain raw Linux clock ticks and are not presented as milliseconds.
- Pointer completion records use pointer-event timestamps for gesture duration when available, preserve capture-clock duration separately, and classify tap/drag/long-press candidates from displacement and duration. These are coordinate-based candidates; they do not identify the semantic widget that received the gesture.
- Active pointer and scroll sessions are closed as interrupted when the app becomes inactive, paused, or detached. Frame timestamp anchors are reset across those lifecycle gaps.

### Journal export correctness

- Export now waits for an already-running journal drain to finish before freezing the boundary.
- The immutable export contains only events through the frozen boundary; later events remain in the live journal.
- Completeness now checks the first sequence, last sequence, boundary sequence, observed/queued/persisted counts, dropped count, malformed rows, gaps, and out-of-order rows.
- Drops are calculated from the frozen boundary rather than a global counter that may continue changing while the live session records post-boundary events.
- Valid JSON values that are not event maps, and event maps without a numeric sequence, are counted as malformed instead of being silently ignored.

### Artwork cache and gate

- The disk cache builds one deferred background index per process, then updates that index incrementally after successful writes.
- Trim uses the in-memory index and only sorts/deletes when the indexed cache exceeds 64 MiB. It no longer enumerates and stats the entire directory for every small batch of writes.
- Reads and writes wait while trim is active; trim waits for a quiet cache-I/O window. This prevents trim from deleting a file during an active cache read/write.
- Cache-index scan, sort, delete, read, write, gate wait, and maintenance wait have separate timings and outcomes.
- Disk write results distinguish `written`, `skippedInvalidPayload`, `rejectedByGate`, and `failed`. The caller no longer labels every unsuccessful write as a generic skip.
- `BoundedLoadGate` now reports `acquired`, `queueEvicted`, or `queueFull`. Existing concurrency and queue capacities were not increased. Artwork gate rejections now report the reason, so the next session can tell whether the 599 rejections were stale queue evictions or genuine queue-capacity failures.
- Media cache keys are represented in diagnostics by a stable opaque fingerprint, not the raw cache key, URL, or local media path. The fingerprint is not a cryptographic anonymization guarantee.

### Video thumbnail coverage

- Video thumbnails now have cache hit/miss, deduplication, gate wait/rejection, source fetch, load outcome, cache eviction, and first-visible-frame timing events.
- Null results and thrown exceptions are separate outcomes. Gate evictions and queue-full rejections are separate counters.
- No video thumbnail concurrency increase was made.

### Library loading and Material warnings

- The Android `on_audio_query` source bundled in this project already performs its MediaStore cursor queries on `Dispatchers.IO`. The audit therefore did not move that code blindly or rewrite the plugin.
- The controller previously started Artists, Albums, and Playlists queries together. V1.2 defers those secondary catalogs until the primary Songs result is published, then loads and publishes one catalog at a time. The selected secondary tab is prioritized. Stale results are discarded after each awaited query.
- The `ListTile` surfaces inside decorated Settings, Theme Picker, and Full Player sheets now have an intervening transparent `Material` ancestor. The previously fixed Home More sheet and Sort sheet wrappers remain in place.
- If a framework warning remains, the enriched Flutter error event should provide a stack/context clue for the remaining source.

## 3. What was deliberately not changed

- Artwork concurrency remains at its existing limit. The 599 gate rejections may represent stale off-screen requests during fast scrolling; increasing concurrency without a Profile trace would risk more decode/memory pressure.
- The MediaStore plugin query implementation was not rewritten. It already dispatches cursor work to IO; the overlapping platform-channel result delivery remains a hypothesis to measure after sequentialization.
- No claim is made that the worst frame is solved. The trace only shows temporal overlap, and a Profile run is required to identify the remaining UI-thread cause.
- The 0 disk-cache hits are not called a bug until a second session is run after force-closing/reopening the app with the same media library.
- PSS/CPU from the Debug session are not used as Release performance acceptance values.
- Raw hardware touch-sensor samples, hover movement, exact semantic widget targets, and every Android internal operation are not observable through Flutter's normal pointer/timing callbacks. The diagnostics capture Flutter-delivered events and explicitly instrumented app operations.
- Separate playback/UI issues (Repeat All, video sorting controls, playlist artwork, Full Player Art/Vinyl, Sleep Timer feedback, and media interruption policy) were not mixed into this performance patch.

## 4. Static validation and execution limits

The following source-level checks passed:

- `validate_pi_source_fixes.py`: 13/13
- `validate_temp_diagnostics.py`: 19/19
- `validate_v5_performance.py`: 18/18
- `validate_v6_ui_performance.py`: 5/5
- `validate_library_evolution_v1.py`: 15/15
- `validate_pi_v1_2.py`: 32/32

Total: 102 static guardrail checks passed. Changed Dart files also passed a delimiter-balance scan, and the baseline-to-V1.2 diff produced no whitespace-error output.

**Not executed in this environment:** `dart format`, `flutter analyze`, `flutter test`, Android APK build, or runtime/Profile benchmark. No Dart or Flutter SDK was installed in the working environment. Static checks do not prove Dart type correctness or runtime behavior. The earlier CI run also stopped at formatting before analyze/tests/build; formatting and full CI must be run with the Flutter SDK before treating this as a verified build.

## 5. Required next validation run

1. Apply this source version and run Dart formatting on the changed Dart files.
2. Run `flutter analyze` and the full `flutter test` suite, including the new bounded-gate tests.
3. Build and install a **Profile** APK (not Debug) for the Galaxy A52.
4. Repeat the same library-scroll, artist/album/playlist navigation, video-list, artwork-heavy, and cache-warm scenarios.
5. Force-close/reopen the app before the warm-cache pass, then export JSON, JSONL, and Markdown together.
6. Compare frame pacing, build/raster split, secondary query overlap, gate eviction reasons, disk-cache index/trim timings, disk hits, video thumbnail outcomes, and remaining Material warnings.

A clean Profile run is needed before claiming the performance issues are resolved.
