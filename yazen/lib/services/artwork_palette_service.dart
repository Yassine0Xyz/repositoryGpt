import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_track.dart';

@immutable
class ArtworkPalette {
  const ArtworkPalette({
    required this.dominant,
    required this.vibrant,
    required this.lightVibrant,
    required this.darkVibrant,
    required this.muted,
    required this.ambientColor,
    required this.safeAccent,
  });

  factory ArtworkPalette.fallback(Color accent, Color surface) {
    return ArtworkPalette(
      dominant: accent,
      vibrant: accent,
      lightVibrant: accent,
      darkVibrant: accent,
      muted: accent,
      ambientColor: _enhanceAmbientColor(accent),
      safeAccent: _ensureContrast(accent, surface),
    );
  }

  final Color dominant;
  final Color vibrant;
  final Color lightVibrant;
  final Color darkVibrant;
  final Color muted;
  final Color ambientColor;
  final Color safeAccent;

  List<Color> get ambientColors => <Color>[
    dominant,
    vibrant,
    lightVibrant,
    darkVibrant,
    muted,
  ];
}

typedef ArtworkPixelLoader = Future<List<int>?> Function(Uri? artworkUri);

class ArtworkPaletteService {
  ArtworkPaletteService({
    ArtworkPixelLoader? pixelLoader,
    this.cacheCapacity = 32,
  }) : _pixelLoader = pixelLoader ?? _readArtworkPixels {
    if (cacheCapacity < 1) {
      throw ArgumentError.value(cacheCapacity, 'cacheCapacity', 'Must be >= 1');
    }
  }

  static final ArtworkPaletteService instance = ArtworkPaletteService();
  static const MethodChannel _channel = MethodChannel('yazen/local_media');

  final int cacheCapacity;
  final ArtworkPixelLoader _pixelLoader;
  final LinkedHashMap<String, _CachedPalette> _cache =
      LinkedHashMap<String, _CachedPalette>();
  final ValueNotifier<ArtworkPalette> _current = ValueNotifier<ArtworkPalette>(
    ArtworkPalette.fallback(Colors.deepPurpleAccent, Colors.black),
  );
  int _requestGeneration = 0;

  ValueListenable<ArtworkPalette> get current => _current;
  @visibleForTesting
  int get cacheLength => _cache.length;

  Future<void> setCurrentTrack(
    MediaTrack? track, {
    required Color themeAccent,
    required Color surface,
  }) async {
    final generation = ++_requestGeneration;
    final fallback = ArtworkPalette.fallback(themeAccent, surface);
    _current.value = fallback;
    if (track == null) return;
    final palette = await paletteForTrack(
      track,
      themeAccent: themeAccent,
      surface: surface,
    );
    if (generation == _requestGeneration) _current.value = palette;
  }

