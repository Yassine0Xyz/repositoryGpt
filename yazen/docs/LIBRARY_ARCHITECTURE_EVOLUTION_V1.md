# YAZEN Player — Library Architecture Evolution V1

## Base and safety

- Base archive: `YAZEN-PLAYER-V6-ARTWORK-FIX-ITERATION-1.zip`.
- Work was performed in a separate extracted copy. The base ZIP was not modified.
- This iteration is a conservative library-surface and row-composition refactor. It does not replace the playback engine, MediaStore query strategy, artwork retrieval pipeline, controller, or list/grid viewport engine.

## Changes

### 1. Leaner song rows

- Removed the repeated `LOCAL` source badge from every local song row. The library is already the local-media surface, so the badge repeated the same information hundreds or thousands of times.
- Removed the separate play icon button. The complete row already plays the selected track, so the button duplicated the primary action and consumed horizontal space.
- Replaced separate favorite and add-to-playlist buttons with one shared overflow-menu widget used by both list and grid tiles. Both actions remain available, including add-to-playlist in compact density.
- Removed the duplicate play buttons from grid tiles too; tapping the tile remains the primary playback action.
- Removed the per-grid-tile `LayoutBuilder`; the parent viewport computes the grid cell and artwork dimensions once and passes the resolved size into each tile.
- Removed an unnecessary one-child `Row` around artist text.
- Preserved artwork size rules, current-track indicator, selection overlay, duration in regular density, long-press selection, row tap playback, and caller-provided trailing actions.

### 2. Avoid overlapping library viewports during tab changes

- Replaced the library tab body's cross-fade `AnimatedSwitcher` with a keyed subtree.
- The outgoing tab no longer remains mounted for the transition while the incoming tab builds. This avoids temporarily retaining two large lazy viewports and allows the old tab's artwork widgets to dispose immediately.
- The back-to-top button's small local animations remain unchanged.

### 3. Deliberately preserved

- Existing list/grid choice and density settings.
- Lazy builders, fixed song-row extents, fixed grid extents, and the 220/260 px cache policies already present in the source.
- Scrollbar and fast-scroll-thumb frame-coalescing behavior.
- Artwork cache, bounded load gate, MediaStore/native fallback paths, and artwork dimensions.
- Search, sorting, playlists, favorites, hidden tracks, selection, queue and playback semantics.

## Why this is a measured-scope change

The current source already has lazy list/grid construction, fixed extents for the main song list, and bounded artwork loading. Replacing those systems without a profile trace would be speculative. This iteration reduces per-row UI composition and prevents cross-tab viewport overlap without changing data or playback architecture.

## Validation limits

- Source-level structural checks are provided by `tool/validate_library_evolution_v1.py`.
- Flutter/Dart formatting, analyzer, widget tests, APK build, and real-device profiling were not run in this environment because the Flutter/Dart SDK and Android toolchain are unavailable here.
- No claim is made that this source change has proven a specific FPS or fixed all fast-scroll jank. Device profiling must compare the same library and gestures against the preserved V6 Artwork Fix Iteration 1 baseline.

## Recommended profile comparisons

1. List mode, fast fling and reverse direction, artwork enabled.
2. Same gestures with warm artwork cache.
3. Grid mode with the same library.
4. Compare UI-thread build/layout and raster frame times, missed frames, CPU, memory, and artwork request completion.
5. Check that favorite, add-to-playlist, play, long-press selection, and hidden-file restore still work.
