import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class AmbientColorFlow extends StatelessWidget {
  const AmbientColorFlow({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _AmbientColorFlowPainter(color),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AmbientColorFlowPainter extends CustomPainter {
  _AmbientColorFlowPainter(this.color);

  final Color color;
  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    _drawBlur(
      canvas,
      size,
      center: Offset(size.width * 0.5, size.height * 0.48),
      width: size.width * 1.24,
      height: size.height * 0.94,
      opacity: 0.1,
      blur: 148,
    );
    _drawBlur(
      canvas,
      size,
      center: Offset(size.width * 0.16, size.height * 0.28),
      width: size.width * 0.72,
      height: size.height * 0.5,
      opacity: 0.12,
      blur: 112,
    );
    _drawBlur(
      canvas,
      size,
      center: Offset(size.width * 0.84, size.height * 0.74),
      width: size.width * 0.76,
      height: size.height * 0.54,
      opacity: 0.09,
      blur: 128,
    );
  }

  void _drawBlur(
    Canvas canvas,
    Size size, {
    required Offset center,
    required double width,
    required double height,
    required double opacity,
    required double blur,
  }) {
    _paint
      ..color = color.withValues(alpha: opacity)
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blur);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: width, height: height),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientColorFlowPainter oldDelegate) =>
      oldDelegate.color != color;
}
