# Library scroll performance audit and source changes

## Scope and verification boundary

This audit was performed by reading the source tree. No Flutter command, Dart command,
Android build, emulator, or device benchmark was run. The changes below are therefore
source-level optimizations, not a measured FPS claim or a runtime-verified release.

Primary path inspected:

- `lib/screens/library/local_media_screen.dart`
- `lib/screens/home/widgets/track_list_tile.dart`
- `lib/widgets/media_artwork.dart`
- `lib/services/artwork_content_cropper.dart`
- `lib/services/artwork_disk_cache.dart`
- `lib/services/media_library_service.dart`
- `lib/controllers/hybrid_music_controller.dart`
- `lib/services/library_search_service.dart`
- `lib/widgets/now_playing_scope.dart`
- Android artwork methods in `MainActivity.kt` and the local `on_audio_query_android` fork

## Findings

### 1. The list virtualization was already correct

The Songs list already uses `ListView.builder`, a fixed `itemExtent`, disabled
automatic keep-alives, repaint boundaries, and a modest 260 logical-pixel cache
extent. Grid mode also uses `GridView.builder` with a fixed main-axis extent.

Therefore, the app was not eagerly building every song row. Adding pagination or
replacing the list with a custom scrolling implementation would add complexity
without addressing the strongest cost found in the source.

### 2. Artwork content analysis was too expensive for thumbnails

Before this change, every `YazenMediaArtwork` request entered
`ArtworkContentCropper.process`, even for 48–64 logical-pixel list images. That
pipeline may decode an image, make a small RGBA copy, inspect pixels in Dart to
find content bounds, decode again, crop through a canvas, and encode another PNG.
The bounds cache avoids repeating the edge analysis for the same source, but a
new song still incurs image loading/decoding work and the crop/re-encode path.

For a rapid fling through hundreds of songs, this work is unnecessary for each
small tile and can compete with frame production.

### 3. Artwork requests had no back-pressure

The previous image loader used a concurrency limit but kept excess requests in an
unbounded waiter queue. A fling can create requests for rows that are already
outside the viewport. Those old requests can continue to consume I/O and decode
capacity after the user has moved on.

Disk-cache reads also need to be included in the same limit; otherwise the decode
limit still permits a large number of simultaneous file reads.

### 4. Disk-cache writes could accumulate independently

Artwork writes were started without awaiting them. That keeps the current image
from waiting on disk, which is good, but a fast series of loaded images could
start many file writes at once. This has now been given a separate one-at-a-time,
bounded write queue. Dropping a cache write is safe: the image remains available
for the current widget and can be fetched again later.

### 5. Repeated row animations added avoidable widget work

Each song-row action previously used an animated button with several nested
implicit animation/state layers. A list can create and recycle these actions
frequently. These actions now use a standard `IconButton` with the Material
ripple. The selected/current-track visuals and actions remain; the small
scale/hover animation on those row buttons is intentionally removed.

### 6. Sorting and search are not the primary scroll bottleneck

`HybridMusicController` caches its ordered/filtered list, and
`LibrarySearchService` caches normalized searchable text per track. The Songs
screen also uses a selector snapshot rather than blindly rebuilding all library
tabs for every controller notification. The HomeScreen scroll callback now uses
movement thresholds and a dedicated `ValueListenableBuilder` for the collapsible
header, so tiny direction changes do not rebuild the entire home page. These
existing foundations were retained and tightened.

## Changes made

1. `YazenMediaArtwork.cropContentBounds` now defaults to `false`. List, grid,
   search, queue, and mini-player artwork therefore avoid pixel-bound analysis,
   canvas cropping, and PNG re-encoding.
2. The full player and the large 720-pixel preview artwork explicitly opt
   into content-bound cropping, so the hero artwork keeps the prior presentation.
3. The artwork cache key now includes both target resolution and the raw/cropped
   variant. The disk cache directory was bumped from `v1` to `v2`, so an old
   cropped thumbnail cannot be mistaken for the new raw thumbnail.
4. A shared `BoundedLoadGate` limits artwork loading to 3 active operations and
   at most 32 waiting operations. When that queue fills, its oldest waiting
   request is rejected so newer viewport requests are retained. The same gate
   covers disk reads and artwork retrieval/processing.
5. Both Android artwork paths now downsample embedded artwork to the requested
   size before sending bytes to Flutter: the local `on_audio_query_android` fork
   and YAZEN's `MainActivity` fallback. Their temporary Android bitmaps are
   recycled after encoding, and the plugin releases its `MediaMetadataRetriever`
   / file handle on every path. This avoids full-resolution bitmap allocation
   on fallback and older Android paths and reduces native-memory/resource
   pressure while covers are loaded.
