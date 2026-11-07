# YAZEN Player — V5 Comprehensive Engineering Audit & Change Log

**Audit date:** 2026-11-03  
**Working baseline:** `YAZEN-PLAYER-SMOOTHER-BROWSING-ITERATION5.zip` (the latest full source archive available in this conversation)  
**Remote reference checked:** `Yassine0Xyz/YAZEN-PLAYER`, `main` at `28cc70feddcad8feda08593638e3a8d36d421889`  
**External reference:** user-supplied decompiled Lark Player APK (`decompiled_apk.zip`)  
**Status:** Source-level V5 engineering iteration. The foundation validator passed. No APK was built or device-tested in this environment.

---

## 1. Executive summary

V5 is a broad reliability and performance pass, with the highest priority on library browsing and video-library work that can compete with scrolling. The existing YAZEN architecture is retained: Flutter UI, `just_audio`/`audio_service` for audio playback, MediaStore/on_audio_query for local media, the existing library query/cache engine, and bounded artwork loading.

The work does **not** replace the audio engine with IJK/FFmpeg. Lark's decompiled package contains IJK/FFmpeg video-player components, but that is not evidence that YAZEN needs a new audio engine. Adding a second playback engine without measured compatibility or latency requirements would introduce another lifecycle, decoder, queue, focus, and error surface.

The central V5 changes:

1. Move Android video-library enumeration and content-thumbnail decoding off the Android main/platform thread.
2. Coalesce overlapping native video-library scans.
3. Add bounded, newest-first, deduplicated video-thumbnail loading and a byte-bounded LRU cache.
4. Avoid unnecessary oversized image work in video cards.
5. Avoid repeat comparator callbacks for dynamic sort keys.
6. Cache search results against all relevant catalog identities, including custom playlists.
7. Keep heavy decorative breathing animation paused during scroll.
8. Reduce keep-alive and prefetch work in high-volume artist, album, folder, hidden-track, and video viewports.
9. Retain and build on earlier YAZEN work for audio artwork, scroll coalescing, and playback state.

The goal is to reduce sources of avoidable work, not to claim mathematically zero lag. Perceived smoothness must be measured on actual hardware with representative libraries.

## 2. Exact baseline and repository provenance

The public GitHub `main` branch was checked before making this V5 source pass. Its tip was `28cc70f` (`Format mini player source`), and the last observed Flutter CI run for that commit was successful. The branch history included:

- `e33417d` — `Add smooth library fast scrolling`
- `27991b1` — `Polish mini player rendering`
- `28cc70f` — formatting-only mini-player source changes

However, the full local source archive supplied in this conversation contains newer/cumulative files not present in the checked remote tree (including additional library engine and viewport services). **This V5 package therefore uses the supplied Iteration 5 source archive as its base; it does not replace it with the older GitHub tree and it does not push anything to GitHub.**

## 3. Findings by subsystem

### 3.1 Library browsing and data model

**Strengths retained**

- Lazy list/grid construction is already used instead of eagerly building every track widget.
- `LibraryTrackViewport` centralizes list/grid cache extent and keep-alive choices.
- `LibraryDataEngine` caches filtered/sorted/search results against source identity and dynamic revisions.
- `LibrarySearchService` uses cached normalized track text and supports Arabic normalization.
- `LibraryViewportEngine` coalesces fast-scroll thumb updates to at most one jump per frame.
- Audio artwork uses a bounded load gate, memory LRU, and persistent disk cache.
- `NowPlayingScope` limits updates to the active track and pauses its pulse during scroll.
- `ScrollPerformanceMode` already pauses some decorative background work while scrolling.

**Important limitation**

`MediaLibraryService.querySongs()` still obtains the device's song collection through `on_audio_query` as a full list. It is not true server-side/MediaStore paging at the Dart API boundary. A virtualized list bounds widget construction, but it does not make the initial MediaStore query, platform-channel result transfer, model conversion, or complete in-memory catalog free. A true paged MediaStore repository is a separate architectural project and must preserve search, folders, playlists, sorting, playback queue snapshots, permission states, and external file updates. It was not replaced with a superficial Dart-only page slice.

### 3.2 Android video library and thumbnails

Before this pass, the YAZEN native video path performed MediaStore cursor work and thumbnail generation through the method-channel handler. Those operations can be expensive and can occupy the platform thread. This is a direct potential UI-jank source.

**V5 source changes**

