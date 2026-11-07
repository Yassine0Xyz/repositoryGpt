import 'package:flutter/material.dart';

import '../core/theme/motion_tokens.dart';

class PlayPauseMorph extends StatefulWidget {
  const PlayPauseMorph({
    required this.playing,
    required this.onPressed,
    required this.tooltip,
    this.minimumSize = const Size(48, 48),
    this.iconSize = 25,
    this.backgroundColor,
    this.foregroundColor,
    this.enabled = true,
    this.buffering = false,
    super.key,
  });

  final bool playing;
  final VoidCallback onPressed;
  final String tooltip;
  final Size minimumSize;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool enabled;
  final bool buffering;

  @override
  State<PlayPauseMorph> createState() => _PlayPauseMorphState();
}

class _PlayPauseMorphState extends State<PlayPauseMorph>
    with TickerProviderStateMixin {
  late final AnimationController _icon = AnimationController(
    vsync: this,
    duration: MotionTokens.fast,
    value: widget.playing ? 1 : 0,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: MotionTokens.instant,
  );
  late final Animation<double> _scale =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 1,
            end: 0.9,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 45,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0.9,
            end: 1,
          ).chain(CurveTween(curve: Curves.easeOutBack)),
          weight: 55,
        ),
      ]).animate(_pulse);

  @override
  void didUpdateWidget(covariant PlayPauseMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      final motion = Motion.of(context);
      _icon.animateTo(
        widget.playing ? 1 : 0,
        duration: motion.fast,
        curve: motion.standard,
      );
    }
  }

  void _handlePressed() {
    if (!widget.enabled || widget.buffering) return;
    if (!Motion.of(context).reducedMotion) _pulse.forward(from: 0);
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return IconButton.filled(
      tooltip: widget.tooltip,
      onPressed: widget.enabled && !widget.buffering ? _handlePressed : null,
      style: IconButton.styleFrom(
        minimumSize: widget.minimumSize,
        backgroundColor: widget.backgroundColor,
        foregroundColor: widget.foregroundColor,
        animationDuration: motion.fast,
      ),
      icon: SizedBox.square(
        dimension: widget.iconSize,
        child:
            widget.buffering
                ? CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: widget.foregroundColor,
                )
                : ScaleTransition(
                  scale: _scale,
                  child: AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _icon,
                    size: widget.iconSize,
                  ),
                ),
      ),
    );
  }

  @override
  void dispose() {
    _icon.dispose();
    _pulse.dispose();
    super.dispose();
  }
}
