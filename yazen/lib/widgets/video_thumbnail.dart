import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../core/theme/theme_provider.dart';
import '../models/media_track.dart';
import '../services/bounded_load_gate.dart';

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
    _requestKey = key;
    _requestedWidth = width;
    if (sourceChanged) _lastThumbnail = null;
    if (key == null) {
      _future = Future<Uint8List?>.value();
      _lastThumbnail = null;
      return;
    }
    final cached = _readCache(key);
    if (cached != null) {
      _lastThumbnail = cached;
      _future = Future<Uint8List?>.value(cached);
      return;
    }
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
      if (oldest != null) _cacheBytes -= oldest.length;
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
    if (existing != null) return existing;
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
    final acquired = await _loadGate.acquire();
    if (!acquired) return null;
    try {
      final uri = track.uri;
      if (uri == null) return null;
      Uint8List? bytes;
      if (uri.scheme == 'content') {
        try {
          bytes = await _channel.invokeMethod<Uint8List>(
            'videoThumbnail',
            <String, Object?>{'uri': uri.toString(), 'width': width},
          );
        } on PlatformException {
          return null;
        } on MissingPluginException {
          return null;
        }
      } else {
        try {
          bytes = await VideoThumbnail.thumbnailData(
            video: uri.scheme == 'file' ? uri.toFilePath() : uri.toString(),
            imageFormat: ImageFormat.JPEG,
            maxWidth: width,
            quality: 84,
          );
        } catch (_) {
          return null;
        }
      }
      if (bytes != null && bytes.isNotEmpty) _writeCache(key, bytes);
      return bytes;
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