- A dedicated single-thread executor now performs video MediaStore enumeration.
- A separate two-thread executor handles content thumbnail extraction and JPEG encoding, so a library scan cannot starve currently visible thumbnails.
- Simultaneous `queryVideos` requests are coalesced into one scan and receive the same immutable result list.
- Video identity is keyed by content URI rather than a potentially colliding path/name/size combination.
- Thumbnail bitmap recycling is guaranteed in a `finally` block.
- Executor rejection and Activity teardown are handled without leaving pending method-channel requests hanging.
- Activity destruction is visible across worker threads; outstanding scan results are completed with a lifecycle error during teardown.
- The video query's provider/volume enumeration is covered by its failure boundary and continues to return any successfully scanned subset.

### 3.3 Video thumbnail widgets

**V5 source changes**

- A shared bounded gate limits video thumbnail work to two concurrent loads and eight queued requests.
- The gate prefers the newest viewport requests and drops stale queued requests when full.
- Requests for the same source/size/version are deduplicated while in flight.
- A small memory LRU is bounded by both 24 MiB and 64 entries; unusually large byte arrays remain transient.
- The cache key includes the URI, requested pixel width, media modification timestamp, and size.
- The request is made near card display size instead of requesting a very large source image for a small list/grid card.
- `FutureBuilder` is keyed by request identity so a recycled viewport element cannot flash a previous video's cached `snapshot.data` over a newly assigned card.
- Decoded display uses low-cost filtering and a repaint boundary.
- Video `LibraryTrackViewport` uses a reduced cache extent and disables automatic keep-alives for rows/cards.

### 3.4 Artwork

**Earlier improvements preserved**

- Artwork reads and image preparation are bounded.
- Memory cache has a byte budget.
- Persistent artwork writes are serialized and publish through a temporary file followed by rename, reducing the chance of a truncated cache entry being treated as valid.
- Small list artwork requests target near-display pixel dimensions.
- Pixel-content cropping is reserved for artwork surfaces that need it; ordinary video-card artwork skips the pixel scan/re-encode step.
- `OnAudioQuery` is shared by artwork widgets rather than instantiated for each row.
- Disk-cache trimming is less frequent (64 writes rather than 16) to reduce directory-wide maintenance scans during active scrolling.

### 3.5 Search and sorting

**Search invalidation fix**

Search results are cached by query and catalog identity. The controller received playlist-manager notifications, but the search screen's selected revision did not include the custom playlist list identity. As a result, a search screen kept open while a custom playlist changed could fail to rebuild its cached playlist results. V5 adds `identityHashCode(playlistManager.playlists)` to the selected catalog revision.

**Sort optimization**

For `mostPlayed` and `recentlyPlayedFirst`, dynamic values are now read once per candidate track before sorting and passed into the comparator as maps. The comparator no longer repeatedly calls controller callbacks O(n log n) times. A regression test checks that play-count reads equal the number of candidate tracks and that ordering is correct.

### 3.6 Motion and visual rendering

- The full-player breathing glow listens to the shared scroll performance mode and stops its continuous shadow animation while scrolling.
- Existing RGB and ambient layers already yield while scrolling; this V5 change closes another continuous animation path.
- `EchoReveal` supports reduced-motion settings; the existing motion architecture is retained rather than replaced with a different animation framework.
- Home/library navigation uses a `PageView.builder`; each library collection uses lazy list/grid builders rather than constructing the entire collection as widgets.
- `TrackListTile` selects only the active theme preset and subscribes to the active-track inherited-model aspect, limiting unrelated row rebuilds.
- `NowPlayingScope` pauses the active-row pulse while scrolling and avoids making all rows dependent on every playback tick.
- The mini-player already uses a repaint boundary and contained animated transitions; that performance work is retained.
- The theme backdrop separates its animated layer with a repaint boundary. Its custom wallpaper blur is static, not a per-frame list-item effect.
- Full Player contains the more expensive dynamic visual effects (visualizer and glow); the breathing glow now yields while scrolling. The visualizer is a product feature and was not disabled indiscriminately.
- Library lists keep the YAZEN design language and card structure. The pass intentionally avoids an ungrounded visual redesign without current app screenshots or a running build.
- Video thumbnail and video-card artwork processing is reduced without changing the visual composition of the cards.

**UI review boundary:** the only user-uploaded image visible in the working files is a browser screenshot of APKLint's decompile form, not a YAZEN screen. Therefore this section is a code/layout/performance assessment; it is not a visual pixel review of the rendered app. Font balance, exact spacing, contrast on the user's device, and animation feel still require a current APK screenshot or device run.

### 3.7 Video player lifecycle