6. Raw thumbnail payloads over 512 KiB are not written to the in-memory or disk
   thumbnail caches. This prevents an unusually large embedded image returned
   by the fallback path from evicting many small covers. Flutter's `Image.memory`
   still receives cache dimensions so the decoded display image is sized for
   the widget.
7. Disk-cache writes are serialized through a second gate: one active write and
   at most 24 waiting writes. Excess cache writes may be skipped; playback and
   visible artwork do not depend on them.
8. Song-row action buttons use standard `IconButton` widgets instead of nested
   animated controls.
9. Unit tests were added for the bounded gate's concurrency limit, permit
   transfer, queue overflow behavior, and zero-queue mode.

## What was deliberately not changed

- No pagination was added. A builder-backed list is already virtualized, and a
  library of hundreds of tracks does not justify introducing paging state.
- No database migration or new indexing dependency was added.
- Sorting/search semantics, playback queues, favourites, playlists, and row
  selection behavior were not redesigned.
- Hero artwork remains eligible for the cropper; only the frequent thumbnail
  path skips it by default.

## Further options, ordered by when they become worthwhile

### A. Measure before changing more

On a real device, compare the same library before and after this patch in a
profile/release-like build. Test both a cold artwork cache and a warm cache.
Watch UI-thread and raster-thread frame charts, image decode activity, memory,
and disk I/O. At 60 Hz, a frame budget is about 16.7 ms; at 120 Hz it is about
8.3 ms. A smooth result should not repeatedly exceed the device's frame budget.

Use 500, 2,000, and 5,000 tracks. Repeat fast flings in list and grid modes,
change direction quickly, stop halfway through a fling, and verify that covers
for the rows left on screen eventually appear. Also test tracks without album
art and large embedded artwork.

### B. Add viewport-aware cancellation / prioritization

The current queue is bounded and rejects old waiting work, but it cannot cancel
an already-running platform-channel request. A more advanced version can give
artwork requests a visibility lease: when the row is disposed, a queued request
is removed; requests for the current viewport are high priority; prefetch rows
are low priority. This is useful only if profiling still shows stale artwork
work after the bounded queue change.

### C. Move exceptional image processing off the UI isolate

If visual requirements demand edge detection for every thumbnail, do not put
pixel scanning and re-encoding in the normal row build/load path. Precompute
thumbnails in a worker/isolate or native Android executor and cache the result.
The best path for local Android artwork is normally to request a thumbnail at
the display resolution from MediaStore rather than decoding a full-size cover
and cropping it in Dart.

### D. Reduce background animation while scrolling

The current source now pauses both `EchoAmbientLayer` and the RGB rainbow
background while any app scroll is active, then resumes after scrolling settles.
It also respects `TickerMode` and system Reduce Motion. This is an automatic,
temporary performance mode; the visual themes remain available while idle.

### E. Change library data storage only for very large catalogs

`MediaLibraryService.querySongs()` currently obtains the full MediaStore song
catalog and converts it to `MediaTrack` objects. That is reasonable for hundreds
or a few thousand songs, especially because it is done during library load, not
for every scroll tick. For tens of thousands of tracks or slow first-load times,
consider a native paged MediaStore query or a local indexed database with
stable IDs and incremental updates. Merely splitting a Flutter list into pages
while still querying and retaining the full catalog would not solve the data
loading cost.

### F. Keep row rebuild scope narrow

The current `NowPlayingScope` uses per-track model notifications, which is
preferable to rebuilding every song row whenever playback position changes.
Preserve that separation. Avoid putting the full `HybridMusicController` behind
`watch` in each row or sending a `notifyListeners()` on every scroll pixel.

## Acceptance checklist for a device run

- 500+ songs: fast repeated flings in list and grid, both cold and warm cache.
- Reverse scroll direction quickly; confirm covers on the final visible rows load.
- Stop in the middle of a fling; confirm visible covers do not remain placeholders.
- Songs without artwork and songs with large embedded images do not cause a
  large memory spike or block list interaction.
- Favourite, queue, play, long-press selection, and add-to-playlist actions work.
- Current-track indicator remains synchronized and the scroll position does not
  jump when playback state changes.
- Repeat with reduced motion enabled and disabled.
- Compare UI and raster frame timelines before/after on the same physical device.

## Verification status

The source edits and test logic were inspected manually. The tests were **not
run**, and the app was **not built or launched**, in accordance with the
source-only inspection request. Device performance is not claimed until the
acceptance checklist is run on hardware.
