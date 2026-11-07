# YAZEN PLAYER — Scroll Performance Iteration 2

## Scope

This iteration targets the reported issue: library browsing feels heavier than
expected, while songs and album covers already appear at an acceptable rate.
The artwork retrieval pipeline was deliberately left unchanged.

## Source-level findings addressed

1. The app-wide animated theme background continued repainting while a list was
   moving. `ScrollPerformanceMode` now observes scroll notifications at the
   `MaterialApp` shell and pauses both ambient and RGB background tickers during
   active scrolling. It resumes shortly after scrolling becomes idle. The mode
   also respects `TickerMode` and the system reduced-motion preference.
2. Every `PageView` animation frame rebuilt nearby library pages to apply an
   additional opacity and horizontal drift. The extra effect was removed; the
   native `PageView` transition remains.
3. The back-to-top button previously rebuilt its position/animation subtree on
   every scroll-controller notification. It now updates visibility only when
   the offset crosses the 420-pixel threshold.
4. The fast-scroll thumb still follows the scroll offset, but its static
   gesture/decoration subtree is now passed as the `AnimatedBuilder` child and
   reused. Only the geometry/translation is recalculated on scroll updates.
5. The collapsible library header previously reacted to very small reversals
   in scroll direction and called `setState` on `HomeScreen`. It now uses
   directional movement thresholds (18 px to hide, 28 px to show) and a
   dedicated `ValueListenableBuilder`, keeping unrelated home-page widgets out
   of that update.
6. Custom wallpaper blur now uses `ImageFiltered` around the image and a
   `RepaintBoundary` rather than a full-screen `BackdropFilter`. The scrim and
   resulting visual treatment remain in place while the filter is isolated to
   the static background image.
7. Added widget tests for scroll-mode pause/resume timing and for a new scroll
   cancelling a pending background-animation resume.

## Kept unchanged

- List/grid virtualization, fixed song-row extent, scroll cache extent, and
  existing row keys remain unchanged.
- Artwork loading, image decoding, cache limits, disk cache, Android artwork
  retrieval and artwork display sizes were not changed in this iteration.
- Playback, queue, favorites, playlists, selection, search, sorting, and
  artwork appearance behavior were not intentionally redesigned.
- No features or data were removed. The added scroll service only coordinates
  decorative background animation with app scroll activity.

## Verification boundary

The project archive integrity was checked and the repository's
`tool/validate_foundation.py` script passed. Flutter and Dart SDK executables
are not available in this environment, so `dart format`, `flutter analyze`,
`flutter test`, and APK builds could not be run here. No physical-device test or
FPS claim is made. The final confirmation still needs a build and real-device
scroll test, especially on a lower/mid-range Android phone and in both List and
Grid modes.