The current source preserves playback while Android moves into Picture-in-Picture's `inactive` state, pauses when the app actually becomes hidden/backgrounded, and resumes only if the video had been playing before backgrounding. This behaviour is retained in the V5 baseline and should be checked on a real Android device, particularly Android versions with differing PiP lifecycle ordering.

### 3.8 Audio playback, queue, service, and effects

The existing audio architecture remains in place. The prior source review found:

- `HybridAudioHandler` is built around `just_audio` and `audio_service` with an audio session coordinator.
- Queue mutations are serialized and selection-generation guards protect against stale selection requests.
- Queue invariant recovery and race-focused tests already exist.
- Playback persistence and startup restore are separated from initial paint.
- Equalizer/effect setup uses retry and session-aware mechanisms.

These subsystems were not wholesale rewritten in V5 because the current architecture already has explicit state/race protections and a set of focused tests. Next audio-engine work should be driven by concrete reproduced failures, session traces, or unsupported codec evidence—not by copying Lark's player implementation.

### 3.9 Persistence, playlists, settings, and privacy

- Playlist persistence and ordering already have serialized writes and focused tests; V5 retained these contracts.
- Search history stays in the existing local preferences store.
- Media artwork remains an optimization and must never become a prerequisite for audio playback.
- No analytics upload, account sync, background network service, external telemetry, or new media-content logging was introduced.

## 4. Lark Player — what was actually learned and reused

The supplied decompiled APK contains the following relevant classes/components:

- `MediaDatabaseHelper$updateByPage$2`: updates a database in page-sized groups, opening and committing SQLite transactions at page boundaries and checking coroutine cancellation.
- `MediaFileObserverHelper$startWatchMedia$1` and `$doOnEvent$1`: set up file-watch-related work and guard a scan-triggering operation against overlapping execution.
- `MediaScanner$scanFile$1`: shows per-file scan/import validation and handling paths.
- `PlaybackService`, `AbstractPlaybackService`, `SingleProcessModePlaybackService`, `MultiProcessModePlaybackService`, and `PlaybackMediaSessionHandler`: show service/session boundaries used by the app.
- `FFmpegPlayer` and bundled IJK/FFmpeg libraries: show a separate video playback path in that application.

**Adapted in YAZEN**

- Work is bounded and serialized where it protects shared data or reduces resource pressure.
- Video MediaStore queries are now moved off the Android main thread and coalesced.
- Thumbnail work is separately bounded and deduplicated.
- The existing YAZEN audio service/media-session boundary is retained.

**Not copied**

- No proprietary Lark implementation code or obfuscated helper code was transplanted.
- No IJK/FFmpeg engine was inserted into YAZEN's audio path.
- The Lark database paging routine is not claimed to be the app's visible song-list pagination algorithm; the decompiled routine directly demonstrates paged database writes, not necessarily paged UI reads.

## 5. Exact file-level V5 changes

| File | Change |
|---|---|
| `android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt` | Dedicated video query/thumbnail executors, query coalescing, URI identity, bitmap cleanup, safe teardown/error handling, provider failure boundary. |
| `lib/widgets/video_thumbnail.dart` | Newest-first bounded queue, deduplication, memory LRU, display-sized request, keyed FutureBuilder to avoid stale prior-card frames. |
| `third_party/video_thumbnail/android/src/main/java/xyz/justsoft/video_thumbnail/VideoThumbnailPlugin.java` | Native decoder pool capped at two workers with defensive executor-shutdown handling and deterministic bitmap/stream cleanup. |
| `lib/screens/library/local_media_screen.dart` | Smaller video thumbnail target, disable expensive crop analysis for card artwork, bounded video cache extent/keep-alives; reduce cache/keep-alive for large hidden/artist/album/folder viewports. |
| `lib/screens/search/search_screen.dart` | Include custom-playlist list identity in catalog revision, preventing stale playlist search results. |
| `lib/services/library_data_engine.dart` | Precompute dynamic sort statistics once per track before comparison. |
| `lib/widgets/echo_motion.dart` | Pause full-player breathing glow while scrolling. |
| `lib/widgets/media_artwork.dart` | Share one `OnAudioQuery` instance across artwork widgets. |
| `lib/services/artwork_disk_cache.dart` | Run less-frequent trimming to reduce filesystem maintenance during scrolling. |
| `third_party/video_thumbnail/android/src/main/java/xyz/justsoft/video_thumbnail/VideoThumbnailPlugin.java` | Bound native decoder threads, handle executor shutdown, and make bitmap/stream cleanup reliable. |
| `third_party/video_thumbnail/LOCAL_PATCHES.md` | Record the vendored plugin compatibility/performance patches. |
| `lib/screens/player/yazen_video_player.dart` | Retains pause/resume-on-background behaviour while preserving PiP transition handling. |
| `test/library_data_engine_test.dart` | Add a regression test for one dynamic-stat read per candidate track during sort. |
| `tool/validate_v5_performance.py` | Add 18 source-level guardrails for bounded work, caching, viewport, and search/sort protections. |

