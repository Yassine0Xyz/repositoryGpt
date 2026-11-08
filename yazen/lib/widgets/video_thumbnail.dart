import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';
import '../services/bounded_load_gate.dart';
import '../diagnostics/core/diagnostics_service.dart';

/// Viewport-aware thumbnail loader.
///
/// A fast fling must not enqueue a thumbnail decode for every video in the
/// library. Requests are deduplicated, bounded, newest-first and cached in a
/// small byte-budgeted LRU so returning to recently seen cards is inexpensive.
class VideoThumbnailWidget extends StatefulWidget {
  const VideoThumbnailWidget({
    required this.track,
    required this.size,
    super.key,
  });

  final MediaTrack track;
  final double size;

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  static const MethodChannel _channel = MethodChannel('yazen/local_media');
  static const int _maxCacheBytes = 24 * 1024 * 1024;
  static const int _maxCacheEntries = 64;
  static final BoundedLoadGate _loadGate = BoundedLoadGate(
    maxConcurrent: 2,
    maxQueued: 8,
    preferNewest: true,
  );
  static final LinkedHashMap<String, Uint8List> _cache =
      LinkedHashMap<String, Uint8List>();
  static final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};
  static int _cacheBytes = 0;
  static int _cacheEvictions = 0;
  int _loadStartedAtUs = 0;
  String? _lastVisibleCacheKey;
  bool _requestWasMemoryCacheHit = false;

  Future<Uint8List?>? _future;
  Uint8List? _lastThumbnail;
  String? _requestKey;
  int _requestedWidth = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startLoad(_pixelWidth(context));
  }

  @override
  void didUpdateWidget(covariant VideoThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startLoad(_pixelWidth(context));
  }

  int _pixelWidth(BuildContext context) =>
      (widget.size * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(160, 1200)
          .toInt();

  void _startLoad(int width) {
    final uri = widget.track.uri;
    final key =
        uri == null
            ? null
            : '${uri.toString()}:$width:'
                '${widget.track.modifiedAt?.microsecondsSinceEpoch ?? 0}:'
                '${widget.track.sizeBytes ?? 0}';
    if (key == _requestKey && width == _requestedWidth) return;
    final sourceChanged = _requestKey != null && _requestKey != key;
    if (_requestKey != key) _lastVisibleCacheKey = null;
    _requestKey = key;
    _requestedWidth = width;
    _loadStartedAtUs = DiagnosticsService.instance.elapsedMicroseconds;
    _requestWasMemoryCacheHit = false;
    if (sourceChanged) _lastThumbnail = null;
    if (key == null) {
      DiagnosticsService.instance.record(
        'video_thumbnail_request_skipped',
        <String, Object?>{'reason': 'missing_content_uri'},
      );
      _future = Future<Uint8List?>.value();
      _lastThumbnail = null;
      return;
    }
    final cached = _readCache(key);
    if (cached != null) {
      _requestWasMemoryCacheHit = true;
      DiagnosticsService.instance.record(
        'video_thumbnail_cache_hit',
        <String, Object?>{
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'bytes': cached.length,
          'cacheEntries': _cache.length,
          'cacheBytes': _cacheBytes,
          'cacheEvictions': _cacheEvictions,
        },
      );
      _lastThumbnail = cached;
      _future = Future<Uint8List?>.value(cached);
      return;
    }
    DiagnosticsService.instance
        .record('video_thumbnail_cache_miss', <String, Object?>{
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'cacheEntries': _cache.length,
          'cacheBytes': _cacheBytes,
          'cacheEvictions': _cacheEvictions,
        });
    _future = _loadDeduplicated(widget.track, key, width);
  }

  static Uint8List? _readCache(String key) {
    final value = _cache.remove(key);
    if (value != null) _cache[key] = value;
    return value;
  }

  static void _writeCache(String key, Uint8List bytes) {
    final previous = _cache.remove(key);
    if (previous != null) _cacheBytes -= previous.length;
    // A single unusually large frame should remain transient instead of
    // displacing the entire useful thumbnail working set.
    if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) return;
    _cache[key] = bytes;
    _cacheBytes += bytes.length;
    while (_cacheBytes > _maxCacheBytes || _cache.length > _maxCacheEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      if (oldest != null) {
        _cacheBytes -= oldest.length;
        _cacheEvictions++;
        DiagnosticsService.instance
            .record('video_thumbnail_cache_eviction', <String, Object?>{
              'cacheEvictions': _cacheEvictions,
              'cacheEntries': _cache.length,
              'cacheBytes': _cacheBytes,
            });
      }
    }
  }

  static Future<Uint8List?> _loadDeduplicated(
    MediaTrack track,
    String key,
    int width,
  ) async {
    final cached = _readCache(key);
    if (cached != null) return cached;
    final existing = _pending[key];
    if (existing != null) {
      DiagnosticsService.instance.record(
        'video_thumbnail_request_deduplicated',
        <String, Object?>{
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'pendingCount': _pending.length,
        },
      );
      return existing;
    }
    final load = _loadBounded(track, key, width);
    _pending[key] = load;
    try {
      return await load;
    } finally {
      if (identical(_pending[key], load)) _pending.remove(key);
    }
  }

  static Future<Uint8List?> _loadBounded(
    MediaTrack track,
    String key,
    int width,
  ) async {
    final loadSpan = DiagnosticsService.instance.startSpan(
      'video_thumbnail_load',
      data: <String, Object?>{
        'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
        'requestedWidth': width,
        'source': track.uri?.scheme ?? 'unknown',
      },
    );
    final gateSpan = DiagnosticsService.instance.startSpan(
      'video_thumbnail_gate_wait',
      data: <String, Object?>{
        'activeLoads': _loadGate.activeLoads,
        'queuedLoads': _loadGate.queuedLoads,
        'rejectedLoads': _loadGate.rejectedLoads,
        'queueEvictions': _loadGate.queueEvictions,
        'queueFullRejections': _loadGate.queueFullRejections,
        'maxConcurrent': _loadGate.maxConcurrent,
        'maxQueued': _loadGate.maxQueued,
      },
    );
    final permit = await _loadGate.acquireWithResult();
    if (permit != LoadPermitResult.acquired) {
      DiagnosticsService.instance
          .endSpan(gateSpan, 'rejected', <String, Object?>{
            'reason':
                permit == LoadPermitResult.queueEvicted
                    ? 'queue_evicted_by_newer_request'
                    : 'queue_capacity_unavailable',
            'activeLoads': _loadGate.activeLoads,
            'queuedLoads': _loadGate.queuedLoads,
            'rejectedLoads': _loadGate.rejectedLoads,
            'queueEvictions': _loadGate.queueEvictions,
            'queueFullRejections': _loadGate.queueFullRejections,
          });
      DiagnosticsService.instance.endSpan(loadSpan, 'rejected');
      return null;
    }
    DiagnosticsService.instance.endSpan(gateSpan, 'complete', <String, Object?>{
      'activeLoads': _loadGate.activeLoads,
      'queuedLoads': _loadGate.queuedLoads,
      'rejectedLoads': _loadGate.rejectedLoads,
      'queueEvictions': _loadGate.queueEvictions,
      'queueFullRejections': _loadGate.queueFullRejections,
    });

    try {
      final uri = track.uri;
      if (uri == null) {
        DiagnosticsService.instance.endSpan(
          loadSpan,
          'complete',
          <String, Object?>{
            'success': false,
            'failureReason': 'missing_content_uri',
          },
        );
        return null;
      }

      final sourceSpan = DiagnosticsService.instance.startSpan(
        'video_thumbnail_source_fetch',
        data: <String, Object?>{
          'source': uri.scheme,
          'cacheKeyFingerprint': DiagnosticsService.diagnosticFingerprint(key),
          'requestedWidth': width,
        },
      );
      Uint8List? bytes;
      String? failureReason;
      String? platformErrorCode;
      if (uri.scheme == 'content') {
        try {
          bytes = await _channel.invokeMethod<Uint8List>(
            'videoThumbnail',
            <String, Object?>{'uri': uri.toString(), 'width': width},
          );
          if (bytes == null || bytes.isEmpty) {
            failureReason = 'native_thumbnail_empty_result';
          }
        } on PlatformException catch (error) {
          failureReason = 'native_thumbnail_platform_exception';
          platformErrorCode = error.code;
        } on MissingPluginException {
          failureReason = 'native_thumbnail_plugin_missing';
        }
      } else {
        try {
          bytes = await VideoThumbnail.thumbnailData(
            video: uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
            imageFormat: ImageFormat.JPEG,
            maxWidth: width,
            quality: 84,
          );
          if (bytes == null || bytes.isEmpty) {
            failureReason = 'thumbnail_plugin_empty_result';
          }
        } catch (error) {
          failureReason = 'thumbnail_plugin_exception';
          DiagnosticsService.instance.record(
            'video_thumbnail_source_exception',
            <String, Object?>{'errorType': error.runtimeType.toString()},
          );
        }
      }

      DiagnosticsService.instance
          .endSpan(sourceSpan, 'complete', <String, Object?>{
            'success': bytes != null && bytes.isNotEmpty,
            'failureReason':
                bytes != null && bytes.isNotEmpty
                    ? null
                    : (failureReason ?? 'empty_thumbnail_result'),
            'platformErrorCode': platformErrorCode,
            'bytes': bytes?.length,
          });
      if (bytes != null && bytes.isNotEmpty) _writeCache(key, bytes);
      DiagnosticsService.instance
          .endSpan(loadSpan, 'complete', <String, Object?>{
            'success': bytes != null && bytes.isNotEmpty,
            'failureReason':
                bytes != null && bytes.isNotEmpty
                    ? null
                    : (failureReason ?? 'empty_thumbnail_result'),
            'bytes': bytes?.length,
            'cacheEntries': _cache.length,
            'cacheBytes': _cacheBytes,
            'cacheEvictions': _cacheEvictions,
          });
      return bytes;
    } catch (error) {
      DiagnosticsService.instance.endSpan(loadSpan, 'failed', <String, Object?>{
        'errorType': error.runtimeType.toString(),
      });
      rethrow;
    } finally {
      _loadGate.release();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.read<ThemeProvider>().tokens;
    return FutureBuilder<Uint8List?>(
      // Reset FutureBuilder's previous snapshot when a recycled viewport
      // element starts showing a different video. Otherwise stale bytes from
      // the previous future can flash over the new card during loading.
      key: ValueKey<String?>(_requestKey),
      future: _future,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded != null && loaded.isNotEmpty) _lastThumbnail = loaded;
        final visible = loaded ?? _lastThumbnail;
        if (visible != null && visible.isNotEmpty) {
          return RepaintBoundary(
            child: Image.memory(
              visible,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              cacheWidth: _requestedWidth,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (frame != null && _lastVisibleCacheKey != _requestKey) {
                  _lastVisibleCacheKey = _requestKey;
                  DiagnosticsService.instance.record(
                    'video_thumbnail_first_frame_visible',
                    <String, Object?>{
                      'cacheKeyFingerprint':
                          _requestKey == null
                              ? null
                              : DiagnosticsService.diagnosticFingerprint(
                                _requestKey!,
                              ),
                      'timeToFirstVisibleFrameUs':
                          _loadStartedAtUs == 0
                              ? null
                              : DiagnosticsService
                                      .instance
                                      .elapsedMicroseconds -
                                  _loadStartedAtUs,
                      'origin':
                          _requestWasMemoryCacheHit
                              ? 'memory_cache'
                              : 'request_or_deduplicated_load',
                      'wasSynchronouslyLoaded': wasSynchronouslyLoaded,
                    },
                  );
                }
                return child;
              },
            ),
          );
        }
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[tokens.surfaceElevated, tokens.accentStrong],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.movie_creation_rounded,
            color: Colors.white.withValues(alpha: 0.9),
            size: widget.size * 0.3,
          ),
        );
      },
    );
  }
}
