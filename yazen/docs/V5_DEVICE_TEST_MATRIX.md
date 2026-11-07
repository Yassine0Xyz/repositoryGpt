# YAZEN V5 — Device Validation Matrix

This matrix is for the first APK produced from the V5 source. Mark each row with pass/fail, device model, Android version, library count, cache state, and evidence (screen recording, Flutter DevTools trace, logcat excerpt with media paths removed).

## A. Browsing performance

| Scenario | Dataset | Expected result | Result |
|---|---:|---|---|
| Cold first open | 100 tracks | First usable screen appears; loading state does not block app navigation. | Pending |
| Cold first open | 500 tracks | No app freeze; loading and list publication remain responsive. | Pending |
| Cold first open | 2,000 tracks | No long main-thread stall; first list remains usable while secondary catalogs load. | Pending |
| Cold first open | 10,000+ tracks | No crash/OOM; measure query and first-paint timings separately. | Pending |
| Fast fling list | 500+ tracks | No blank frames or prolonged frame stalls; images for current rows win over stale queued requests. | Pending |
| Fast fling grid | 500+ tracks | Cards remain responsive; no large thumbnail decode burst. | Pending |
| Fast scrollbar drag | 2,000+ tracks | Thumb jumps coalesce; no queue of outdated intermediate jumps. | Pending |
| Revisit previous rows | Warm cache | Artwork reappears without repeated expensive decode/crop work. | Pending |
| Stress scroll repeat | 10 cycles | Memory stabilizes; no continuously growing thumbnail backlog. | Pending |

## B. Search and sort

| Scenario | Expected result | Result |
|---|---|---|
| Search common term in 10k songs | Search stays responsive; results are stable while typing. | Pending |
| Clear/re-enter same term | Cached search is reused for unchanged catalogs. | Pending |
| Create custom playlist while Search remains open | Search result list updates without leaving the screen. | Pending |
| Rename/edit playlist while Search remains open | Search reflects the new title/content. | Pending |
| `Most played` sort | Correct ordering; no repeated play-count read per comparator call. | Pending |
| `Recently played` sort | Correct ordering, with never-played tracks consistently last. | Pending |

## C. Artwork and video

| Scenario | Expected result | Result |
|---|---|---|
| Many audio covers, cold cache | UI remains interactive; queue stays bounded. | Pending |
| Repeat audio-cover scroll, warm cache | Cache hits avoid unnecessary MediaStore artwork requests. | Pending |
| 100+ videos with thumbnails | Native scan and thumbnail decoding do not block scrolling. | Pending |
| Fast video-grid fling | Thumbnail queue remains capped; newest visible cards have priority. | Pending |
| Recycled video card changes source | Old thumbnail does not flash on the new video card. | Pending |
| Missing/corrupt thumbnail | Safe placeholder; no crash. | Pending |
| Revoke media permission during use | No crash; subsequent reads fail gracefully and UI reflects permission state. | Pending |

## D. Playback and lifecycle

| Scenario | Expected result | Result |
|---|---|---|
| Browse while music plays | Queue, metadata, and playback position remain stable. | Pending |
| Rapidly tap different tracks | Latest user selection wins; no stale completion overwrites it. | Pending |
| Next/previous at queue boundaries | Circular navigation behaves as intended. | Pending |
| Open/close full player repeatedly | No duplicated listeners/timers; animation controllers are disposed. | Pending |
| Enter/leave PiP | Video remains playing in PiP; no unintended pause on `inactive`. | Pending |
| Background then foreground | Video resumes only if it was playing before the background transition. | Pending |
| Audio interruption | Pause/duck/restore follows audio-session policy and does not override newer user volume. | Pending |
| Bluetooth/headphone connect/disconnect | Route changes do not leave playback or focus in an invalid state. | Pending |
| Sleep timer | Stops playback once; no timer callback after disposal. | Pending |
| Process kill/restart | Playback restore is safe with removed or inaccessible media. | Pending |

## E. Visual quality and accessibility

| Scenario | Expected result | Result |
|---|---|---|
| Scroll while ambient theme active | Decorative animation yields; no competing full-time repaint. | Pending |
| Reduce motion enabled | Nonessential animations stop or render their final static state. | Pending |
| Light/dark/OLED theme switch | Contrast, surfaces, text, and selection remain readable. | Pending |
| Compact/comfortable density | Rows do not overflow; touch targets remain usable. | Pending |
| Large text/display scaling | Titles ellipsize safely; no clipped controls or overflow exceptions. | Pending |
| RTL/Arabic media metadata | Titles and artists remain legible and correctly aligned. | Pending |

## F. Required measurements

For each device profile, record:

- Device / chipset / RAM / Android version.
- Library size and video count.
- Cold/warm cache state.
- Time from app launch to first interactive song list.
- Time for initial audio scan and secondary artist/album/playlist scan.
- Flutter UI and raster frame times while flinging (profile mode).
- Peak and settled memory after 10 repeated scroll cycles.
- Native `queryVideos` duration and video count.
- Thumbnail-cache hit/miss count, rejected queued requests, and decode duration if instrumented.
- Crashes, framework exceptions, Android ANRs, or method-channel errors.

Do not label the release “zero lag” based on a single short manual scroll. Compare the same device, dataset, scroll actions, and cache state before and after.
