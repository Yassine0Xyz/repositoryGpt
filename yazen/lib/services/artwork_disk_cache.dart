import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/core/diagnostics_service.dart';
import 'bounded_load_gate.dart';

enum ArtworkDiskWriteResult {
  written,
  skippedInvalidPayload,
  rejectedByGate,
  failed,
}

class DiskArtwork {
  const DiskArtwork({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Small persistent cache for artwork bytes sized for their display role.
///
/// The cache index is scanned once per process in the background. Subsequent
/// writes update the index incrementally, so trimming does not repeatedly
/// enumerate and stat every thumbnail while the user is scrolling.
class ArtworkDiskCache {
  ArtworkDiskCache._();

  static final ArtworkDiskCache instance = ArtworkDiskCache._();
  static const int _maxBytes = 64 * 1024 * 1024;
  static const int _trimWriteBudgetBytes = 48 * 1024 * 1024;
  static Future<Directory>? _directoryFuture;
  static final BoundedLoadGate _writeGate = BoundedLoadGate(
    maxConcurrent: 1,
    maxQueued: 24,
  );

  final Map<String, _ArtworkCacheEntry> _cacheIndex =
      <String, _ArtworkCacheEntry>{};
  final Map<String, _ArtworkCacheEntry> _pendingIndexUpdates =
      <String, _ArtworkCacheEntry>{};
  Future<void>? _cacheIndexFuture;
  Future<void>? _trimFuture;
  Completer<void>? _trimCompleter;
  bool _trimInProgress = false;
  int _activeReads = 0;
  bool _cacheIndexReady = false;
  bool _cacheIndexScheduled = false;
  int _knownCacheBytes = 0;
  int _bytesWrittenSinceTrim = 0;

  Future<Directory> _directory() =>
      _directoryFuture ??= getApplicationSupportDirectory().then((root) async {
        final directory = Directory('${root.path}/artwork-thumbnails-v2');
        await directory.create(recursive: true);
        // Index construction is intentionally deferred from the first read/write.
        // It must not compete with the first visible artwork requests.
        if (!_cacheIndexScheduled && !_cacheIndexReady) {
          _cacheIndexScheduled = true;
          unawaited(
            Future<void>.delayed(const Duration(seconds: 2))
                .then((_) => _ensureCacheIndex(directory))
                .whenComplete(() => _cacheIndexScheduled = false),
          );
        }
        return directory;
      });

  String _fileName(String key) {
    var hash = 0xcbf29ce484222325;
    for (final byte in key.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  Future<DiskArtwork?> read(String key) async {
    final maintenanceWaitSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_read_maintenance_wait',
    );
    final pendingTrim = _trimCompleter;
    if (pendingTrim != null) await pendingTrim.future;
    DiagnosticsService.instance.endSpan(
      maintenanceWaitSpan,
      'complete',
      <String, Object?>{'waitedForTrim': pendingTrim != null},
    );
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_read_io',
      data: <String, Object?>{
        'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
      },
    );
    _activeReads++;
    try {
      final file = File('${(await _directory()).path}/${_fileName(key)}.art');
      if (!await file.exists()) {
        DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
          'hit': false,
          'reason': 'file_missing',
        });
        return null;
      }
      final data = await file.readAsBytes();
      if (data.length < 8) {
        DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
          'hit': false,
          'reason': 'invalid_header',
          'bytes': data.length,
        });
        return null;
      }
      final header = ByteData.sublistView(data, 0, 8);
      final width = header.getUint32(0);
      final height = header.getUint32(4);
      if (width == 0 || height == 0 || data.length == 8) {
        DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
          'hit': false,
          'reason': 'invalid_dimensions_or_empty_payload',
          'bytes': data.length,
        });
        return null;
      }
      // Do not touch the file timestamp on every cache hit. This keeps reads
      // read-only; eviction uses the last successful write time instead.
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
        'hit': true,
        'bytes': data.length,
        'width': width,
        'height': height,
      });
      return DiskArtwork(
        bytes: Uint8List.sublistView(data, 8),
        width: width,
        height: height,
      );
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      return null;
    } finally {
      _activeReads--;
    }
  }

  Future<ArtworkDiskWriteResult> write(
    String key,
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final maintenanceWaitSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_write_maintenance_wait',
    );
    final pendingTrim = _trimCompleter;
    if (pendingTrim != null) await pendingTrim.future;
    DiagnosticsService.instance.endSpan(
      maintenanceWaitSpan,
      'complete',
      <String, Object?>{'waitedForTrim': pendingTrim != null},
    );
    final gateSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_write_gate_wait',
      data: <String, Object?>{
        'activeWrites': _writeGate.activeLoads,
        'queuedWrites': _writeGate.queuedLoads,
        'rejectedWrites': _writeGate.rejectedLoads,
        'queueEvictions': _writeGate.queueEvictions,
        'queueFullRejections': _writeGate.queueFullRejections,
        'maxConcurrent': _writeGate.maxConcurrent,
        'maxQueued': _writeGate.maxQueued,
      },
    );
    final permitResult = await _writeGate.acquireWithResult();
    if (permitResult != LoadPermitResult.acquired) {
      DiagnosticsService.instance
          .endSpan(gateSpan, 'rejected', <String, Object?>{
            'reason':
                permitResult == LoadPermitResult.queueEvicted
                    ? 'queue_evicted_oldest_write'
                    : 'queue_capacity_unavailable',
            'activeWrites': _writeGate.activeLoads,
            'queuedWrites': _writeGate.queuedLoads,
            'rejectedWrites': _writeGate.rejectedLoads,
            'queueEvictions': _writeGate.queueEvictions,
            'queueFullRejections': _writeGate.queueFullRejections,
          });
      return ArtworkDiskWriteResult.rejectedByGate;
    }
    DiagnosticsService.instance.endSpan(gateSpan, 'complete', <String, Object?>{
      'activeWrites': _writeGate.activeLoads,
      'queuedWrites': _writeGate.queuedLoads,
      'rejectedWrites': _writeGate.rejectedLoads,
      'queueEvictions': _writeGate.queueEvictions,
      'queueFullRejections': _writeGate.queueFullRejections,
    });

    final ioSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_write_io',
      data: <String, Object?>{
        'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
        'bytes': bytes.length,
        'width': width,
        'height': height,
      },
    );
    try {
      if (bytes.isEmpty ||
          bytes.length > _maxBytes ~/ 2 ||
          width <= 0 ||
          height <= 0) {
        DiagnosticsService.instance.endSpan(
          ioSpan,
          'skipped',
          <String, Object?>{'reason': 'invalid_artwork_payload'},
        );
        return ArtworkDiskWriteResult.skippedInvalidPayload;
      }
      final directory = await _directory();
      final file = File('${directory.path}/${_fileName(key)}.art');
      final header =
          ByteData(8)
            ..setUint32(0, width)
            ..setUint32(4, height);
      final data =
          Uint8List(8 + bytes.length)
            ..setRange(0, 8, header.buffer.asUint8List())
            ..setRange(8, 8 + bytes.length, bytes);

      // Publish atomically so an interrupted write cannot look like a valid hit.
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }

      final entry = _ArtworkCacheEntry(
        path: file.path,
        sizeBytes: data.length,
        modifiedAt: DateTime.now(),
      );
      _updateCacheIndex(entry);
      _bytesWrittenSinceTrim += data.length;
      final shouldScheduleTrim =
          _cacheIndexReady
              ? _knownCacheBytes > _maxBytes
              : _bytesWrittenSinceTrim >= _trimWriteBudgetBytes;
      if (shouldScheduleTrim) _bytesWrittenSinceTrim = 0;

      DiagnosticsService.instance.endSpan(ioSpan, 'complete', <String, Object?>{
        'writtenBytes': data.length,
        'cacheIndexReady': _cacheIndexReady,
        'indexedCacheBytes': _cacheIndexReady ? _knownCacheBytes : null,
        'bytesWrittenSinceLastTrim': _bytesWrittenSinceTrim,
        'trimScheduled': shouldScheduleTrim,
      });
      if (shouldScheduleTrim) _scheduleTrim(directory);
      return ArtworkDiskWriteResult.written;
    } catch (error) {
      DiagnosticsService.instance.endSpan(ioSpan, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      return ArtworkDiskWriteResult.failed;
    } finally {
      _writeGate.release();
    }
  }

  void _updateCacheIndex(_ArtworkCacheEntry entry) {
    if (!_cacheIndexReady) {
      _pendingIndexUpdates[entry.path] = entry;
      return;
    }
    final previous = _cacheIndex[entry.path];
    if (previous != null) _knownCacheBytes -= previous.sizeBytes;
    _cacheIndex[entry.path] = entry;
    _knownCacheBytes += entry.sizeBytes;
  }

  Future<void> _ensureCacheIndex(Directory directory) {
    if (_cacheIndexReady) return Future<void>.value();
    final existing = _cacheIndexFuture;
    if (existing != null) return existing;
    final scan = _scanCacheIndex(directory);
    _cacheIndexFuture = scan.whenComplete(() {
      _cacheIndexFuture = null;
      if (_cacheIndexReady && _knownCacheBytes > _maxBytes) {
        _scheduleTrim(directory);
      }
    });
    return _cacheIndexFuture!;
  }

  Future<void> _scanCacheIndex(Directory directory) async {
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_index_scan',
    );
    final clock = Stopwatch()..start();
    var listDurationUs = 0;
    var statDurationUs = 0;
    var statFailures = 0;
    var fileCount = 0;
    var indexedBytes = 0;
    try {
      final listClock = Stopwatch()..start();
      final files =
          await directory
              .list()
              .where((entity) => entity is File && entity.path.endsWith('.art'))
              .cast<File>()
              .toList();
      listClock.stop();
      listDurationUs = listClock.elapsedMicroseconds;
      fileCount = files.length;
      final statClock = Stopwatch()..start();
      final discovered = <String, _ArtworkCacheEntry>{};
      for (final file in files) {
        try {
          final stat = await file.stat();
          final entry = _ArtworkCacheEntry(
            path: file.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          );
          discovered[file.path] = entry;
          indexedBytes += stat.size;
        } catch (_) {
          statFailures++;
        }
      }
      statClock.stop();
      statDurationUs = statClock.elapsedMicroseconds;

      _cacheIndex
        ..clear()
        ..addAll(discovered);
      _knownCacheBytes = indexedBytes;
      // Apply writes that completed while the one-time directory scan was in
      // flight. The latest update for a path wins over the scanned metadata.
      final pendingUpdatesApplied = _pendingIndexUpdates.length;
      for (final update in _pendingIndexUpdates.values) {
        final previous = _cacheIndex[update.path];
        if (previous != null) _knownCacheBytes -= previous.sizeBytes;
        _cacheIndex[update.path] = update;
        _knownCacheBytes += update.sizeBytes;
      }
      _pendingIndexUpdates.clear();
      _cacheIndexReady = true;
      _bytesWrittenSinceTrim = 0;
      clock.stop();
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
        'fileCount': fileCount,
        'indexedBytes': _knownCacheBytes,
        'statFailures': statFailures,
        'totalDurationUs': clock.elapsedMicroseconds,
        'listDurationUs': listDurationUs,
        'statDurationUs': statDurationUs,
        'pendingWriteUpdatesApplied': pendingUpdatesApplied,
      });
    } catch (error) {
      if (clock.isRunning) clock.stop();
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
        'fileCount': fileCount,
        'indexedBytes': indexedBytes,
        'statFailures': statFailures,
        'totalDurationUs': clock.elapsedMicroseconds,
        'listDurationUs': listDurationUs,
        'statDurationUs': statDurationUs,
      });
    }
  }

  void _scheduleTrim(Directory directory) {
    if (_trimFuture != null) return;
    _trimFuture = Future<void>(() async {
      await _ensureCacheIndex(directory);
      if (!_cacheIndexReady) {
        _bytesWrittenSinceTrim = _trimWriteBudgetBytes;
        DiagnosticsService.instance.record(
          'artwork_disk_cache_trim_deferred',
          <String, Object?>{'reason': 'cache_index_unavailable'},
        );
        return;
      }
      // Wait for a quiet window, but keep retries bounded so maintenance can
      // never become a permanent background task.
      var idle = false;
      for (var attempt = 1; attempt <= 4; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_writeGate.activeLoads == 0 &&
            _writeGate.queuedLoads == 0 &&
            _activeReads == 0) {
          idle = true;
          break;
        }
      }
      if (!idle) {
        _bytesWrittenSinceTrim = _trimWriteBudgetBytes;
        DiagnosticsService.instance
            .record('artwork_disk_cache_trim_deferred', <String, Object?>{
              'reason': 'artwork_cache_io_never_idle',
              'activeWrites': _writeGate.activeLoads,
              'queuedWrites': _writeGate.queuedLoads,
              'activeReads': _activeReads,
              'retryCount': 4,
            });
        return;
      }
      await _trim();
    }).whenComplete(() => _trimFuture = null);
  }

  Future<void> _trim() async {
    if (_trimInProgress) return;
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_trim',
      data: <String, Object?>{
        'cacheIndexReady': _cacheIndexReady,
        'indexedFileCount': _cacheIndex.length,
        'indexedBytesBeforeTrim': _knownCacheBytes,
        'activeReads': _activeReads,
        'activeWrites': _writeGate.activeLoads,
      },
    );
    _trimInProgress = true;
    final maintenanceCompleter = Completer<void>();
    _trimCompleter = maintenanceCompleter;
    try {
      if (!_cacheIndexReady) {
        DiagnosticsService.instance.endSpan(span, 'skipped', <String, Object?>{
          'reason': 'cache_index_unavailable',
        });
        return;
      }

      final bytesBeforeTrim = _knownCacheBytes;
      if (bytesBeforeTrim <= _maxBytes) {
        DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
          'indexedFileCountBeforeTrim': _cacheIndex.length,
          'indexedBytesBeforeTrim': bytesBeforeTrim,
          'indexedBytesAfterTrim': bytesBeforeTrim,
          'deletedFiles': 0,
          'deleteFailures': 0,
          'sortDurationUs': 0,
          'deleteDurationUs': 0,
          'trimReason': 'under_size_limit',
        });
        return;
      }

      final sortClock = Stopwatch()..start();
      final entries =
          _cacheIndex.values.toList()
            ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      sortClock.stop();
      final deleteClock = Stopwatch()..start();
      var deletedFiles = 0;
      var deleteFailures = 0;
      for (final entry in entries) {
        if (_knownCacheBytes <= _maxBytes) break;
        try {
          await File(entry.path).delete();
          _cacheIndex.remove(entry.path);
          _knownCacheBytes -= entry.sizeBytes;
          deletedFiles++;
        } catch (_) {
          deleteFailures++;
        }
      }
      deleteClock.stop();
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
        'indexedFileCountBeforeTrim': entries.length,
        'indexedBytesBeforeTrim': bytesBeforeTrim,
        'indexedBytesAfterTrim': _knownCacheBytes,
        'deletedFiles': deletedFiles,
        'deleteFailures': deleteFailures,
        'sortDurationUs': sortClock.elapsedMicroseconds,
        'deleteDurationUs': deleteClock.elapsedMicroseconds,
        'limitExceededBeforeTrim': bytesBeforeTrim > _maxBytes,
        'remainingOverLimitBytes': (_knownCacheBytes - _maxBytes).clamp(
          0,
          _knownCacheBytes,
        ),
        'trimReason':
            _knownCacheBytes > _maxBytes
                ? 'delete_failed_remaining_over_limit'
                : 'size_limit_enforced',
      });
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
    } finally {
      _trimInProgress = false;
      if (identical(_trimCompleter, maintenanceCompleter)) {
        _trimCompleter = null;
      }
      if (!maintenanceCompleter.isCompleted) maintenanceCompleter.complete();
    }
  }
}

class _ArtworkCacheEntry {
  const _ArtworkCacheEntry({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
}
