#!/usr/bin/env python3
"""Source-level guardrails for the YAZEN V5 performance architecture.

This script intentionally does not replace Flutter analysis, unit/widget tests,
Android compilation, or device profiling. It checks that the intended bounded
work and cache-invalidation protections remain present in the source tree.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise FileNotFoundError(f"Required source file is missing: {relative}")
    return path.read_text(encoding="utf-8")


checks: list[tuple[str, bool]] = []

main_activity = read(
    "android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt"
)
checks.extend(
    [
        (
            "video MediaStore scan uses a dedicated worker",
            "videoQueryExecutor.execute" in main_activity,
        ),
        (
            "video thumbnails use a separate bounded worker pool",
            "videoThumbnailExecutor.execute" in main_activity
            and "Executors.newFixedThreadPool(2)" in main_activity,
        ),
        (
            "overlapping video scans are coalesced",
            "pendingVideoQueryResults" in main_activity
            and "videoQueryInFlight" in main_activity,
        ),
        (
            "Activity teardown is visible to worker callbacks",
            "@Volatile\n    private var activityDestroyed" in main_activity,
        ),
    ]
)

video_widget = read("lib/widgets/video_thumbnail.dart")
checks.extend(
    [
        (
            "video thumbnail work is bounded and newest-first",
            "maxConcurrent: 2" in video_widget
            and "maxQueued: 8" in video_widget
            and "preferNewest: true" in video_widget,
        ),
        (
            "video thumbnail requests are deduplicated and cached",
            "_pending" in video_widget and "_maxCacheBytes" in video_widget,
        ),
        (
            "recycled video cards discard stale FutureBuilder snapshots",
            "key: ValueKey<String?>(_requestKey)" in video_widget,
        ),
    ]
)

plugin = read(
    "third_party/video_thumbnail/android/src/main/java/xyz/justsoft/video_thumbnail/VideoThumbnailPlugin.java"
)
checks.append(
    (
        "vendored Android decoder pool is fixed-size",
        "Executors.newFixedThreadPool(2)" in plugin
        and "Executors.newCachedThreadPool()" not in plugin,
    )
)

library_screen = read("lib/screens/library/local_media_screen.dart")
video_card = library_screen.split("class _VideoPreviewCard", 1)[1].split(
    "class _DurationBadge", 1
)[0]
checks.extend(
    [
        (
            "video card asks for display-sized thumbnails",
            "VideoThumbnailWidget(track: track, size: 340)" in video_card,
        ),
        (
            "video card artwork skips expensive pixel-bound cropping",
            "cropContentBounds: false" in video_card,
        ),
        (
            "large video viewports avoid automatic keep-alives",
            library_screen.count("addAutomaticKeepAlives: false") >= 4,
        ),
    ]
)

search_screen = read("lib/screens/search/search_screen.dart")
checks.append(
    (
        "search catalog revision includes custom playlist identity",
        "identityHashCode(value.playlistManager.playlists)" in search_screen,
    )
)

sort_engine = read("lib/services/library_data_engine.dart")
sort_test = read("test/library_data_engine_test.dart")
checks.extend(
    [
        (
            "dynamic sort keys are materialized before comparator calls",
            "final playCounts =" in sort_engine
            and "playCounts: playCounts" in sort_engine,
        ),
        (
            "dynamic sort callback regression test exists",
            "reads play-count sort keys once per track" in sort_test,
        ),
    ]
)

artwork = read("lib/widgets/media_artwork.dart")
disk_cache = read("lib/services/artwork_disk_cache.dart")
checks.extend(
    [
        (
            "audio artwork uses one shared OnAudioQuery instance",
            "static final OnAudioQuery _audioQuery" in artwork,
        ),
        (
            "artwork loads use a bounded newest-first gate",
            "maxQueued: 12" in artwork and "preferNewest: true" in artwork,
        ),
        (
            "disk artwork cache publishes atomically",
            "temporary.writeAsBytes(data, flush: true)" in disk_cache
            and "temporary.rename(file.path)" in disk_cache,
        ),
    ]
)

echo_motion = read("lib/widgets/echo_motion.dart")
checks.append(
    (
        "full-player breathing glow yields during scroll",
        "ScrollPerformanceMode.isScrolling.addListener(_onScrollModeChanged)"
        in echo_motion
        and "!_scrolling" in echo_motion,
    )
)

for label, passed in checks:
    print(f"{'PASS' if passed else 'FAIL'} {label}")

failed = [label for label, passed in checks if not passed]
print(f"\n{len(checks) - len(failed)}/{len(checks)} V5 source guardrails passed.")
if failed:
    print("Failed checks: " + "; ".join(failed), file=sys.stderr)
    sys.exit(1)
