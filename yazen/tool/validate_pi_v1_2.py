#!/usr/bin/env python3
"""Static source guardrails for YAZEN Performance Intelligence V1.2."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = []

def check(name, condition):
    checks.append((name, bool(condition)))

service = (ROOT / 'lib/diagnostics/core/diagnostics_service.dart').read_text()
artwork = (ROOT / 'lib/widgets/media_artwork.dart').read_text()
disk = (ROOT / 'lib/services/artwork_disk_cache.dart').read_text()
gate = (ROOT / 'lib/services/bounded_load_gate.dart').read_text()
video = (ROOT / 'lib/widgets/video_thumbnail.dart').read_text()
controller = (ROOT / 'lib/controllers/hybrid_music_controller.dart').read_text()
settings = (ROOT / 'lib/screens/settings/settings_screen.dart').read_text()
theme = (ROOT / 'lib/widgets/theme_picker_sheet.dart').read_text()
player = (ROOT / 'lib/screens/player/full_player_screen.dart').read_text()

check('null artwork results are counted separately from exceptions',
      "_artworkLoadsReturnedNull++" in service and "_artworkLoadsExceptionFailed++" in service)
check('artwork success is based on success=true',
      "if (data['success'] == true)" in service and "_artworkLoadsSucceeded++" in service)
check('source fetch has explicit failure reasons and attempts',
      'failureReason' in artwork and 'sourceAttempts' in artwork)
check('raw artwork cache keys are not written to telemetry',
      "'cacheKey': key" not in artwork and "'cacheKey': key" not in disk)
check('disk cache index is scanned once in background',
      '_ensureCacheIndex(directory)' in disk and 'Duration(seconds: 2)' in disk and '_cacheIndexReady' in disk)
check('disk cache writes update the index incrementally',
      '_updateCacheIndex(entry)' in disk and '_pendingIndexUpdates[entry.path]' in disk)
trim = disk[disk.index('Future<void> _trim()'):disk.index('class _ArtworkCacheEntry')]
check('trim does not enumerate/stat the whole directory',
      '.list()' not in trim and '.stat()' not in trim and '_cacheIndex.values.toList()' in trim)
check('trim only sorts/deletes when cache is actually over limit',
      'bytesBeforeTrim <= _maxBytes' in trim and 'size_limit_enforced' in trim)
check('trim serializes with active cache reads and writes',
      '_trimCompleter' in disk and '_activeReads' in disk and 'waitedForTrim' in disk)
check('cache index scan and trim stages have independent spans',
      "'artwork_disk_cache_index_scan'" in disk and "'artwork_disk_cache_trim'" in disk)
check('bounded gate distinguishes queue eviction from queue full',
      'enum LoadPermitResult { acquired, queueEvicted, queueFull }' in gate and 'queueEvictions' in gate)
check('artwork gate reports rejection reason without raising concurrency',
      'queue_evicted_by_newer_request' in artwork and 'maxConcurrent: 2' in artwork)
check('disk write outcomes distinguish skipped, rejected, failed and written',
      'enum ArtworkDiskWriteResult' in disk and 'ArtworkDiskWriteResult.failed' in disk and 'ArtworkDiskWriteResult.rejectedByGate' in artwork)
check('video thumbnails have cache, source, gate and load spans',
      "'video_thumbnail_load'" in video and "'video_thumbnail_source_fetch'" in video and "'video_thumbnail_gate_wait'" in video)
check('video thumbnails report first visible frame timing',
      "'video_thumbnail_first_frame_visible'" in video and 'timeToFirstVisibleFrameUs' in video)
check('video thumbnail pipeline is included in exported summary',
      "'videoThumbnailPipeline'" in service and 'averageTimeToVisibleMs' in service)
check('secondary catalogs wait until primary library load ends',
      '_libraryLoadInProgress = false' in controller and 'shouldLoadSecondaryCatalogs' in controller)
check('secondary catalogs are loaded sequentially, not with Future.wait',
      'library_secondary_catalog_pipeline' in controller and 'Future.wait<dynamic>' not in controller)
check('secondary catalogs yield after each published result',
      'library_catalog_published' in controller and '_yieldForCatalogFrame(fallbackMilliseconds: 60)' in controller)
check('stale secondary catalog results are discarded after await',
      'Discard the stale payload before assigning or notifying' in controller)
check('frame interval uses engine vsync timestamps',
      'FramePhase.vsyncStart' in service and 'frameStartIntervalUs' in service and 'callbackGapUs' in service)
check('recent frame percentiles retain fractional milliseconds',
      'double get p50FrameMs' in service and "'p99': double.parse(p99FrameMs.toStringAsFixed(3))" in service)
check('journal export freezes only after prior drain completes',
      service.index('while (_journalDraining)') < service.index('_journalSnapshotting = true'))
check('journal completeness checks first/last sequence and persisted counts',
      "analysis['firstSequence'] == 1" in service and "analysis['lastSequence'] == snapshotSequence" in service and 'snapshotQueuedCount == snapshotEventCount' in service)
check('journal counts malformed non-object or sequence-less rows',
      "if (decoded is! Map)" in service and "if (sequence is! num)" in service)
check('framework warnings are counted separately and retain stack context',
      '_flutterFrameworkReportEvents++' in service and 'handler_capture_fallback' in service and "'information': information" in service)
check('thread CPU aggregates are keyed by thread ID',
      'final threadCpuTickTotals = <int, Map<String, Object?>>{}' in service and "'threadId': id" in service)
check('settings cards provide an intervening Material ancestor',
      'child:Material(color:Colors.transparent,child:child)' in ''.join(settings.split()))
check('theme picker provides an intervening Material ancestor',
      'child: Material(' in theme and 'color: Colors.transparent' in theme)
check('full-player decorated sheet provides a Material ancestor',
      'class _SheetSurface' in player and 'child: Material(' in player)
check('pointer finish records event-timestamp gesture duration and tap/drag candidate',
      'startEventTimestampUs' in service and 'durationClock' in service and 'gestureKind' in service and 'maxDisplacement' in service)
check('lifecycle interruption closes active pointer and scroll sessions',
      "'pointer_interrupted'" in service and "'scroll_interrupted'" in service)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL') + ': ' + name)
print(f'{len(checks) - len(failed)}/{len(checks)} V1.2 source guardrails passed.')
if failed:
    raise SystemExit(1)
