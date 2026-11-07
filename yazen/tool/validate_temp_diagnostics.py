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
    ("Flutter frame timing callback", "addTimingsCallback" in service and "frame_timing" in service),
    ("refresh-rate-aware frame budget", "frameBudgetUs" in service and "displayRefreshRateHz" in service),
    ("scroll and pointer velocity samples", "velocityPixelsPerSecond" in service and "velocityXPerSecond" in service and "pointer_move" in service),
    ("bounded dashboard plus durable journal", "_dashboardEventLimit = 12000" in service and "_pendingJournalLimit" in service and "openWrite(mode: FileMode.append)" in service),
    ("full-session JSONL plus JSON and Markdown export", "jsonl" in service.lower() and "yazen-pi-session-$stamp.json" in service and "yazen-pi-session-$stamp.md" in service),
    ("session starts at app launch", "DiagnosticsService.instance.start()" in main),
    ("Settings export entry", "Export complete session" in settings),
    ("artwork tracing, cache and first-visible timing", "startSpan('artwork_load'" in artwork and "artwork_disk_cache_hit" in artwork and "artwork_first_frame_visible" in artwork),
    ("MediaStore query tracing", "startSpan(operation)" in media_library and "endSpan(span, 'complete'" in media_library),
    ("Android process memory and CPU snapshot", "processPssKb" in native and "processCpuPercentSincePreviousSnapshot" in native and "threadCpuSamples" in native),
    ("Android Downloads journal streaming", "exportDiagnosticJournal" in native and "YAZEN Diagnostics" in native),
    ("hybrid resource sampling", "Duration(seconds: _deepInvestigation ? 1 : 5)" in service and "resourceSnapshotCountInJournal" in service),
    ("diagnostics CI branch", "diagnostics/temp-performance-v1" in workflow),
    ("global pointer capture", "onPointerMove: DiagnosticsService.instance.pointerMove" in main and "onPointerSignal: DiagnosticsService.instance.pointerSignal" in main),
    ("trace correlation and full journal analysis", "activeSpanFrameCorrelations" in service and "_buildAnalysisFromJournal" in service),
    ("diagnostics overhead instrumentation", "_recordCostSamples" in service and "_journalDrainTotalUs" in service),
    ("library pipeline stage spans", "library_sort_filter" in (ROOT / "lib/services/library_data_engine.dart").read_text() and "library_index_snapshot_build" in (ROOT / "lib/services/library_data_engine.dart").read_text()),
    ("playback and user-action journal coverage", "playback_track_requested" in (ROOT / "lib/controllers/hybrid_music_controller.dart").read_text() and "sleep_timer_activated" in (ROOT / "lib/services/hybrid_audio_handler.dart").read_text()),
    ("Flutter build/layout/paint deep profiling", "debugProfileBuildsEnabled" in service and "debugProfileLayoutsEnabled" in service and "debugProfilePaintsEnabled" in service),
]
failed = [label for label, passed in required if not passed]
for label, passed in required:
    print(f"{'PASS' if passed else 'FAIL'}: {label}")
if failed:
    raise SystemExit(f"{len(failed)} diagnostics guardrail(s) failed")
print(f"All {len(required)} temporary diagnostics guardrails passed.")
