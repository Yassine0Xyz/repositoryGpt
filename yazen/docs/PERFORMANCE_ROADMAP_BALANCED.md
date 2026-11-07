# YAZEN PLAYER — Balanced Performance Engineering Plan

## Selected strategy

- Priority: balanced performance, stability, and visual quality.
- Scope: performance work only in this iteration.
- Device range: low-end, mid-range, and high-end Android devices.
- Constraint: source-level work only; do not claim runtime or FPS results until a profile build is measured on physical devices.

## Current architectural assessment

The app already has several good performance foundations:

- `ListView.builder` / `GridView.builder` for virtualized library views.
- A fixed row extent and a modest scroll cache extent in the main Songs view.
- Cached sort/filter/search results in `HybridMusicController`.
- Normalized per-track search text cached with `Expando`.
- `NowPlayingScope` to keep playback-position updates away from the entire library tree.
- Artwork memory/disk caches and bounded concurrency.
- Secondary artist/album/playlist catalogs are deferred until the Songs list is available.

These should be preserved. Pagination, a wholesale state-management replacement, or a database migration are not justified for a library of hundreds of songs without measured evidence.

## Work completed in this iteration

1. **Avoid disk metadata writes on artwork cache hits.** `ArtworkDiskCache.read()` no longer calls `File.setLastModified()` for every hit. Repeated cache reads during a fling should remain read-only; eviction uses successful cache-write timestamps as a low-cost approximation instead of touching the filesystem on every read.
2. **Invalidate local artwork when the underlying file changes.** Local artwork cache keys now include MediaStore ID, modified timestamp, and file size. Replacing a file or editing its metadata/artwork no longer leaves the previous cover cached indefinitely under the same MediaStore ID.
3. **Add DevTools timeline spans around artwork retrieval and processing.** Debug/Profile traces now include `YAZEN.artwork.load` with target pixel size, crop mode, and local/remote source. This makes slow artwork paths measurable without adding tracing overhead to release builds.

## Decisions: what not to add yet

### No Drift/SQLite migration yet

The current library is loaded once from MediaStore and kept in memory. For hundreds or a few thousand tracks, that is a reasonable architecture and is not on the hot scroll path. Drift/SQLite becomes worthwhile if measured startup/query latency or catalog size (e.g. tens of thousands of tracks) justifies persistent indexing, incremental synchronization, or richer queries.

### No Riverpod migration

The project already uses Provider, selectors, and scoped playback notifications. Replacing the state-management library would create migration risk without proving a frame-time improvement.

### No custom scrolling implementation

The main library already uses builder-backed virtualized lists/grids. Keep Flutter's standard scrolling primitives unless profiling identifies a specific layout or sliver bottleneck.

## Next engineering phases

### Phase A — Instrument and baseline

On the same physical devices and same test library, capture Profile-mode traces for:

- Cold and warm artwork cache.
- 500, 2,000, and 5,000 tracks.
- Fast repeated flings in List and Grid modes.
- Direction reversal and abrupt stop after a fling.
- Search while scrolling.
- Artwork-heavy, missing-artwork, and unusually large embedded-art collections.

Inspect UI and raster frame times separately, image decode work, memory, and I/O. At 60 Hz the frame budget is 16.67 ms; at 90 Hz it is 11.11 ms; at 120 Hz it is 8.33 ms.

### Phase B — Artwork request lifecycle

If traces show stale work after a fling:

- Add viewport-aware request cancellation for queued requests.
- Give visible rows higher priority than prefetch work.
- Keep prefetch bounded and optional on low-memory devices.
- Ensure a row that remains visible always gets a chance to retry after a stale request is dropped.
- Keep thumbnail, medium, and hero image variants separate.

### Phase C — Library loading and search

Only if first-load/search measurements justify it:

- Add MediaStore change observation and incremental refresh rather than repeated full scans.
- Avoid rebuilding secondary catalogs when their source has not changed.
- Consider a local indexed database (Drift/SQLite with FTS5) for very large libraries or advanced query needs.
- Keep search cancellation/versioning so old asynchronous results cannot overwrite newer queries.

### Phase D — Rendering and adaptive effects

If raster/GPU time is the limiting factor on low-end devices:

- Add an optional Performance mode that reduces ambient motion and expensive visual effects.
- Respect Android battery saver and system reduced-motion preferences.
- Avoid globally removing animations; target only effects shown by traces to be expensive.

### Phase E — Regression protection

- Unit tests for cache key invalidation, request queue behavior, and repository synchronization.
- Integration tests for play/queue/favorites/selection while scrolling.
- Repeatable profile benchmark scenarios with recorded device model, refresh rate, OS, Flutter version, and catalog size.
- Compare P50/P95/P99 frame timing, janky-frame percentage, memory growth, and first-library-paint time between releases.

## Acceptance principles

- No claimed FPS improvement without a physical-device Profile-mode comparison.
- No library/dependency migration without a demonstrated benefit and a rollback plan.
- No performance optimization may break playback, queue order, favorites, playlists, artwork correctness, or scroll position.
- Low-end devices must degrade gracefully: bounded caches, bounded background work, and optional visual effects.
