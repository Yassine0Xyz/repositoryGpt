import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/core/diagnostics_service.dart';
import 'bounded_load_gate.dart';

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
/// The cache is deliberately independent from widget lifetime: scrolling away
/// from a row does not throw away work that will be needed again later.
class ArtworkDiskCache {
  ArtworkDiskCache._();

  static final ArtworkDiskCache instance = ArtworkDiskCache._();
  static const _maxBytes = 64 * 1024 * 1024;
  static Future<Directory>? _directoryFuture;
  // Disk writes are deliberately serialized and bounded. A fast fling should
  // not spawn an arbitrary number of independent cache-file writes.
  static final BoundedLoadGate _writeGate = BoundedLoadGate(
    maxConcurrent: 1,
    maxQueued: 24,
  );
  Future<void>? _trimFuture;
  int _writesSinceTrim = 0;

  Future<Directory> _directory() =>
      _directoryFuture ??= getApplicationSupportDirectory().then((root) async {
        final directory = Directory('${root.path}/artwork-thumbnails-v2');
        await directory.create(recursive: true);
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
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_read_io',
      data: <String, Object?>{'cacheKey': key},
    );
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
      // Do not touch the file timestamp on every cache hit. That turns a
      // read-only artwork lookup into filesystem metadata writes during fast
      // scrolling. Eviction uses the last successful write time instead.
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
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<bool> write(
    String key,
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final gateSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_write_gate_wait',
      data: <String, Object?>{
        'activeWrites': _writeGate.activeLoads,
        'queuedWrites': _writeGate.queuedLoads,
        'rejectedWrites': _writeGate.rejectedLoads,
        'maxConcurrent': _writeGate.maxConcurrent,
        'maxQueued': _writeGate.maxQueued,
      },
    );
    final acquired = await _writeGate.acquire();
    if (!acquired) {
      DiagnosticsService.instance
          .endSpan(gateSpan, 'rejected', <String, Object?>{
            'activeWrites': _writeGate.activeLoads,
            'queuedWrites': _writeGate.queuedLoads,
            'rejectedWrites': _writeGate.rejectedLoads,
          });
      return false;
    }
    DiagnosticsService.instance.endSpan(gateSpan, 'complete', <String, Object?>{
      'activeWrites': _writeGate.activeLoads,
      'queuedWrites': _writeGate.queuedLoads,
      'rejectedWrites': _writeGate.rejectedLoads,
    });

    final ioSpan = DiagnosticsService.instance.startSpan(
      'artwork_disk_write_io',
      data: <String, Object?>{
        'cacheKey': key,
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
        return false;
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
      // Publish cache entries atomically. A process interruption during a
      // direct write must not leave a truncated file that looks like a hit.
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsBytes(data, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      }
      _writesSinceTrim++;
      if (_writesSinceTrim >= 64 && _trimFuture == null) {
        _writesSinceTrim = 0;
        _trimFuture = _trim(directory).whenComplete(() => _trimFuture = null);
      }
      DiagnosticsService.instance.endSpan(ioSpan, 'complete', <String, Object?>{
        'writtenBytes': data.length,
      });
      return true;
    } catch (error) {
      DiagnosticsService.instance.endSpan(ioSpan, 'failed', <String, Object?>{
        'error': error.toString(),
      });
      return false;
    } finally {
      _writeGate.release();
    }
  }

  Future<void> _trim(Directory directory) async {
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_trim',
    );
    try {
      final files =
          await directory
              .list()
              .where((entity) => entity is File && entity.path.endsWith('.art'))
              .cast<File>()
              .toList();
      var total = 0;
      final entries = <(File, int, DateTime)>[];
      for (final file in files) {
        try {
          final stat = await file.stat();
          total += stat.size;
          entries.add((file, stat.size, stat.modified));
        } catch (_) {}
      }
      if (total <= _maxBytes) {
        DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
          'fileCount': files.length,
          'totalBytes': total,
          'deletedFiles': 0,
        });
        return;
      }
      entries.sort((a, b) => a.$3.compareTo(b.$3));
      var deletedFiles = 0;
      for (final entry in entries) {
        if (total <= _maxBytes) break;
        try {
          await entry.$1.delete();
          total -= entry.$2;
          deletedFiles++;
        } catch (_) {}
      }
      DiagnosticsService.instance.endSpan(span, 'complete', <String, Object?>{
        'fileCount': files.length,
        'totalBytesAfterTrim': total,
        'deletedFiles': deletedFiles,
      });
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{
        'error': error.toString(),
      });
    }
  }
}
