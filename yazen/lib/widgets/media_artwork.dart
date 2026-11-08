import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:on_audio_query/on_audio_query.dart';
import 'package:provider/provider.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';
import '../services/artwork_content_cropper.dart';
import '../services/artwork_disk_cache.dart';
import '../services/bounded_load_gate.dart';
import '../diagnostics/core/diagnostics_service.dart';

class YazenMediaArtwork extends StatefulWidget {
  const YazenMediaArtwork({
    this.track,
    required this.size,
    this.imageUri,
    this.placeholder,
    this.borderRadius,
    this.circular = false,
    this.cropContentBounds = false,
    super.key,
  });

  final MediaTrack? track;
  final double size;
  final Uri? imageUri;
  final Widget? placeholder;
  final BorderRadius? borderRadius;
  final bool circular;

  /// Expensive edge analysis is opt-in for large, hero-sized artwork only.
  /// Library/list/grid thumbnails keep their original framing and skip the
  /// pixel scan plus PNG re-encode.
  final bool cropContentBounds;

  @override
  State<YazenMediaArtwork> createState() => _YazenMediaArtworkState();
}

class _YazenMediaArtworkState extends State<YazenMediaArtwork> {
  static const MethodChannel _localMediaChannel = MethodChannel(
    'yazen/local_media',
  );
  static const int _maxArtworkPixels = 2048;
  // Small list tiles should not allocate 256px decoded images. The full
  // player still requests its larger target size through the same pipeline.
  static const int _minArtworkPixels = 96;
  static const int _maxCacheBytes = 32 * 1024 * 1024;
  // Large embedded pictures can be returned by the fallback path. Keep those
  // transient instead of letting one full-resolution file evict many covers.
  static const int _maxRawThumbnailCacheBytes = 512 * 1024;
  // A queue eviction is not evidence that a track has no artwork. Give a
  // still-mounted request one bounded chance to re-enter the prioritized gate.
  static const int _maxGateAcquireAttempts = 2;
  static const Duration _gateRetryDelay = Duration(milliseconds: 140);
  // A bounded gate prevents rapid scrolling from building an unlimited
  // backlog of image I/O and decoding for rows that are already off-screen.
  static final BoundedLoadGate _loadGate = BoundedLoadGate(
    // Keep image I/O/decode pressure modest on mid/low-end phones. During a
    // fling, the newest requests are the ones most likely to still be visible.
    maxConcurrent: 2,
    maxQueued: 12,
    preferNewest: true,
  );
  static final LinkedHashMap<String, _CachedArtwork> _memoryCache =
      LinkedHashMap<String, _CachedArtwork>();
  static final Map<String, Future<_CachedArtwork?>> _pendingLoads =
      <String, Future<_CachedArtwork?>>{};
  static int _memoryCacheBytes = 0;
  static int _artworkLoadsStarted = 0;
  static int _artworkLoadsCompleted = 0;
  static int _artworkLoadsSucceeded = 0;
  static int _artworkLoadsReturnedNull = 0;
  static int _artworkLoadsFailed = 0;
  static int _diskCacheHits = 0;
  static int _diskCacheMisses = 0;

