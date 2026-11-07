import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/theme_tokens.dart';
import '../services/scroll_performance_mode.dart';

class EchoRevealSession {
  final Set<Object> _revealedKeys = <Object>{};

  bool claim(Object? key) => key == null || _revealedKeys.add(key);
}

class EchoReveal extends StatefulWidget {
  const EchoReveal({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 620),
    this.offset = const Offset(0, 0.08),
    this.session,
    this.revealKey,
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset offset;
  final EchoRevealSession? session;
  final Object? revealKey;

  @override
  State<EchoReveal> createState() => _EchoRevealState();
}

class _EchoRevealState extends State<EchoReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  late Animation<Offset> _slide;
  Timer? _delayTimer;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _curved = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = _createSlide(widget.offset);
    if (widget.duration <= Duration.zero) {
      _controller.value = 1;
      return;
    }
    _startReveal();
  }

  Animation<Offset> _createSlide(Offset offset) =>
      Tween<Offset>(begin: offset, end: Offset.zero).animate(_curved);

  void _startReveal() {
    final session = widget.session;
    if (session != null && !session.claim(widget.revealKey)) {
      _controller.value = 1;
      return;
    }
    void reveal() {
      if (!mounted) return;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }

    if (widget.delay <= Duration.zero) {
      reveal();
    } else {
      _delayTimer = Timer(widget.delay, reveal);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion && !_reduceMotion) {
      _reduceMotion = true;
      _delayTimer?.cancel();
      _controller.value = 1;
    } else if (!reduceMotion && _reduceMotion) {
      _reduceMotion = false;
    }
  }

  @override
  void didUpdateWidget(covariant EchoReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.offset != widget.offset) {
      _slide = _createSlide(widget.offset);
    }
    if (widget.duration <= Duration.zero) {
      _delayTimer?.cancel();
      _controller.value = 1;
      return;
    }
    if (oldWidget.session != widget.session ||
        oldWidget.revealKey != widget.revealKey) {
      _delayTimer?.cancel();
      _controller.reset();
      _startReveal();
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.duration <= Duration.zero ||
        _reduceMotion ||
        MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _curved,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class EchoPressable extends StatefulWidget {
  const EchoPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  @override
  State<EchoPressable> createState() => _EchoPressableState();
}

class _EchoPressableState extends State<EchoPressable> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (MediaQuery.disableAnimationsOf(context) || _pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (MediaQuery.disableAnimationsOf(context) || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(20);
    return MouseRegion(
      cursor:
          widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
      onEnter: widget.onTap == null ? null : (_) => _setHovered(true),
      onExit: widget.onTap == null ? null : (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale:
              _pressed
                  ? 0.975
                  : _hovered
                  ? 1.008
                  : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: ClipRRect(borderRadius: radius, child: widget.child),
        ),
      ),
    );
  }
}

class EchoBreathingGlow extends StatefulWidget {
  const EchoBreathingGlow({
    required this.child,
    required this.color,
    this.enabled = true,
    this.radius = 22,
    super.key,
  });

  final Widget child;
  final Color color;
  final bool enabled;
  final double radius;

  @override
  State<EchoBreathingGlow> createState() => _EchoBreathingGlowState();
}

class _EchoBreathingGlowState extends State<EchoBreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    ScrollPerformanceMode.isScrolling.addListener(_onScrollModeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _tickerEnabled = TickerMode.of(context);
    _scrolling = ScrollPerformanceMode.isScrolling.value;
    _sync();
  }

  void _onScrollModeChanged() {
    _scrolling = ScrollPerformanceMode.isScrolling.value;
    _sync();
  }

  @override
  void didUpdateWidget(covariant EchoBreathingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled && !_reduceMotion && _tickerEnabled && !_scrolling) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      if (_controller.isAnimating) _controller.stop(canceled: false);
      if (_reduceMotion) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    ScrollPerformanceMode.isScrolling.removeListener(_onScrollModeChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final intensity = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.color.withValues(
                  alpha: widget.enabled ? 0.12 + intensity * 0.18 : 0.05,
                ),
                blurRadius: 22 + intensity * 14,
                spreadRadius: intensity * 1.5,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

class EchoAmbientLayer extends StatefulWidget {
  const EchoAmbientLayer({required this.tokens, super.key});

  final ThemeTokens tokens;

  @override
  State<EchoAmbientLayer> createState() => _EchoAmbientLayerState();
}

class _EchoAmbientLayerState extends State<EchoAmbientLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _scrolling = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    );
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
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    ScrollPerformanceMode.isScrolling.removeListener(_onScrollModeChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return const SizedBox.expand();
    return CustomPaint(
      painter: _EchoAmbientPainter(_controller, widget.tokens),
      child: const SizedBox.expand(),
    );
  }
}