## 6. What was deliberately not changed

1. **No true MediaStore paging yet.** The current audio catalog API returns the complete query result. A paged repository requires a deliberate redesign and queue/catalog contract tests.
2. **No new MediaStore ContentObserver/FileObserver integration yet.** Lark's observer design is useful, but a YAZEN observer must have a tested debounce, permission, lifecycle, engine-detach, and refresh-coalescing contract. An unsafe observer can cause repeated full-library scans or stale callbacks. This is a next-stage item, not a claimed V5 feature.
3. **No audio engine replacement.** The existing `just_audio`/`audio_service` architecture has queue and lifecycle tests; no evidence yet justifies introducing IJK/FFmpeg into it.
4. **No broad aesthetic restyle.** It would be irresponsible to redesign screen composition without a current running APK/screenshots and user approval of the visual direction. The V5 pass focuses on structural performance and preserving the YAZEN design language.
5. **No GitHub push or direct modification of the user's remote branch.** This ZIP is a reviewable source deliverable.

## 7. Validation status and honest limits

The supplied baseline contains 67 Dart source files and 35 Dart test files. This iteration adds one regression test inside the existing test suite and one Python source-guardrail script.


| Check | Result |
|---|---|
| Source archive extraction and file-level comparison | Completed. |
| Foundation validator | **Passed** on the final V5 source tree (`python3 tool/validate_foundation.py`). |
| V5 source guardrails | **18/18 passed** using `python3 tool/validate_v5_performance.py`; these are source-pattern checks, not compiler tests. |
| ZIP integrity | **Passed**: archive test completed with no errors; source/docs/test/tool files included. |
| Dart formatter / analyzer | Not run: Flutter/Dart SDK is unavailable in this environment. |
| Dart unit/widget tests | Not run: Flutter/Dart SDK is unavailable. One regression test was added but not executed here. |
| Android Kotlin/Gradle build | Not run: Android/Flutter Gradle toolchain is unavailable. A standalone Kotlin compile cannot resolve Android/Flutter dependencies and is not a valid Android build. |
| GitHub Actions for this V5 source | Not run: no branch was pushed and no workflow was triggered. The observed successful CI run is for the earlier remote commit only. |
| Real-device profiling / APK test | Not run. Must be done by the user on device after CI builds the artifact. |

## 8. Release/device test plan

Follow `V5_DEVICE_TEST_MATRIX.md`. At minimum, verify:

- Small, medium, and large libraries: 100, 500, 2,000, and 10,000+ tracks.
- Repeated fast flings in list and grid, including moving the scrollbar thumb from top to bottom and back.
- Warm and cold artwork-cache runs.
- Low-memory/background pressure and rotation/activity recreation.
- Add/delete/rename media, permission denial/partial access/regrant, and return from Android Settings.
- Several video formats and videos with/without embedded thumbnails.
- Playback continuity while browsing, changing tabs, opening search, and entering/leaving PiP.
- Audio focus: notification, alarm, call interruption, Bluetooth/headphone route change, and competing media app.
- Long playback (30 minutes), queue next/previous/seek, sleep timer, equalizer presets, and process restart/restore.

## 9. Acceptance criteria for calling V5 ready

- No Flutter framework exceptions, unhandled async errors, duplicate method-channel completions, or lifecycle callbacks after teardown.
- No stale video thumbnail flashes when viewport elements are reused.
- Video scanning and thumbnail extraction do not block Android's main thread.
- Pending image work remains bounded and prioritizes the current viewport.
- Search reflects playlist create/rename/edit while Search is still open.
- Sorting dynamic keys is O(n) reads plus O(n log n) comparisons, not O(n log n) provider callbacks.
- Audio queue state and displayed active media remain consistent through rapid repeated selection.
- Performance is measured in profile mode on the target device; do not infer release performance from debug-only timings.
- The same device, library size, scroll path, and cache state are used for before/after comparisons.

---

**Engineering principle for future iterations:** preserve every confirmed gain; review each subsystem against the actual code; use Lark as a reference for architecture and patterns, not as an instruction to transplant obfuscated internals; measure before adding new engines or services; and keep this change log updated with source commit, exact files, tests, and known gaps.
