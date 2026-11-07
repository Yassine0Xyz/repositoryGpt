import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

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
    try {
      final file = File('${(await _directory()).path}/${_fileName(key)}.art');
      if (!await file.exists()) return null;
      final data = await file.readAsBytes();
      if (data.length < 8) return null;
      final header = ByteData.sublistView(data, 0, 8);
      final width = header.getUint32(0);
      final height = header.getUint32(4);
      if (width == 0 || height == 0 || data.length == 8) return null;
      // Do not touch the file timestamp on every cache hit. That turns a
      // read-only artwork lookup into filesystem metadata writes during fast
      // scrolling. Eviction uses the last successful write time instead.
      return DiskArtwork(
        bytes: Uint8List.sublistView(data, 8),
        width: width,
        height: height,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    String key,
    Uint8List bytes, {
    required int width,
    required int height,
  }) async {
    final acquired = await _writeGate.acquire();
    if (!acquired) return;
    try {
      if (bytes.isEmpty ||
          bytes.length > _maxBytes ~/ 2 ||
          width <= 0 ||
          height <= 0) {
        return;
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
    } catch (_) {
      // Disk cache is an optimization; media playback must never depend on it.
    } finally {
      _writeGate.release();
    }
  }

  Future<void> _trim(Directory directory) async {
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
    if (total <= _maxBytes) return;
    entries.sort((a, b) => a.$3.compareTo(b.$3));
    for (final entry in entries) {
      if (total <= _maxBytes) break;
      try {
        await entry.$1.delete();
        total -= entry.$2;
      } catch (_) {}
    }
  }
}
