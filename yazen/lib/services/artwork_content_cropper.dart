import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

@immutable
class ProcessedArtwork {
  const ProcessedArtwork({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

class ArtworkContentCropper {
  ArtworkContentCropper._();

  static const int _maxCachedBounds = 256;
  static const int _analysisLongestSide = 128;
  static const int _maxOutputLongestSide = 2048;
  static final LinkedHashMap<String, ui.Rect?> _boundsCache =
      LinkedHashMap<String, ui.Rect?>();
  static final Map<String, Future<ui.Rect?>> _pendingAnalysis =
      <String, Future<ui.Rect?>>{};

  static Future<ProcessedArtwork> process(
    Uint8List bytes, {
    required String cacheKey,
    int targetPixels = _maxOutputLongestSide,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final originalWidth = descriptor.width;
      final originalHeight = descriptor.height;
      if (originalWidth < 2 || originalHeight < 2) {
        return ProcessedArtwork(
          bytes: bytes,
          width: originalWidth,
          height: originalHeight,
        );
      }

      // Keep content-bound detection for square artwork too. Some covers use
      // square canvases with intentional side padding, and changing that
      // framing would alter the existing visual behavior.
      final bounds = await _boundsFor(
        cacheKey,
        descriptor,
        originalWidth,
        originalHeight,
      );
      if (bounds == null) {
        return ProcessedArtwork(
          bytes: bytes,
          width: originalWidth,
          height: originalHeight,
        );
      }

      final outputLimit = targetPixels.clamp(96, _maxOutputLongestSide);
      final scale = math.min(
        1.0,
        outputLimit / math.max(originalWidth, originalHeight),
      );
      final decodeWidth = math.max(1, (originalWidth * scale).round());
      final decodeHeight = math.max(1, (originalHeight * scale).round());
      final codec =
          originalWidth >= originalHeight
              ? await descriptor.instantiateCodec(targetWidth: decodeWidth)
              : await descriptor.instantiateCodec(targetHeight: decodeHeight);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final cropBounds = bounds;
          final source = ui.Rect.fromLTRB(
            cropBounds.left * image.width,
            cropBounds.top * image.height,
            cropBounds.right * image.width,
            cropBounds.bottom * image.height,
          );
          final cropWidth = source.width.round().clamp(1, image.width);
          final cropHeight = source.height.round().clamp(1, image.height);
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          canvas.drawImageRect(
            image,
            source,
            ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.medium,
          );
          final picture = recorder.endRecording();
          try {
            final cropped = await picture.toImage(cropWidth, cropHeight);
            try {
              final png = await cropped.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (png == null) {
                throw StateError('Unable to encode cropped artwork.');
              }
              return ProcessedArtwork(
                bytes: png.buffer.asUint8List(
                  png.offsetInBytes,
                  png.lengthInBytes,
                ),
                width: cropWidth,
                height: cropHeight,
              );
            } finally {
              cropped.dispose();
            }
          } finally {
            picture.dispose();
          }
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  static Future<ui.Rect?> _boundsFor(
    String key,
    ui.ImageDescriptor descriptor,
    int width,
    int height,
  ) async {
    if (_boundsCache.containsKey(key)) {
      final cached = _boundsCache.remove(key);
      _boundsCache[key] = cached;
      return cached;
    }
    final pending = _pendingAnalysis[key];
    if (pending != null) return pending;

    final analysis = _analyze(descriptor, width, height);
    _pendingAnalysis[key] = analysis;
    try {
      final bounds = await analysis;
      _boundsCache[key] = bounds;
      while (_boundsCache.length > _maxCachedBounds) {
        _boundsCache.remove(_boundsCache.keys.first);
      }
      return bounds;
    } finally {
      _pendingAnalysis.remove(key);
    }
  }

  static Future<ui.Rect?> _analyze(
    ui.ImageDescriptor descriptor,
    int width,
    int height,
  ) async {
    final scale = math.min(1.0, _analysisLongestSide / math.max(width, height));
    final sampleWidth = math.max(1, (width * scale).round());
    final sampleHeight = math.max(1, (height * scale).round());
    final codec =
        width >= height
            ? await descriptor.instantiateCodec(targetWidth: sampleWidth)
            : await descriptor.instantiateCodec(targetHeight: sampleHeight);
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final pixels = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final bounds = _findContentBounds(pixels, image.width, image.height);
        if (bounds == null) return null;
        return ui.Rect.fromLTRB(bounds[0], bounds[1], bounds[2], bounds[3]);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  static List<double>? _findContentBounds(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final horizontal = _AxisPrefix(pixels, width, height, horizontal: true);
    final vertical = _AxisPrefix(pixels, width, height, horizontal: false);
    final left = _edgePadding(horizontal, fromEnd: false);
    final right = _edgePadding(horizontal, fromEnd: true);
    final top = _edgePadding(vertical, fromEnd: false);
    final bottom = _edgePadding(vertical, fromEnd: true);

    final horizontalCrop = _pairedEdgeCrop(left, right);
    final verticalCrop = _pairedEdgeCrop(top, bottom);
    if (horizontalCrop == null && verticalCrop == null) return null;

    final leftCrop = horizontalCrop?.start ?? 0;
    final rightCrop = horizontalCrop?.end ?? 0;
    final topCrop = verticalCrop?.start ?? 0;
    final bottomCrop = verticalCrop?.end ?? 0;
    final leftMargin = math.min(0.035, leftCrop * 0.18);
    final rightMargin = math.min(0.035, rightCrop * 0.18);
    final topMargin = math.min(0.035, topCrop * 0.18);
    final bottomMargin = math.min(0.035, bottomCrop * 0.18);
    final bounds = ui.Rect.fromLTRB(
      (leftCrop - leftMargin).clamp(0.0, 0.45),
      (topCrop - topMargin).clamp(0.0, 0.45),
      (1 - rightCrop + rightMargin).clamp(0.55, 1.0),
      (1 - bottomCrop + bottomMargin).clamp(0.55, 1.0),
    );
    if (bounds.width * bounds.height < 0.5) return null;
    return <double>[bounds.left, bounds.top, bounds.right, bounds.bottom];
  }

  static ({double start, double end})? _pairedEdgeCrop(
    double start,
    double end,
  ) {
    if (start < 0.12 || end < 0.12 || (start - end).abs() > 0.16) return null;
    return (start: start, end: end);
  }

  static double _edgePadding(_AxisPrefix prefix, {required bool fromEnd}) {
    final length = prefix.length;
    final step = math.max(1, (length * 0.02).round());
    final minBand = math.max(2, (length * 0.12).ceil());
    final maxBand = math.min((length * 0.38).floor(), length ~/ 2 - 1);
    var best = 0.0;

    for (var band = minBand; band <= maxBand; band += step) {
      final edgeStart = fromEnd ? length - band : 0;
      final innerStart = fromEnd ? length - band * 2 : band;
      final innerEnd = fromEnd ? length - band : band * 2;
      if (innerStart < 0 || innerEnd > length) continue;
      final edge = prefix.measure(edgeStart, edgeStart + band);
      final inner = prefix.measure(innerStart, innerEnd);
      if (edge.standardDeviation <= 14 &&
          _colorDistance(edge, inner) >= 42 &&
          (inner.standardDeviation >= 10 ||
              _colorDistance(edge, inner) >= 58)) {
        best = band / length;
      }
    }
    return best;
  }

  static double _colorDistance(_BandStats first, _BandStats second) {
    final red = first.red - second.red;
    final green = first.green - second.green;
    final blue = first.blue - second.blue;
    final alpha = (first.alpha - second.alpha) * 1.5;
    return math.sqrt(red * red + green * green + blue * blue + alpha * alpha);
  }

  @visibleForTesting
  static void clearCacheForTesting() {
    _boundsCache.clear();
    _pendingAnalysis.clear();
  }
}

class _BandStats {
  const _BandStats(
    this.red,
    this.green,
    this.blue,
    this.alpha,
    this.standardDeviation,
  );

  final double red;
  final double green;
  final double blue;
  final double alpha;
  final double standardDeviation;
}

class _AxisPrefix {
  _AxisPrefix(
    Uint8List pixels,
    int width,
    int height, {
    required bool horizontal,
  }) : length = horizontal ? width : height,
       _crossLength = horizontal ? height : width,
       _red = List<double>.filled((horizontal ? width : height) + 1, 0),
       _green = List<double>.filled((horizontal ? width : height) + 1, 0),
       _blue = List<double>.filled((horizontal ? width : height) + 1, 0),
       _alpha = List<double>.filled((horizontal ? width : height) + 1, 0),
       _redSquared = List<double>.filled((horizontal ? width : height) + 1, 0),
       _greenSquared = List<double>.filled(
         (horizontal ? width : height) + 1,
         0,
       ),
       _blueSquared = List<double>.filled((horizontal ? width : height) + 1, 0),
       _alphaSquared = List<double>.filled(
         (horizontal ? width : height) + 1,
         0,
       ) {
    for (var primary = 0; primary < length; primary++) {
      var red = 0.0;
      var green = 0.0;
      var blue = 0.0;
      var alpha = 0.0;
      var redSquared = 0.0;
      var greenSquared = 0.0;
      var blueSquared = 0.0;
      var alphaSquared = 0.0;
      for (var secondary = 0; secondary < _crossLength; secondary++) {
        final x = horizontal ? primary : secondary;
        final y = horizontal ? secondary : primary;
        final offset = (y * width + x) * 4;
        final r = pixels[offset].toDouble();
        final g = pixels[offset + 1].toDouble();
        final b = pixels[offset + 2].toDouble();
        final a = pixels[offset + 3].toDouble();
        red += r;
        green += g;
        blue += b;
        alpha += a;
        redSquared += r * r;
        greenSquared += g * g;
        blueSquared += b * b;
        alphaSquared += a * a;
      }
      final next = primary + 1;
      _red[next] = _red[primary] + red;
      _green[next] = _green[primary] + green;
      _blue[next] = _blue[primary] + blue;
      _alpha[next] = _alpha[primary] + alpha;
      _redSquared[next] = _redSquared[primary] + redSquared;
      _greenSquared[next] = _greenSquared[primary] + greenSquared;
      _blueSquared[next] = _blueSquared[primary] + blueSquared;
      _alphaSquared[next] = _alphaSquared[primary] + alphaSquared;
    }
  }

  final int length;
  final int _crossLength;
  final List<double> _red;
  final List<double> _green;
  final List<double> _blue;
  final List<double> _alpha;
  final List<double> _redSquared;
  final List<double> _greenSquared;
  final List<double> _blueSquared;
  final List<double> _alphaSquared;

  _BandStats measure(int start, int end) {
    final count = (end - start) * _crossLength;
    final averageRed = (_red[end] - _red[start]) / count;
    final averageGreen = (_green[end] - _green[start]) / count;
    final averageBlue = (_blue[end] - _blue[start]) / count;
    final averageAlpha = (_alpha[end] - _alpha[start]) / count;
    final variance =
        ((_redSquared[end] - _redSquared[start]) / count -
            averageRed * averageRed +
            (_greenSquared[end] - _greenSquared[start]) / count -
            averageGreen * averageGreen +
            (_blueSquared[end] - _blueSquared[start]) / count -
            averageBlue * averageBlue +
            (_alphaSquared[end] - _alphaSquared[start]) / count -
            averageAlpha * averageAlpha) /
        4;
    return _BandStats(
      averageRed,
      averageGreen,
      averageBlue,
      averageAlpha,
      math.sqrt(math.max(0, variance)),
    );
  }
}
