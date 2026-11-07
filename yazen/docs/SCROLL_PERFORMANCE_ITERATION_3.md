# YAZEN PLAYER — Scroll Performance Iteration 3

## Goal

Continue the source-level work on library scrolling after the user clarified that
song rows and artwork already load acceptably. This iteration focuses on the
cost of building and painting list rows, and on avoiding decorative animation
work while a scroll is active. Artwork retrieval, decoding, and cache policy are
left unchanged.

## Changes applied

1. **Track row composition:** merged the row's decorated `Container` and
   transparent `Material` into one shaped `Material` with the same background,
   rounded border, and ink response. This removes one wrapper/decorated paint
   layer from every `TrackListTile` while preserving its appearance and tap
   feedback.
2. **Palette-specific subscriptions:** `TrackListTile` and `_TrackGridTile` now
   select only the theme preset. A wallpaper/custom-background notification no
   longer invalidates all visible song rows when the row palette has not
   changed.
3. **One compact-width calculation per list:** Songs, Hidden, Favorites,
   artist/album detail tracks, playlist detail, and the add-song picker now
   calculate the compact breakpoint once at the list viewport and pass it into
   each row. `TrackListTile` no longer creates a `LayoutBuilder` per row.
4. **Fixed-extent track lists:** added fixed row extents to hidden tracks and
   the add-song picker; converted Favorites to a fixed-extent builder; and
   changed artist/album detail tracks to a `SliverFixedExtentList`. The fixed
   extents preserve the existing row and separator dimensions:
   - Main Songs list: 70px in compact density; regular density uses 76px on
     narrow viewports (58px artwork) or 82px on wider viewports (64px artwork).
   - Hidden tracks: 72px compact / 78px regular.
   - Add-song picker: 72px compact / 78px regular.
   - Favorites: 74px compact / 80px regular (including the original 2px gap).
   - Artist/album detail tracks: 76px compact / 82px regular (including the
     original 4px gap).
5. **Grid identity:** added a stable track-ID key to song grid tiles so child
   state remains attached to the correct track if the underlying order changes.
6. **Now-playing repaint isolation:** wrapped the small animated now-playing
   indicator in its own `RepaintBoundary` in list and grid rows.
7. **Pause the now-playing pulse during scroll:** the current-track pulse now
   yields while `ScrollPerformanceMode` is active, then resumes when scrolling
   settles. The global ambient/RGB background pause from the previous iteration
   remains in place.
8. **Responsive fixed extents:** fixed row dimensions account for compact
   artwork sizing so they do not insert blank vertical space on narrow screens.
   The main Songs list now uses 76px rather than 82px for regular-density rows
   when the compact-width layout selects 58px artwork.

## Intentionally unchanged

- Artwork loading, decoding, thumbnail sizes, request concurrency, disk cache,
  and Android MediaStore artwork retrieval.
- Audio playback, playback queue, favorites, playlists, search, sorting,
  selection mode, video playback, and theme appearance.
- The main Songs list's existing lazy builder and `cacheExtent`; its fixed row
  extent is retained and now also accounts for compact-width regular-density
  layout.
- Search/sort preprocessing that was already cached in the controller and
  `LibrarySearchService`; no redundant Isolate or cache layer was added.
- Grid and card visual effects whose cost has not been shown to be a scroll
  bottleneck. No blanket shadow/blur removal or global cache increase was made.

## Verification boundary

The source foundation validation script passes. Archive-level checks are run
when the delivery ZIP is created. Flutter and Dart SDK executables are not
available in this environment, so `dart format`, `flutter analyze`,
`flutter test`, and APK build cannot be claimed. No real-device FPS or
smoothness measurement has been performed. The fixed row heights are derived
from the current `TrackListTile` layout constants and should be confirmed by a
Flutter build and a quick scroll check in Songs, Favorites, Hidden, and
artist/album detail views.
