import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/artwork_content_cropper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('leaves normal square artwork unchanged', () async {
    final bytes = await _artwork(200, 200, _drawTexture);
    final result = await _process('square', bytes);

    expect((result.width, result.height), (200, 200));
    expect(identical(result.bytes, bytes), isTrue);
  });

  test('leaves full-frame portrait artwork unchanged', () async {
    final bytes = await _artwork(120, 200, _drawTexture);
    final result = await _process('portrait', bytes);

    expect((result.width, result.height), (120, 200));
  });

  test('leaves full-frame landscape artwork unchanged', () async {
    final bytes = await _artwork(200, 120, _drawTexture);
    final result = await _process('landscape', bytes);

    expect((result.width, result.height), (200, 120));
  });

  test('crops strongly evidenced black side bars', () async {
    final bytes = await _sidePaddedArtwork(const Color(0xFF050506));
    final result = await _process('black-bars', bytes);

    expect(result.width, lessThan(180));
    expect(result.width, greaterThanOrEqualTo(125));
    expect(result.height, 200);
  });

  test('crops uniform light or colored side padding', () async {
    final bytes = await _sidePaddedArtwork(const Color(0xFFE7D5B7));
    final result = await _process('colored-padding', bytes);

    expect(result.width, lessThan(180));
    expect(result.width, greaterThanOrEqualTo(125));
    expect(result.height, 200);
  });

  test('crops clearly paired side padding with unequal widths', () async {
    final bytes = await _artwork(200, 200, (canvas, _) {
      canvas.drawColor(const Color(0xFFE7D5B7), BlendMode.src);
      _drawTexture(canvas, const Size(104, 200), offsetX: 36);
    });
    final result = await _process('unequal-side-padding', bytes);

    expect(result.width, lessThan(170));
    expect(result.width, greaterThanOrEqualTo(125));
    expect(result.height, 200);
  });

  test(
    'does not crop a single contrasting edge without paired evidence',
    () async {
      final bytes = await _artwork(200, 200, (canvas, _) {
        canvas.drawColor(const Color(0xFFE7D5B7), BlendMode.src);
        _drawTexture(canvas, const Size(160, 200), offsetX: 40);
      });
      final result = await _process('single-edge', bytes);

      expect((result.width, result.height), (200, 200));
    },
  );

  test(
    'reuses detected content bounds for another decode of the same art',
    () async {
      final large = await _sidePaddedArtwork(const Color(0xFF050506));
      final small = await _artwork(100, 100, (canvas, _) {
        canvas.drawColor(const Color(0xFF050506), BlendMode.src);
        _drawTexture(canvas, const Size(60, 100), offsetX: 20);
      });
      await _process('shared-bounds', large);
      final result = await _process('shared-bounds', small);

      expect(result.width, lessThan(90));
      expect(result.height, 100);
    },
  );

  test(
    'keeps intentionally dark artwork with detail across its edges',
    () async {
      final bytes = await _artwork(200, 200, (canvas, size) {
        canvas.drawColor(const Color(0xFF09090C), BlendMode.src);
        for (var y = 0; y < size.height; y += 10) {
          for (var x = 0; x < size.width; x += 10) {
            final channel = (8 + ((x * 7 + y * 11) % 18)).clamp(0, 255);
            canvas.drawRect(
              Rect.fromLTWH(x.toDouble(), y.toDouble(), 10, 10),
              Paint()
                ..color = Color.fromARGB(255, channel, channel, channel + 2),
            );
          }
        }
      });
      final result = await _process('dark-art', bytes);

      expect((result.width, result.height), (200, 200));
    },
  );

  test('crops top and bottom letterboxing in a landscape source', () async {
    final bytes = await _artwork(200, 200, (canvas, size) {
      canvas.drawColor(const Color(0xFF080808), BlendMode.src);
      _drawTexture(canvas, const Size(200, 120), offsetY: 40);
    });
    final result = await _process('letterbox', bytes);

    expect(result.height, lessThan(180));
    expect(result.height, greaterThanOrEqualTo(125));
    expect(result.width, 200);
  });

  test('keeps text and face features inside a padded cover crop', () async {
    final bytes = await _artwork(200, 200, (canvas, size) {
      canvas.drawColor(const Color(0xFF060609), BlendMode.src);
      canvas.drawRect(
        const Rect.fromLTWH(40, 0, 120, 200),
        Paint()..color = const Color(0xFF403080),
      );
      canvas.drawOval(
        const Rect.fromLTWH(76, 42, 48, 54),
        Paint()..color = const Color(0xFFFFD09A),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(60, 92, 80, 75),
          const Radius.circular(24),
        ),
        Paint()..color = const Color(0xFFDD536C),
      );
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 14),
      )..pushStyle(ui.TextStyle(color: const Color(0xFFFFFFFF)));
      builder.addText('ALBUM TITLE');
      final paragraph =
          builder.build()..layout(const ui.ParagraphConstraints(width: 120));
      canvas.drawParagraph(paragraph, const Offset(40, 172));
    });
    final result = await _process('face-and-text', bytes);

    expect(result.width, greaterThanOrEqualTo(125));
    expect(result.width, lessThan(180));
    expect(result.height, 200);
    expect(
      await _pixelAt(result.bytes, result.width ~/ 2, 68),
      const Color(0xFFFFD09A).toARGB32(),
    );
    expect(await _brightPixelsInBottomTextBand(result), greaterThan(0));
  });
}

Future<ProcessedArtwork> _process(String key, Uint8List bytes) {
  return ArtworkContentCropper.process(bytes, cacheKey: key);
}

Future<Uint8List> _sidePaddedArtwork(Color padding) {
  return _artwork(200, 200, (canvas, _) {
    canvas.drawColor(padding, BlendMode.src);
    _drawTexture(canvas, const Size(120, 200), offsetX: 40);
  });
}

Future<Uint8List> _artwork(
  int width,
  int height,
  void Function(Canvas canvas, Size size) draw,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Failed to create test artwork.');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Future<int> _pixelAt(Uint8List bytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Unable to read test image pixels.');
      final offset = (y * image.width + x) * 4;
      return (data.getUint8(offset + 3) << 24) |
          (data.getUint8(offset) << 16) |
          (data.getUint8(offset + 1) << 8) |
          data.getUint8(offset + 2);
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<int> _brightPixelsInBottomTextBand(ProcessedArtwork artwork) async {
  final codec = await ui.instantiateImageCodec(artwork.bytes);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) throw StateError('Unable to read test image pixels.');
      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      var count = 0;
      for (var y = 172; y < 194 && y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = (y * image.width + x) * 4;
          if (pixels[offset] > 220 &&
              pixels[offset + 1] > 220 &&
              pixels[offset + 2] > 220) {
            count++;
          }
        }
      }
      return count;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

void _drawTexture(
  Canvas canvas,
  Size size, {
  double offsetX = 0,
  double offsetY = 0,
}) {
  const colors = <Color>[
    Color(0xFFB743A8),
    Color(0xFF346FBE),
    Color(0xFFE1A74C),
    Color(0xFF368C72),
  ];
  for (var y = 0; y < size.height; y += 20) {
    for (var x = 0; x < size.width; x += 20) {
      canvas.drawRect(
        Rect.fromLTWH(offsetX + x, offsetY + y, 20, 20),
        Paint()..color = colors[((x ~/ 20) + (y ~/ 20)) % colors.length],
      );
    }
  }
}