  Future<ArtworkPalette> paletteForTrack(
    MediaTrack track, {
    required Color themeAccent,
    required Color surface,
  }) async {
    final cacheKey = _cacheKey(track);
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return _withSafeAccent(cached.palette, surface);
    }
    try {
      final pixels = await _pixelLoader(track.artworkUri);
      if (pixels == null || pixels.length < 16) {
        return ArtworkPalette.fallback(themeAccent, surface);
      }
      final colors = await compute<List<int>, List<int>>(
        _extractPalette,
        pixels,
        debugLabel: 'artwork-palette',
      );
      if (colors.length < 7) {
        return ArtworkPalette.fallback(themeAccent, surface);
      }
      final palette = _withSafeAccent(
        ArtworkPalette(
          dominant: Color(colors[0]),
          vibrant: Color(colors[1]),
          lightVibrant: Color(colors[2]),
          darkVibrant: Color(colors[3]),
          muted: Color(colors[4]),
          ambientColor:
              colors[6] == 0
                  ? _enhanceAmbientColor(themeAccent)
                  : Color(colors[6]),
          safeAccent: Color(colors[1]),
        ),
        surface,
      );
      _cache[cacheKey] = _CachedPalette(palette);
      while (_cache.length > cacheCapacity) {
        _cache.remove(_cache.keys.first);
      }
      return palette;
    } catch (_) {
      return ArtworkPalette.fallback(themeAccent, surface);
    }
  }

  String _cacheKey(MediaTrack track) =>
      '${track.id}|${track.source.name}|${track.kind.name}|'
      '${track.artworkUri?.toString() ?? ''}';

  ArtworkPalette _withSafeAccent(ArtworkPalette palette, Color surface) {
    return ArtworkPalette(
      dominant: palette.dominant,
      vibrant: palette.vibrant,
      lightVibrant: palette.lightVibrant,
      darkVibrant: palette.darkVibrant,
      muted: palette.muted,
      ambientColor: palette.ambientColor,
      safeAccent: _ensureContrast(palette.vibrant, surface),
    );
  }

  static Future<List<int>?> _readArtworkPixels(Uri? uri) async {
    if (!Platform.isAndroid || uri == null || uri.scheme != 'content') {
      return null;
    }
    try {
      final pixels = await _channel.invokeMethod<List<dynamic>>(
        'readArtworkPixels',
        <String, Object?>{'uri': uri.toString(), 'size': 64},
      );
      return pixels?.whereType<num>().map((value) => value.toInt()).toList();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @visibleForTesting
  void clearCacheForTesting() {
    _cache.clear();
  }

  @visibleForTesting
  void disposeForTesting() {
    _current.dispose();
  }
}

class _CachedPalette {
  const _CachedPalette(this.palette);
  final ArtworkPalette palette;
}

List<int> _extractPalette(List<int> pixels) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  var saturationSum = 0.0;
  var vibrantScore = -1.0;
  var vibrantColor = 0xFF7C5CFC;
  var lightScore = -1.0;
  var lightColor = 0xFFB8A7FF;
  var darkScore = -1.0;
  var darkColor = 0xFF5C3ACB;
  var mutedScore = -1.0;
  var mutedColor = 0xFF7C5CFC;
  final ambientBuckets = <int, _AmbientColorBucket>{};

  for (final value in pixels) {
    final a = (value >> 24) & 0xFF;
    if (a < 32) continue;
    final r = (value >> 16) & 0xFF;
    final g = (value >> 8) & 0xFF;
    final b = value & 0xFF;
    red += r;
    green += g;
    blue += b;
    count++;
    final maximum = mathMax(r, mathMax(g, b));
    final minimum = mathMin(r, mathMin(g, b));
    final saturation = maximum == 0 ? 0.0 : (maximum - minimum) / maximum;
    saturationSum += saturation;
    final luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
    final color = 0xFF000000 | (r << 16) | (g << 8) | b;
    final hsv = HSVColor.fromColor(Color(color));
    final centerBias = 1.0 - (luminance - 0.52).abs();
    final score = saturation * (0.72 + centerBias * 0.28);
    if (score > vibrantScore) {
      vibrantScore = score;
      vibrantColor = color;
    }
    if (luminance >= 0.55 && score > lightScore) {
      lightScore = score;
      lightColor = color;
    }
    if (luminance <= 0.48 && score > darkScore) {
      darkScore = score;
      darkColor = color;
    }
    final candidateMuted = (1.0 - saturation) * (1.0 - (luminance - 0.5).abs());
    if (candidateMuted > mutedScore) {
      mutedScore = candidateMuted;
      mutedColor = color;
    }
    if (hsv.saturation >= 0.16 && hsv.value >= 0.2) {
      final hueBucket = (hsv.hue / 15).floor() % 24;
      final saturationBucket = (hsv.saturation * 4).floor().clamp(0, 3);
      final valueBucket = (hsv.value * 4).floor().clamp(0, 3);
      final key = hueBucket * 16 + saturationBucket * 4 + valueBucket;
      (ambientBuckets[key] ??= _AmbientColorBucket()).add(r, g, b, hsv);
    }
  }

  if (count == 0) return <int>[];
  var ambientColor = 0;
  var ambientScore = 0.0;
  for (final bucket in ambientBuckets.values) {
    final score =
        bucket.count *
        (0.65 + bucket.averageSaturation) *
        (0.65 + bucket.averageValue * 0.35);
    if (score > ambientScore) {
      ambientScore = score;
      ambientColor = _enhanceAmbientColor(bucket.averageColor).toARGB32();
    }
  }
  final dominant =
      0xFF000000 |
      (((red ~/ count) & 0xFF) << 16) |
      (((green ~/ count) & 0xFF) << 8) |
      ((blue ~/ count) & 0xFF);
  final saturationPermille =
      ((saturationSum / count).clamp(0.0, 1.0) * 1000).round();
  return <int>[
    dominant,
    vibrantColor,
    lightColor,
    darkColor,
    mutedColor,
    saturationPermille,
    ambientColor,
  ];
}

Color _enhanceAmbientColor(Color color) {
  final hsv = HSVColor.fromColor(color);
  final source =
      hsv.saturation < 0.12 ? HSVColor.fromColor(const Color(0xFF7657D5)) : hsv;
  return source
      .withSaturation(source.saturation.clamp(0.52, 0.76).toDouble())
      .withValue(source.value.clamp(0.7, 0.9).toDouble())
      .toColor();
}

class _AmbientColorBucket {
  int count = 0;
  int red = 0;
  int green = 0;
  int blue = 0;
  double _saturation = 0;
  double _value = 0;

  double get averageSaturation => _saturation / count;
  double get averageValue => _value / count;
  Color get averageColor =>
      Color.fromARGB(255, red ~/ count, green ~/ count, blue ~/ count);

  void add(int r, int g, int b, HSVColor hsv) {
    count++;
    red += r;
    green += g;
    blue += b;
    _saturation += hsv.saturation;
    _value += hsv.value;
  }
}

Color _ensureContrast(Color candidate, Color surface) {
  if (_contrastRatio(candidate, surface) >= 4.5) return candidate;
  final target =
      surface.computeLuminance() < 0.45 ? Colors.white : Colors.black;
  for (var step = 1; step <= 20; step++) {
    final adjusted = Color.lerp(candidate, target, step / 20)!;
    if (_contrastRatio(adjusted, surface) >= 4.5) return adjusted;
  }
  return target;
}

double _contrastRatio(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

int mathMax(int a, int b) => a > b ? a : b;
int mathMin(int a, int b) => a < b ? a : b;
