# YAZEN Library Engine — V1

## Goal

Create a focused, maintainable library architecture that improves the hot
browsing path without replacing Provider, changing the app's visual design, or
removing library features. The work builds on the existing V3 fast-scroll fix.

## Architecture

### 1. Library data engine

`LibraryDataEngine` owns an immutable `LibraryIndexSnapshot` for each completed
local-library refresh. A snapshot contains:

- The complete audio-track collection and its stable `trackId` lookup.
- Separate visible and hidden track lists.
- A normalized full-path folder index, folder counts, and sorted folder IDs.
- A monotonically increasing snapshot revision.

The controller applies playlist metadata and hidden-state overlays before
publishing a replacement snapshot. A refresh therefore swaps one complete
snapshot instead of exposing partially rebuilt collections. Folder navigation
uses the prebuilt index rather than scanning every track again.

The query pipeline keeps two cache levels separate:

1. Filtered and sorted tracks are cached by source identity, sort mode, filters,
   and dynamic playlist revision.
2. Text-search results are cached by that ordered source and the current query.

This is intentional: typing another character repeats the text match but does
not sort the whole library again. Favorite/play-count changes invalidate the
relevant dynamic cache; metadata/hidden changes publish a new snapshot.

### 2. Viewport and scroll engine

`LibraryViewportEngine` owns the frame-coalescing behavior previously embedded
inside the fast-scroll widget. It keeps the most recent thumb target, schedules
no more than one `jumpTo` per display frame, flushes the final target on drag
end/cancel, clamps the target to the scroll range, and cancels pending work on
disposal.

The visible thumb and its geometry remain in the widget layer. The engine only
coordinates scroll position, keeping UI details separate from scroll work.

### 3. Shared list/grid renderer

`LibraryTrackViewport` centralizes lazy list/grid construction for songs,
artists, albums, folders, hidden files, playlists, and videos. It standardizes the 260 px scroll cache,
keeps repaint boundaries consistent, and lets each library view retain its
previous keep-alive policy (the main song list remains non-keep-alive). Each screen still supplies its own cards, row heights, spacing,
artwork, and interactions; no visual redesign was introduced.

Stable keys remain on song rows/grids and folder rows; artist, album, and video
cells now also receive stable item IDs to reduce unnecessary state churn.

## Preserved behavior

- Song/video playback, queue ordering, favorites, playlists, hide/unhide,
  selection, sharing, deletion, sorting, filtering, and search remain in place.
- Artwork loading, artwork cache policy, and player artwork behavior were not
  changed in this phase.
- Existing list/grid layouts, row heights, spacing, toolbar controls, and
  animations were kept intact.
- Existing V3 fast-scroll coalescing remains active, now delegated to the
  viewport engine.

## Tests added

- `test/library_data_engine_test.dart`: immutable snapshots, hidden/visible
  indexing, folder lookup/counts, ordered search caching, and dynamic favorite
  invalidation.
- `test/library_viewport_engine_test.dart`: frame-coalesced fast-scroll jumps
  and immediate final-position flush.

## Validation status

Source-level review and archive-integrity checks are performed for this
iteration. The current work environment does not contain the Flutter or Dart
SDK, so `dart format`, `flutter analyze`, `flutter test`, and an APK build cannot
be executed here. No FPS/frame-time improvement is claimed without a Profile
build and a physical-device comparison.

Recommended validation commands on a Flutter workstation:

```bash
dart format lib/models/library_query.dart lib/services/library_data_engine.dart \
  lib/services/library_viewport_engine.dart lib/widgets/library_track_viewport.dart \
  lib/controllers/hybrid_music_controller.dart lib/screens/library/local_media_screen.dart \
  test/library_data_engine_test.dart test/library_viewport_engine_test.dart
flutter analyze
flutter test test/library_data_engine_test.dart test/library_viewport_engine_test.dart \
  test/library_search_service_test.dart test/scroll_performance_mode_test.dart
flutter build apk --profile
```

On the phone, compare the same library in Songs List, Songs Grid, Videos List/Grid,
search while scrolling, repeated fast-thumb drags, abrupt direction changes, and
rapid fling stops. Also verify favorite toggling, hidden/unhide, folder counts,
and queue playback after sorting/searching.
