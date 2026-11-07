import 'package:flutter/material.dart';

class BreathingGlow extends StatefulWidget {
  const BreathingGlow({
    required this.child,
    required this.enabled,
    this.color,
    this.duration = const Duration(milliseconds: 1900),
    super.key,
  });

  final Widget child;
  final bool enabled;
  final Color? color;
  final Duration duration;

  @override
  State<BreathingGlow> createState() => _BreathingGlowState();
}

class _BreathingGlowState extends State<BreathingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _sync();
  }

  @override
  void didUpdateWidget(covariant BreathingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final intensity =
            widget.enabled
                ? Curves.easeInOut.transform(_controller.value)
                : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: color.withValues(alpha: 0.12 + intensity * 0.22),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: intensity * 0.18),
                blurRadius: 18 + intensity * 10,
                spreadRadius: intensity * 1.5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({required this.active, this.color, this.size = 8, super.key});

  final bool active;
  final Color? color;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _sync();
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.45,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: SizedBox.square(dimension: widget.size),
      ),
    );
  }
}
