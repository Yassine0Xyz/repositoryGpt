# Fast-scroll performance — iteration 5

## Scope

This iteration targets the remaining lightweight hitch reported during rapid
song-library browsing. It preserves the existing Flutter/MediaStore design and
the earlier viewport, cache, and refresh fixes.

## Changes

1. `BoundedLoadGate` now supports an opt-in newest-first scheduling mode. Its
default remains FIFO so unrelated/background work keeps its established order.
2. Artwork loading uses newest-first scheduling with two concurrent loads and a
bounded queue of twelve. During a fling, newer requests are more likely to
belong to rows that remain visible; stale pending artwork requests are dropped
when the queue fills instead of delaying current viewport work.
3. The songs grid disables automatic keep-alives, matching the list's policy.
The rows are stateless apart from their artwork child, and artwork data is
already shared through bounded memory/disk caches and in-flight request reuse.

## Lark comparison

The decompiled Lark evidence showed bounded page-sized database update batches
and a guarded media-file observer dispatch. Those are library refresh/database
ideas, not proof of a paginated visible song list. This iteration does not copy
Lark code or introduce a second media scanner. It adapts the useful principle
of bounded, non-obsolete work to YAZEN's actual hot path: artwork requests
created by a scrolling viewport.

## UI assessment from source

The main Songs screen already uses `ListView.builder`/`GridView.builder`, fixed
row extents in list mode, repaint boundaries, and disables list-row keep-alives.
There is no `BackdropFilter`/large blur in the main Songs list path. Therefore
the overall UI composition is not the primary demonstrated bottleneck. The
per-row artwork retrieval/decode, grid tile layout work, and row action widgets
can still contribute to frame pressure, especially on lower-end phones.
The grid keep-alive policy was aligned with the list. Further visual simplification
should be driven by profile traces, not guessed from source alone.

## Verification boundary

Added unit tests for newest-first scheduling and stale-request eviction. Flutter
and Dart SDKs are not installed in this environment, so tests, analyzer, profile
traces, APK build, and physical-device measurements were not run. The reported
improvement is an engineering hypothesis supported by the request lifecycle,
not a measured FPS or zero-jank guarantee.

## Next measurement

Use a Profile build on the same phone/library before and after this iteration.
Record P50/P95/P99 frame time, janky frames, artwork load/decode spans, and peak
memory during repeated fast flings in List and Grid modes. Include cold and warm
artwork caches and reverse direction mid-fling.
