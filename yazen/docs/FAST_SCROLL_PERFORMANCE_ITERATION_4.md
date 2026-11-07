# Fast Scroll Performance — Iteration 4

## Scope

This iteration targets the remaining user-reported stutter when dragging the
library fast-scroll thumb or rapidly moving through the song list. It does not
change artwork loading, library ordering, playback, playlists, or visual design.

## Implemented

- Coalesced fast-scroll pointer updates to at most one `ScrollController.jumpTo`
  request per display frame.
- Kept only the latest requested thumb position while multiple pointer events
  arrive before the next frame, avoiding redundant intermediate jumps.
- Flushed the final pending thumb position when the drag ends or is cancelled,
  so the last pointer movement is not lost.
- Cancelled a pending frame callback when the thumb is disposed.
- Added guards for detached controllers, missing content dimensions, invalid
  travel distance, and negligible position changes.

## Why this targets the reported issue

The previous implementation called `jumpTo` for every drag-update event. Touch
input can deliver multiple updates between painted frames. Each jump can trigger
scroll notifications and viewport work even though the display can only show
one resulting position per frame. Keeping only the newest target removes work
for positions that would never be painted.

## Not changed intentionally

- Artwork pipeline and disk/memory cache.
- Song ordering, search, playback, favorites, playlists, and selection behavior.
- List cache extent. Increasing it without evidence can increase memory and
  background build work; fast thumb jumps can skip over any prebuilt region.
- Broad library architecture. A rewrite is not justified before validating
  this targeted fix and identifying any remaining hot path.

## Validation limits

The source was inspected and basic delimiter/structure checks were performed.
Flutter and Dart SDKs are not available in this environment, so `dart format`,
`flutter analyze`, `flutter test`, and APK build were not run. No claim is made
about measured frame-time improvement until the APK is exercised on a device.

## Recommended next architecture step if stutter remains

Introduce a focused library viewport/data engine rather than rewriting the
whole app: immutable indexed library snapshots, stable item identity, isolated
row state, and viewport-aware prefetch. First profile whether the remaining
cost is UI build/layout, rasterization, or data preparation; select only the
corresponding engine changes.
