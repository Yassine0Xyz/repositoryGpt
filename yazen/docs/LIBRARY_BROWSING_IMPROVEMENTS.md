# YAZEN-PLAYER — Library browsing improvements

## What was changed in this pass

1. **Secondary-catalog stale-result protection** (`hybrid_music_controller.dart`)
   - Artist/album/playlist queries are now associated with the primary library-load generation.
   - A scan invalidates secondary results already in flight.
   - Stale results cannot overwrite catalogs belonging to a newer scan.
   - If a newer scan supersedes an active secondary query, one fresh query is scheduled after the old query exits.
   - Secondary catalog failures remain non-fatal; the Songs list stays usable.

2. **Atomic artwork-cache publication** (`artwork_disk_cache.dart`)
   - Reject invalid dimensions and empty payloads before writing.
   - Write to a temporary file, flush it, then rename it into place.
   - Interrupted writes should no longer leave a partially written cache entry that can be mistaken for a complete hit.
   - Cache remains an optimization; failures do not affect playback.

## Lark Player observations used as design references

The decompiled Lark sources show a database update routine that commits work in pages (the observed page size in one call site is 200) and a delayed media-file observer setup for configured folders. These are useful architectural ideas: bounded batches, coalesced file-change notifications, and incremental invalidation. They are not copied code, and the decompiled evidence does not establish that Lark uses the same mechanism for every screen's visible song list.

## Existing YAZEN work retained

- Immutable library snapshots and memoized sorting/filtering/search (`LibraryDataEngine`).
- Viewport thumb event coalescing (`LibraryViewportEngine`).
- Bounded artwork work queue (`BoundedLoadGate`).
- Persistent artwork byte cache (`ArtworkDiskCache`).
- Lazy list/grid rendering (`LibraryTrackViewport`).

## Not implemented yet (requires design and device validation)

- Native MediaStore incremental change tracking / ContentObserver integration.
- True paged MediaStore reads. The current `on_audio_query.querySongs()` path returns a full result set; adding paging requires a supported native query path and permission/content-URI handling, not just slicing the already-loaded Dart list.
- A measured 500 / 2,000 / 10,000-track performance benchmark and device frame-time profile.

## Validation

`tool/validate_foundation.py` passed after the changes. Flutter/Dart SDK was not available in the execution environment, so `dart format`, `flutter analyze`, automated Flutter tests, APK builds, and physical-device scrolling tests were not run. These changes are source-level improvements, not a claim that the app is bug-free or that the performance target has been measured.