class _EchoAmbientPainter extends CustomPainter {
  _EchoAmbientPainter(this.animation, this.tokens) : super(repaint: animation);

  final Animation<double> animation;
  final ThemeTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final time = animation.value * 2 * 3.14159265359;
    final paint = Paint()..style = PaintingStyle.fill;
    final glows = <({Offset center, double radius, Color color})>[
      (
        center: Offset(
          size.width * (0.12 + 0.06 * _sin(time)),
          size.height * 0.12,
        ),
        radius: size.width * 0.55,
        color: tokens.accentStrong.withValues(
          alpha: tokens.isLight ? 0.035 : 0.075,
        ),
      ),
      (
        center: Offset(
          size.width * (0.90 + 0.06 * _cos(time * 0.78)),
          size.height * 0.48,
        ),
        radius: size.width * 0.52,
        color: tokens.accent.withValues(alpha: tokens.isLight ? 0.025 : 0.055),
      ),
      (
        center: Offset(
          size.width * 0.42,
          size.height * (0.98 + 0.04 * _sin(time * 0.58)),
        ),
        radius: size.width * 0.50,
        color: tokens.accentStrong.withValues(
          alpha: tokens.isLight ? 0.018 : 0.035,
        ),
      ),
    ];
    for (final glow in glows) {
      paint.shader = RadialGradient(
        colors: <Color>[glow.color, glow.color.withValues(alpha: 0)],
      ).createShader(Rect.fromCircle(center: glow.center, radius: glow.radius));
      canvas.drawRect(Offset.zero & size, paint);
    }
  }

  double _sin(double value) => math.sin(value);
  double _cos(double value) => math.cos(value);

  @override
  bool shouldRepaint(covariant _EchoAmbientPainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}

class EchoIconButton extends StatefulWidget {
  const EchoIconButton({
    required this.icon,
    required this.onPressed,
    this.selectedIcon,
    this.selected = false,
    this.tooltip,
    this.color,
    this.selectedColor,
    this.backgroundColor,
    this.selectedBackgroundColor,
    this.size = 42,
    super.key,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final bool selected;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? selectedColor;
  final Color? backgroundColor;
  final Color? selectedBackgroundColor;
  final double size;

  @override
  State<EchoIconButton> createState() => _EchoIconButtonState();
}

class _EchoIconButtonState extends State<EchoIconButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).colorScheme;
    final active = widget.selected || _hovered;
    final icon =
        widget.selected && widget.selectedIcon != null
            ? widget.selectedIcon!
            : widget.icon;
    return MouseRegion(
      cursor:
          widget.onPressed == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
      onEnter:
          widget.onPressed == null
              ? null
              : (_) => setState(() => _hovered = true),
      onExit:
          widget.onPressed == null
              ? null
              : (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown:
            widget.onPressed == null
                ? null
                : (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.94 : (_hovered ? 1.04 : 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow:
                  widget.selected && widget.onPressed != null
                      ? <BoxShadow>[
                        BoxShadow(
                          color: (widget.selectedColor ?? tokens.primary)
                              .withValues(alpha: 0.12),
                          blurRadius: 10,
                        ),
                      ]
                      : const <BoxShadow>[],
            ),
            child: IconButton(
              tooltip: widget.tooltip,
              onPressed: widget.onPressed,
              constraints: BoxConstraints.tightFor(
                width: widget.size,
                height: widget.size,
              ),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor:
                    active
                        ? (widget.selectedBackgroundColor ??
                            tokens.primary.withValues(alpha: 0.14))
                        : widget.backgroundColor,
                foregroundColor:
                    active
                        ? (widget.selectedColor ?? tokens.primary)
                        : widget.color,
                shape: const CircleBorder(),
              ),
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder:
                    (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                child: Icon(icon, key: ValueKey<IconData>(icon), size: 20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
