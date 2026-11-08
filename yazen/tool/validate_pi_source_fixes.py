#!/usr/bin/env python3
"""Source-level checks for the 2026-11-08 Performance Intelligence fixes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

service = read("lib/diagnostics/core/diagnostics_service.dart")
main = read("lib/main.dart")
artwork = read("lib/widgets/media_artwork.dart")
disk_cache = read("lib/services/artwork_disk_cache.dart")
home = read("lib/screens/home/home_screen.dart")
tests = read("test/diagnostics_service_test.dart")

checks = {
    "pointer velocity uses PointerEvent timestamps": "calculateEventVelocity(" in service and "event.timeStamp" in service and "captureIntervalUs" in service,
    "pointer event timestamp clock is explicit": "pointerEventTimestampUs" in service and "flutter_pointer_event" in service,
    "scroll velocity uses drag source timestamps": "sourceTimeStamp" in service and "scroll_drag_event_timestamp" in service,
    "missing drag timestamps do not fabricate scroll velocity": "session.lastEventTimestamp=sourceTimeStamp" in "".join(service.split()) and "'velocitySource':velocity==null?'unavailable'" in "".join(service.split()),
    "root scroll listener forwards drag timestamps": "notification.dragDetails?.sourceTimeStamp" in main,
    "disk cache read I/O is separately traced": "artwork_disk_cache_read_io" in disk_cache,
    "disk write gate wait is separately traced": "artwork_disk_write_gate_wait" in disk_cache,
    "disk write I/O is separately traced": "artwork_disk_write_io" in disk_cache,
    "disk cache trim is traced": "artwork_disk_cache_trim" in disk_cache,
    "disk write outcome is propagated precisely to artwork diagnostics": "final result = await ArtworkDiskCache.instance.write" in artwork and "ArtworkDiskWriteResult.failed" in artwork and "ArtworkDiskWriteResult.rejectedByGate" in artwork,
    "More sheet uses a Material surface": "return Material(" in home and "_MoreOption(" in home,
    "sort sheet uses a Material surface": "sort) => Material(" in home and "child: RadioListTile<LibrarySort>" in home,
    "timestamp regression tests exist": "calculates pointer velocity from event timestamps" in tests and "does not calculate velocity without a positive event timestamp interval" in tests,
}

for label, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {label}")

failed = [label for label, passed in checks.items() if not passed]
if failed:
    raise SystemExit(f"{len(failed)} source-fix check(s) failed")
print(f"All {len(checks)} Performance Intelligence source-fix checks passed.")
