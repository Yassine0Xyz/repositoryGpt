#!/usr/bin/env python3
"""Static guardrails for the temporary YAZEN diagnostics subsystem."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "diagnostics service exists": ROOT / "lib/diagnostics/core/diagnostics_service.dart",
    "diagnostics screen exists": ROOT / "lib/diagnostics/screens/diagnostics_screen.dart",
    "removal map exists": ROOT / "docs/TEMP_DIAGNOSTICS_REMOVAL.md",
    "diagnostics service test exists": ROOT / "test/diagnostics_service_test.dart",
}
for label, path in checks.items():
    if not path.is_file():
        raise SystemExit(f"FAIL: {label}: missing {path.relative_to(ROOT)}")

service = checks["diagnostics service exists"].read_text()
main = (ROOT / "lib/main.dart").read_text()
settings = (ROOT / "lib/screens/settings/settings_screen.dart").read_text()
artwork = (ROOT / "lib/widgets/media_artwork.dart").read_text()
media_library = (ROOT / "lib/services/media_library_service.dart").read_text()
native = (ROOT / "android/app/src/main/kotlin/com/yassine/yazen/MainActivity.kt").read_text()
workflow = (ROOT / ".github/workflows/flutter-ci.yml").read_text()

required = [
    ("Flutter frame timing callback", "addTimingsCallback" in service),
    ("slow frame tracking", "slow_frame" in service and "verySlowFrames" in service),
    ("scroll latency and velocity", "startToFirstUpdateMs" in service and "estimatedPixelsPerSecond" in service),
    ("bounded event history", "_maxEvents = 12000" in service and "removeFirst()" in service),
    ("JSON and TXT report", "yazen-diagnostics-$stamp.json" in service and "yazen-diagnostics-$stamp.txt" in service),
    ("session starts at app launch", "DiagnosticsService.instance.start()" in main),
    ("Settings export entry", "Export diagnostic logs" in settings),
    ("artwork instrumentation", "artwork_load_complete" in artwork and "artwork_disk_cache_hit" in artwork),
    ("MediaStore query timing", "media_query_all_songs" in media_library and "media_query_videos" in media_library and "durationMs" in media_library),
    ("Android process memory and CPU snapshot", "processPssKb" in native and "processCpuPercentSincePreviousSnapshot" in native),
    ("Android Downloads export", "YAZEN Diagnostics" in native),
    ("periodic process resource sampling", "Duration(seconds: 5)" in service and "resourceSnapshotsDuringSession" in service),
    ("diagnostics CI branch", "diagnostics/temp-performance-v1" in workflow),
]
failed = [label for label, passed in required if not passed]
for label, passed in required:
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    raise SystemExit(f"{len(failed)} diagnostics guardrail(s) failed")
print(f"All {len(required)} temporary diagnostics guardrails passed.")
