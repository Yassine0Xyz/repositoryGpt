import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import '../../widgets/echo_motion.dart';
import '../../services/scroll_performance_mode.dart';
import 'theme_tokens.dart';

export 'theme_tokens.dart' show EchoThemePreset, ThemeTokens;

class ThemeProvider extends ChangeNotifier {
  static const _presetKey = 'echo.theme_preset';

  ThemeProvider({EchoThemePreset initialPreset = EchoThemePreset.oledBlack})
    : _preset = initialPreset;

  EchoThemePreset _preset;
  ImageProvider<Object>? _customBackground;

  EchoThemePreset get preset => _preset;
  ThemeTokens get tokens => ThemeTokens.fromPreset(_preset);
  ImageProvider<Object>? get customBackground => _customBackground;
  bool get hasCustomBackground => _customBackground != null;
  ThemeData get theme => buildAppTheme(tokens: tokens);

  Future<void> load() async {
    final preferences = await SharedPreferences.getInstance();
    final savedId = preferences.getString(_presetKey);
    if (savedId == null) return;
    EchoThemePreset? savedPreset;
    for (final preset in EchoThemePreset.values) {
      if (preset.id == savedId) {
        savedPreset = preset;
        break;
      }
    }
    if (savedPreset != null && savedPreset != _preset) {
      _preset = savedPreset;
      notifyListeners();
    }
  }

  void setPreset(EchoThemePreset preset) {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    unawaited(_savePreset(preset));
  }

  Future<void> _savePreset(EchoThemePreset preset) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_presetKey, preset.id);
  }

  void setCustomBackground(ImageProvider<Object>? image) {
    if (_customBackground == image) return;
    _customBackground = image;
    notifyListeners();
  }

  void clearCustomBackground() {
    if (_customBackground == null) return;
    _customBackground = null;
    notifyListeners();
  }
}

class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ThemeProvider>();
    final tokens = state.tokens;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(color: tokens.background),
        if (state.preset == EchoThemePreset.rgbRainbow)
          const RepaintBoundary(child: _RgbRainbowLayer())
        else
          RepaintBoundary(child: EchoAmbientLayer(tokens: tokens)),
        if (state.customBackground != null) ...<Widget>[
          // A full-screen blur is one of the more expensive raster effects in
          // the app. Keep the softened look while idle, but remove the filter
          // entirely during active scrolling so it cannot compete with list
          // layout and artwork decoding for GPU time.
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<bool>(
                valueListenable: ScrollPerformanceMode.isScrolling,
                builder: (context, scrolling, _) {
                  final image = Image(
                    image: state.customBackground!,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  );
                  if (scrolling) return image;
                  return ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: image,
                  );
                },
              ),
            ),
          ),
          Positioned.fill(child: ColoredBox(color: tokens.scrim)),
        ],
        child,
      ],
    );
  }
}

class _RgbRainbowLayer extends StatefulWidget {
  const _RgbRainbowLayer();

  @override
  State<_RgbRainbowLayer> createState() => _RgbRainbowLayerState();
}

class _RgbRainbowLayerState extends State<_RgbRainbowLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _FrameLimitedAnimationValue _paintValue;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    );
    _paintValue = _FrameLimitedAnimationValue(_controller);
    ScrollPerformanceMode.isScrolling.addListener(_onScrollModeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.of(context);
    _scrolling = ScrollPerformanceMode.isScrolling.value;
    _syncAnimation();
  }

  void _onScrollModeChanged() {
    _scrolling = ScrollPerformanceMode.isScrolling.value;
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_reduceMotion || !_tickerEnabled || _scrolling) {
      if (_controller.isAnimating) _controller.stop(canceled: false);
      _paintValue.sync();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    ScrollPerformanceMode.isScrolling.removeListener(_onScrollModeChanged);
    _paintValue.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RgbRainbowPainter(_paintValue),
      child: const SizedBox.expand(),
    );
  }
}

class _FrameLimitedAnimationValue extends ChangeNotifier
    implements ValueListenable<double> {
  _FrameLimitedAnimationValue(this._controller) : _value = _controller.value {
    _controller.addListener(_onTick);
  }

  static const Duration _minimumPaintInterval = Duration(milliseconds: 50);

  final AnimationController _controller;
  Duration? _lastPublishedElapsed;
  double _value;

  @override
  double get value => _value;

  void _onTick() {
    final elapsed = _controller.lastElapsedDuration;
    final previous = _lastPublishedElapsed;
    if (elapsed != null &&
        previous != null &&
        elapsed - previous < _minimumPaintInterval) {
      return;
    }
    _lastPublishedElapsed = elapsed;
    _publish();
  }

  void _publish() {
    final next = _controller.value;
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  void sync() {
    _lastPublishedElapsed = _controller.lastElapsedDuration;
    _publish();
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    super.dispose();
  }
}

class _RgbRainbowPainter extends CustomPainter {
  _RgbRainbowPainter(this.animation) : super(repaint: animation);

  final ValueListenable<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * math.pi * 2;
    final pulse = 0.92 + math.sin(t * 1.4) * 0.08;
    final rect = Offset.zero & size;
    final glows = <({Offset center, double radius, double hue, double alpha})>[
      (
        center: Offset(
          size.width * (0.14 + math.sin(t * 0.83) * 0.18),
          size.height * (0.16 + math.cos(t * 0.52) * 0.08),
        ),
        radius: size.width * 0.58 * pulse,
        hue: (265 + animation.value * 360) % 360,
        alpha: 0.22,
      ),
      (
        center: Offset(
          size.width * (0.84 + math.cos(t * 0.71) * 0.14),
          size.height * (0.34 + math.sin(t * 0.47) * 0.14),
        ),
        radius: size.width * 0.64 * pulse,
        hue: (190 + animation.value * 360) % 360,
        alpha: 0.16,
      ),
      (
        center: Offset(
          size.width * (0.36 + math.sin(t * 0.39) * 0.16),
          size.height * (0.88 + math.cos(t * 0.64) * 0.08),
        ),
        radius: size.width * 0.60 * pulse,
        hue: (325 + animation.value * 360) % 360,
        alpha: 0.15,
      ),
      (
        center: Offset(
          size.width * (0.70 + math.sin(t * 0.58) * 0.12),
          size.height * (0.78 + math.cos(t * 0.43) * 0.10),
        ),
        radius: size.width * 0.48 * pulse,
        hue: (35 + animation.value * 360) % 360,
        alpha: 0.10,
      ),
    ];
    for (final glow in glows) {
      final color = HSVColor.fromAHSV(1, glow.hue, 0.78, 1).toColor();
      final paint =
          Paint()
            ..style = PaintingStyle.fill
            ..shader = RadialGradient(
              colors: <Color>[
                color.withValues(alpha: glow.alpha),
                color.withValues(alpha: glow.alpha * 0.32),
                color.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.34, 1],
            ).createShader(
              Rect.fromCircle(center: glow.center, radius: glow.radius),
            );
      canvas.drawRect(rect, paint);
    }

    final spectrumPaint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, size.shortestSide * 0.012)
          ..shader = SweepGradient(
            transform: GradientRotation(animation.value * math.pi * 2),
            colors: const <Color>[
              Color(0x007C5CFC),
              Color(0x667C5CFC),
              Color(0x5500D9FF),
              Color(0x55FF3D81),
              Color(0x007C5CFC),
            ],
          ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(size.shortestSide * 0.018),
        Radius.circular(size.shortestSide * 0.07),
      ),
      spectrumPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RgbRainbowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