  static final OnAudioQuery _audioQuery = OnAudioQuery();
  Future<_CachedArtwork?>? _future = Future<_CachedArtwork?>.value();
  Uint8List? _lastBytes;
  int _lastWidth = 0;
  int _lastHeight = 0;
  String? _cacheKey;
  String? _artworkSourceKey;
  int _requestedPixels = 0;
  int _loadStartedAtUs = 0;
  String? _lastRenderedCacheKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startLoad(_pixelSize(context));
  }

  @override
  void didUpdateWidget(covariant YazenMediaArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startLoad(_pixelSize(context));
  }

  int _pixelSize(BuildContext context) =>
      (widget.size * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(_minArtworkPixels, _maxArtworkPixels)
          .toInt();

  String? _sourceKeyFor(MediaTrack? track, Uri? imageUri) {
    if (track != null) {
      if (track.isLocal) {
        // MediaStore IDs are stable when a file's tags/artwork are edited.
        // Include file metadata so a replaced cover cannot remain stale in
        // memory or on disk under the same artwork cache key.
        final modified = track.modifiedAt?.microsecondsSinceEpoch ?? 0;
        final size = track.sizeBytes ?? 0;
        return 'local-track:${track.id}:$modified:$size';
      }
      final artworkUri = track.artworkUri;
      return artworkUri == null
          ? '${track.source.name}:${track.id}'
          : '${track.source.name}:$artworkUri';
    }
    return imageUri == null ? null : 'remote:$imageUri';
  }

  String? _keyFor(
    MediaTrack? track,
    Uri? imageUri,
    int pixels,
    bool cropContentBounds,
  ) {
    final base = _sourceKeyFor(track, imageUri);
    if (base == null) return null;
    // Keep output variants separate: Android downsamples local artwork, and
    // hero artwork may be content-cropped while ordinary thumbnails are not.
    final variant = cropContentBounds ? 'crop' : 'raw';
    return '$base:$pixels:$variant';
  }

  _CachedArtwork? _readCache(String key) {
    final bytes = _memoryCache.remove(key);
    if (bytes != null) _memoryCache[key] = bytes;
    return bytes;
  }

  void _writeCache(String key, _CachedArtwork artwork) {
    final previous = _memoryCache.remove(key);
    if (previous != null) _memoryCacheBytes -= previous.bytes.length;
    if (artwork.bytes.length > _maxCacheBytes) return;
    _memoryCache[key] = artwork;
    _memoryCacheBytes += artwork.bytes.length;
    while (_memoryCacheBytes > _maxCacheBytes) {
      final oldestKey = _memoryCache.keys.first;
      final oldest = _memoryCache.remove(oldestKey);
      if (oldest != null) _memoryCacheBytes -= oldest.bytes.length;
    }
  }

  static Map<String, Object?> _diagnosticsSnapshot() => <String, Object?>{
    'memoryCacheBytes': _memoryCacheBytes,
    'memoryCacheEntries': _memoryCache.length,
    'pendingLoads': _pendingLoads.length,
    'activeLoads': _loadGate.activeLoads,
    'queuedLoads': _loadGate.queuedLoads,
    'rejectedLoads': _loadGate.rejectedLoads,
    'queueEvictions': _loadGate.queueEvictions,
    'queueFullRejections': _loadGate.queueFullRejections,
    'loadsStarted': _artworkLoadsStarted,
    'loadsCompleted': _artworkLoadsCompleted,
    'loadsSucceeded': _artworkLoadsSucceeded,
    'loadsReturnedNull': _artworkLoadsReturnedNull,
    'loadsFailed': _artworkLoadsReturnedNull + _artworkLoadsFailed,
    'loadsExceptionFailed': _artworkLoadsFailed,
    'diskCacheHits': _diskCacheHits,
    'diskCacheMisses': _diskCacheMisses,
  };

  void _startLoad(int pixels) {
    final key = _keyFor(
      widget.track,
      widget.imageUri,
      pixels,
      widget.cropContentBounds,
    );
    if (key == _cacheKey && pixels == _requestedPixels) return;
    final sourceKey = _sourceKeyFor(widget.track, widget.imageUri);
    if (sourceKey != _artworkSourceKey) {
      _lastBytes = null;
      _lastWidth = 0;
      _lastHeight = 0;
    }
    _artworkSourceKey = sourceKey;
    _cacheKey = key;
    _loadStartedAtUs = DiagnosticsService.instance.elapsedMicroseconds;
    _requestedPixels = pixels;
    final cached = key == null ? null : _readCache(key);
    // Keep the previous frame visible until replacement art is ready; cached
    // low-resolution art is still replaced by its high-resolution variant.
    if (key != null && cached != null && cached.bytes.isNotEmpty) {
      DiagnosticsService.instance.record(
        'artwork_memory_cache_hit',
        <String, Object?>{
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'pixels': pixels,
          ..._diagnosticsSnapshot(),
        },
      );
      _lastBytes = cached.bytes;
      _lastWidth = cached.width;
      _lastHeight = cached.height;
    }
    _future =
        cached == null
            ? _load(
              widget.track,
              widget.imageUri,
              key,
              pixels,
              widget.cropContentBounds,
            )
            : Future<_CachedArtwork?>.value(cached);
  }

  Future<_CachedArtwork?> _load(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
    bool cropContentBounds,
  ) async {
    if (track == null && imageUri == null) {
      DiagnosticsService.instance.record(
        'artwork_request_skipped',
        <String, Object?>{'reason': 'missing_track_and_image_uri'},
      );
      return null;
    }
    if (key != null) {
      final cached = _readCache(key);
      if (cached != null) {
        DiagnosticsService.instance
            .record('artwork_memory_cache_hit', <String, Object?>{
              'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(
                key,
              ),
              'pixels': pixels,
              ..._diagnosticsSnapshot(),
            });
        return cached;
      }
      final pending = _pendingLoads[key];
      if (pending != null) {
        DiagnosticsService.instance
            .record('artwork_request_deduplicated', <String, Object?>{
              'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(
                key,
              ),
              'pixels': pixels,
              ..._diagnosticsSnapshot(),
            });
        return pending;
      }
      DiagnosticsService.instance.record(
        'artwork_memory_cache_miss',
        <String, Object?>{
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'pixels': pixels,
          ..._diagnosticsSnapshot(),
        },
      );
      final load = _loadWithDiskCache(
        track,
        imageUri,
        key,
        pixels,
        cropContentBounds,
      );
      _pendingLoads[key] = load;
      try {
        return await load;
      } finally {
        if (identical(_pendingLoads[key], load)) _pendingLoads.remove(key);
      }
    }
    return _loadUncached(track, imageUri, key, pixels, cropContentBounds);
  }

  Future<bool> _acquireArtworkPermit() async {
    final gateSpan = DiagnosticsService.instance.startSpan(
      'artwork_gate_wait',
      data: _diagnosticsSnapshot(),
    );
    var lastRejectionReason = 'unknown';
    for (var attempt = 1; attempt <= _maxGateAcquireAttempts; attempt++) {
      final result = await _loadGate.acquireWithResult();
      if (result == LoadPermitResult.acquired) {
        DiagnosticsService.instance.endSpan(
          gateSpan,
          'complete',
          <String, Object?>{'attempt': attempt, ..._diagnosticsSnapshot()},
        );
        return true;
      }
      lastRejectionReason =
          result == LoadPermitResult.queueEvicted
              ? 'queue_evicted_by_newer_request'
              : 'queue_capacity_unavailable';
      if (result == LoadPermitResult.queueFull ||
          attempt == _maxGateAcquireAttempts) {
        break;
      }
      // Keep the retry bounded: no timer loop and no unbounded queue growth.
      await Future<void>.delayed(_gateRetryDelay);
    }
    DiagnosticsService.instance.endSpan(gateSpan, 'rejected', <String, Object?>{
      'reason': lastRejectionReason,
      'attemptLimit': _maxGateAcquireAttempts,
      ..._diagnosticsSnapshot(),
    });
    if (kDebugMode || kProfileMode) {
      developer.log(
        'Artwork request dropped after bounded gate retry '
        '(rejected=${_loadGate.rejectedLoads}, '
        'active=${_loadGate.activeLoads}, queued=${_loadGate.queuedLoads})',
        name: 'yazen.artwork',
      );
    }
    return false;
  }

  Future<_CachedArtwork?> _loadWithDiskCache(
    MediaTrack? track,
    Uri? imageUri,
    String key,
    int pixels,
    bool cropContentBounds,
  ) async {
    // Acquire before touching disk so a fast fling cannot create an unlimited
    // number of concurrent file reads while the decode queue is saturated.
    final acquired = await _acquireArtworkPermit();
    if (!acquired) return null;
    try {
      final diskSpan = DiagnosticsService.instance.startSpan(
        'artwork_disk_cache_read',
        data: <String, Object?>{
          'pixels': pixels,
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
        },
      );
      dynamic disk;
      try {
        disk = await ArtworkDiskCache.instance.read(key);
      } catch (error) {
        DiagnosticsService.instance.endSpan(
          diskSpan,
          'failed',
          <String, Object?>{'errorType': error.runtimeType.toString()},
        );
        rethrow;
      }
      DiagnosticsService.instance.endSpan(
        diskSpan,
        'complete',
        <String, Object?>{
          'hit': disk != null && disk.bytes.isNotEmpty,
          'bytes': disk?.bytes.length,
        },
      );
      if (disk != null && disk.bytes.isNotEmpty) {
        _diskCacheHits++;
        DiagnosticsService.instance.record(
          'artwork_disk_cache_hit',
          <String, Object?>{'pixels': pixels, ..._diagnosticsSnapshot()},
        );
        final artwork = _CachedArtwork(disk.bytes, disk.width, disk.height);
        _writeCache(key, artwork);
        return artwork;
      }
      _diskCacheMisses++;
      DiagnosticsService.instance.record(
        'artwork_disk_cache_miss',
        <String, Object?>{'pixels': pixels, ..._diagnosticsSnapshot()},
      );
      return await _loadArtwork(
        track,
        imageUri,
        key,
        pixels,
        cropContentBounds,
      );
    } finally {
      _loadGate.release();
    }
  }

  Future<_CachedArtwork?> _loadUncached(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
    bool cropContentBounds,
  ) async {
    final acquired = await _acquireArtworkPermit();
    if (!acquired) return null; // Still bounded after one prioritized retry.
    try {
      return await _loadArtwork(
        track,
        imageUri,
        key,
        pixels,
        cropContentBounds,
      );
    } finally {
      _loadGate.release();
    }
  }

  Future<_CachedArtwork?> _loadArtwork(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
    bool cropContentBounds,
  ) async {
    // Detailed DevTools TimelineTask tracing stays out of release builds.
    // The lightweight YAZEN span is retained for session-level investigation.
    final traceEnabled = kDebugMode || kProfileMode;
    final task =
        traceEnabled
            ? (developer.TimelineTask()..start(
              'YAZEN.artwork.load',
              arguments: <String, Object?>{
                'pixels': pixels,
                'crop': cropContentBounds,
                'source': track?.isLocal == true ? 'local' : 'remote',
              },
            ))
            : null;
    _artworkLoadsStarted++;
    final loadSpan = DiagnosticsService.instance.startSpan(
      'artwork_load',
      data: <String, Object?>{
        'pixels': pixels,
        'source':
            track?.isLocal == true
                ? 'local'
                : ((track?.artworkUri != null || imageUri != null)
                    ? 'remote'
                    : 'unknown'),
        'cacheKeyFingerprint':
            key == null ? null : DiagnosticsService.diagnosticFingerprint(key),
        ..._diagnosticsSnapshot(),
      },
    );
    try {
      final result = await _loadArtworkInternal(
        track,
        imageUri,
        key,
        pixels,
        cropContentBounds,
      );
      _artworkLoadsCompleted++;
      if (result != null) {
        _artworkLoadsSucceeded++;
      } else {
        _artworkLoadsReturnedNull++;
      }
      DiagnosticsService.instance
          .endSpan(loadSpan, 'complete', <String, Object?>{
            'success': result != null,
            'resultKind':
                result == null
                    ? 'no_artwork_or_source_unavailable'
                    : 'artwork_ready',
            ..._diagnosticsSnapshot(),
          });
      return result;
    } catch (error) {
      _artworkLoadsFailed++;
      DiagnosticsService.instance.endSpan(loadSpan, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
        ..._diagnosticsSnapshot(),
      });
      rethrow;
    } finally {
      if ((kDebugMode || kProfileMode) &&
          (_artworkLoadsCompleted + _artworkLoadsFailed) % 32 == 0) {
        developer.log(
          'Artwork metrics: started=$_artworkLoadsStarted, '
          'completed=$_artworkLoadsCompleted, succeeded=$_artworkLoadsSucceeded, '
          'null=$_artworkLoadsReturnedNull, exceptionFailed=$_artworkLoadsFailed, '
          'diskHit=$_diskCacheHits, diskMiss=$_diskCacheMisses, '
          'gateRejected=${_loadGate.rejectedLoads}',
          name: 'yazen.artwork.metrics',
        );
      }
      task?.finish();
    }
  }

  Future<_CachedArtwork?> _loadArtworkInternal(
    MediaTrack? track,
    Uri? imageUri,
    String? key,
    int pixels,
    bool cropContentBounds,
  ) async {
    Uint8List? bytes;
    final sourceAttempts = <Map<String, Object?>>[];
    String? failureReason;
    int? httpStatusCode;
    final sourceKind =
        track?.isLocal == true
            ? 'local'
            : (track?.artworkUri != null || imageUri != null
                ? 'remote'
                : 'unknown');
    final sourceSpan = DiagnosticsService.instance.startSpan(
      'artwork_source_fetch',
      data: <String, Object?>{
        'source': sourceKind,
        'pixels': pixels,
        'cacheKeyFingerprint':
            key == null ? null : DiagnosticsService.diagnosticFingerprint(key),
      },
    );
    try {
      final localTrack = track;
      if (localTrack != null && localTrack.isLocal) {
        final id = int.tryParse(localTrack.id);
        if (id != null) {
          bytes = await _audioQuery.queryArtwork(
            id,
            ArtworkType.AUDIO,
            format: ArtworkFormat.JPEG,
            size: pixels,
            quality: 86,
          );
          sourceAttempts.add(<String, Object?>{
            'source': 'media_store_artwork',
            'success': bytes != null && bytes.isNotEmpty,
            'encodedBytes': bytes?.length,
          });
          if (bytes == null || bytes.isEmpty) {
            failureReason = 'media_store_artwork_not_found';
          }
        } else {
          failureReason = 'invalid_media_store_id';
        }
        if ((bytes == null || bytes.isEmpty) && !localTrack.isVideo) {
          bytes = await _readOriginalArtwork(localTrack.uri, pixels);
          sourceAttempts.add(<String, Object?>{
            'source': 'embedded_artwork_fallback',
            'success': bytes != null && bytes.isNotEmpty,
            'encodedBytes': bytes?.length,
          });
          if (bytes == null || bytes.isEmpty) {
            failureReason = 'embedded_artwork_unavailable';
          } else {
            failureReason = null;
          }
        } else if ((bytes == null || bytes.isEmpty) && localTrack.isVideo) {
          failureReason = 'video_artwork_unavailable';
        }
      } else {
        final uri = track?.artworkUri ?? imageUri;
        if (uri == null) {
          failureReason = 'missing_artwork_uri';
        } else {
          try {
            final response = await http
                .get(uri)
                .timeout(const Duration(seconds: 5));
            httpStatusCode = response.statusCode;
            sourceAttempts.add(<String, Object?>{
              'source': 'http_artwork',
              'statusCode': response.statusCode,
              'success':
                  response.statusCode == 200 && response.bodyBytes.isNotEmpty,
              'encodedBytes': response.bodyBytes.length,
            });
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              bytes = response.bodyBytes;
              failureReason = null;
            } else if (response.statusCode != 200) {
              failureReason = 'http_status_${response.statusCode}';
            } else {
              failureReason = 'empty_http_body';
            }
          } catch (error, stackTrace) {
            failureReason =
                error is TimeoutException
                    ? 'network_timeout'
                    : 'network_request_failed';
            developer.log(
              'Remote artwork request failed',
              name: 'yazen.artwork',
              error: error,
              stackTrace: stackTrace,
            );
          }
        }
      }
    } catch (error) {
      DiagnosticsService.instance
          .endSpan(sourceSpan, 'failed', <String, Object?>{
            'errorType': error.runtimeType.toString(),
            'failureReason': 'source_exception',
          });
      rethrow;
    }
    DiagnosticsService.instance
        .endSpan(sourceSpan, 'complete', <String, Object?>{
          'success': bytes != null && bytes.isNotEmpty,
          'failureReason':
              bytes != null && bytes.isNotEmpty
                  ? null
                  : (failureReason ?? 'empty_artwork_result'),
          'sourceAttempts': sourceAttempts,
          'httpStatusCode': httpStatusCode,
          'encodedBytes': bytes?.length,
        });
    if (bytes == null || bytes.isEmpty) return null;

    final sourceKey = _sourceKeyFor(track, imageUri);
    if (sourceKey == null) {
      DiagnosticsService.instance.record(
        'artwork_processing_skipped',
        <String, Object?>{
          'reason': 'missing_source_cache_key',
          'pixels': pixels,
        },
      );
      return null;
    }
    ProcessedArtwork processed;
    if (!cropContentBounds) {
      // Thumbnails are already requested at display resolution. Reading the
      // encoded dimensions is enough for Image.memory's decode cache; scanning
      // all pixels and writing a second PNG gives no useful benefit here.
      final size = await _imageSize(bytes);
      processed = ProcessedArtwork(
        bytes: bytes,
        width: size.$1,
        height: size.$2,
      );
    } else {
      final cropSpan = DiagnosticsService.instance.startSpan(
        'artwork_content_crop',
        data: <String, Object?>{
          'encodedBytes': bytes.length,
          'targetPixels': pixels,
        },
      );
      try {
        processed = await ArtworkContentCropper.process(
          bytes,
          cacheKey: sourceKey,
          targetPixels: pixels,
        );
        DiagnosticsService.instance
            .endSpan(cropSpan, 'complete', <String, Object?>{
              'outputBytes': processed.bytes.length,
              'width': processed.width,
              'height': processed.height,
            });
      } catch (error, stackTrace) {
        DiagnosticsService.instance.endSpan(
          cropSpan,
          'failed',
          <String, Object?>{'errorType': error.runtimeType.toString()},
        );
        debugPrint(
          'Unable to inspect artwork content; using original image: '
          '$error\n$stackTrace',
        );
        final size = await _imageSize(bytes);
        processed = ProcessedArtwork(
          bytes: bytes,
          width: size.$1,
          height: size.$2,
        );
      }
    }
    final artwork = _CachedArtwork(
      processed.bytes,
      processed.width,
      processed.height,
    );
    if (key != null &&
        (cropContentBounds ||
            artwork.bytes.length <= _maxRawThumbnailCacheBytes)) {
      _writeCache(key, artwork);
      unawaited(_writeArtworkDiskCache(key, artwork));
    }
    return artwork;
  }

  Future<void> _writeArtworkDiskCache(
    String key,
    _CachedArtwork artwork,
  ) async {
    final span = DiagnosticsService.instance.startSpan(
      'artwork_disk_cache_write',
      data: <String, Object?>{
        'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
        'bytes': artwork.bytes.length,
      },
    );
    try {
      final result = await ArtworkDiskCache.instance.write(
        key,
        artwork.bytes,
        width: artwork.width,
        height: artwork.height,
      );
      final outcome = switch (result) {
        ArtworkDiskWriteResult.written => 'complete',
        ArtworkDiskWriteResult.rejectedByGate => 'rejected',
        ArtworkDiskWriteResult.skippedInvalidPayload => 'skipped',
        ArtworkDiskWriteResult.failed => 'failed',
      };
      DiagnosticsService.instance.endSpan(span, outcome, <String, Object?>{
        'result': result.name,
        'written': result == ArtworkDiskWriteResult.written,
      });
    } catch (error) {
      DiagnosticsService.instance.endSpan(span, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  Future<(int, int)> _imageSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final decodeSpan = DiagnosticsService.instance.startSpan(
      'artwork_image_descriptor_decode',
      data: <String, Object?>{'encodedBytes': bytes.length},
    );
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final dimensions = (descriptor.width, descriptor.height);
        DiagnosticsService.instance.endSpan(
          decodeSpan,
          'complete',
          <String, Object?>{'width': dimensions.$1, 'height': dimensions.$2},
        );
        return dimensions;
      } finally {
        descriptor.dispose();
      }
    } catch (error) {
      DiagnosticsService.instance.endSpan(
        decodeSpan,
        'failed',
        <String, Object?>{'errorType': error.runtimeType.toString()},
      );
      rethrow;
    } finally {
      buffer.dispose();
    }
  }

  Future<Uint8List?> _readOriginalArtwork(Uri? sourceUri, int pixels) async {
    if (sourceUri == null) return null;
    try {
      final bytes = await _localMediaChannel.invokeMethod<Uint8List>(
        'readOriginalArtwork',
        <String, Object?>{'uri': sourceUri.toString(), 'size': pixels},
      );
      if (bytes != null && bytes.isNotEmpty && bytes.length <= _maxCacheBytes) {
        return bytes;
      }
    } on MissingPluginException {
      // Non-Android platforms use the fallback source below.
    } on PlatformException {
      // Missing file permission or embedded art falls back to MediaStore.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    final radius =
        widget.circular
            ? BorderRadius.circular(widget.size / 2)
            : widget.borderRadius ?? BorderRadius.circular(widget.size * 0.18);
    return ClipRRect(
      borderRadius: radius,
      child: FutureBuilder<_CachedArtwork?>(
        key: ValueKey<String?>(_cacheKey),
        future: _future,
        builder: (context, snapshot) {
          final loaded = snapshot.data;
          if (loaded != null && loaded.bytes.isNotEmpty) {
            _lastBytes = loaded.bytes;
            _lastWidth = loaded.width;
            _lastHeight = loaded.height;
          }
          final bytes = loaded?.bytes ?? _lastBytes;
          if (bytes != null && bytes.isNotEmpty) {
            final width = loaded?.width ?? _lastWidth;
            final height = loaded?.height ?? _lastHeight;
            final scale =
                widget.size *
                MediaQuery.devicePixelRatioOf(context) /
                math.max(width, height);
            return Image.memory(
              bytes,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: math.max(1, (width * scale).round()),
              cacheHeight: math.max(1, (height * scale).round()),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null && _lastRenderedCacheKey != _cacheKey) {
                  _lastRenderedCacheKey = _cacheKey;
                  DiagnosticsService.instance
                      .record('artwork_first_frame_visible', <String, Object?>{
                        'cacheKeyFingerprint':
                            _cacheKey == null
                                ? null
                                : DiagnosticsService.diagnosticFingerprint(
                                  _cacheKey!,
                                ),
                        'timeToFirstVisibleFrameUs':
                            DiagnosticsService.instance.elapsedMicroseconds -
                            _loadStartedAtUs,
                        'wasSynchronouslyLoaded': wasSynchronouslyLoaded,
                        'frameNumber': frame,
                        'width': width,
                        'height': height,
                      });
                }
                return child;
              },
            );
          }
          return widget.placeholder ??
              Container(
                width: widget.size,
                height: widget.size,
                color: tokens.surfaceElevated,
                alignment: Alignment.center,
                child: Icon(
                  Icons.music_note_rounded,
                  color: tokens.accent,
                  size: widget.size * 0.34,
                ),
              );
        },
      ),
    );
  }
}

class _CachedArtwork {
  const _CachedArtwork(this.bytes, this.width, this.height);

  final Uint8List bytes;
  final int width;
  final int height;
}
