import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme/motion_tokens.dart';

class MiniPlayerGestureSurface extends StatefulWidget {
  const MiniPlayerGestureSurface({
    required this.child,
    this.onNext,
    this.onPrevious,
    this.onExpand,
    super.key,
  });

  final Widget child;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final VoidCallback? onExpand;

  @override
  State<MiniPlayerGestureSurface> createState() =>
      _MiniPlayerGestureSurfaceState();
}

class _MiniPlayerGestureSurfaceState extends State<MiniPlayerGestureSurface> {
  static const double _axisLockSlop = 8;
  static const double _feedbackThreshold = 34;
  static const double _commitThreshold = 52;
  double _horizontalTravel = 0;
  double _verticalTravel = 0;
  double _offsetX = 0;
  double _offsetY = 0;
  bool _thresholdFeedbackSent = false;
  bool _dragging = false;
  _MiniDragAxis _axis = _MiniDragAxis.none;

  void _start(DragStartDetails _) {
    setState(() {
      _horizontalTravel = 0;
      _verticalTravel = 0;
      _offsetX = 0;
      _offsetY = 0;
      _thresholdFeedbackSent = false;
      _dragging = true;
      _axis = _MiniDragAxis.none;
    });
  }

  void _update(DragUpdateDetails details) {
    _horizontalTravel += details.delta.dx;
    _verticalTravel += details.delta.dy.abs();
    if (_axis == _MiniDragAxis.none &&
        math.max(_horizontalTravel.abs(), _verticalTravel) >= _axisLockSlop) {
      _axis =
          _horizontalTravel.abs() >= _verticalTravel
              ? _MiniDragAxis.horizontal
              : _MiniDragAxis.vertical;
    }
    final reachesThreshold =
        _axis == _MiniDragAxis.horizontal &&
        _horizontalTravel.abs() >= _feedbackThreshold;
    if (reachesThreshold && !_thresholdFeedbackSent) {
      _thresholdFeedbackSent = true;
      unawaited(Haptics.selection().catchError((Object _) {}));
    } else if (!reachesThreshold) {
      _thresholdFeedbackSent = false;
    }
    setState(() {
      if (_axis == _MiniDragAxis.horizontal) {
        _offsetX = _horizontalTravel.clamp(-90.0, 90.0);
      } else if (_axis == _MiniDragAxis.vertical) {
        _offsetY = (_offsetY + details.delta.dy).clamp(-64.0, 24.0);
      }
    });
  }

  void _finish(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond;
    final horizontalDominant = _axis == _MiniDragAxis.horizontal;
    final shouldCommitSwipe =
        horizontalDominant &&
        (_horizontalTravel.abs() >= _commitThreshold ||
            velocity.dx.abs() >= 120);
    final shouldExpand =
        _axis == _MiniDragAxis.vertical &&
        (_offsetY <= -48 || velocity.dy <= -280);
    final next = _horizontalTravel < 0;
    _settle();
    if (shouldCommitSwipe) {
      if (next) {
        widget.onNext?.call();
      } else {
        widget.onPrevious?.call();
      }
    } else if (shouldExpand) {
      widget.onExpand?.call();
    }
  }

  void _cancel() => _settle();

  void _settle() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _offsetX = 0;
      _offsetY = 0;
      _axis = _MiniDragAxis.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: _start,
      onPanUpdate: _update,
      onPanEnd: _finish,
      onPanCancel: _cancel,
      child: AnimatedContainer(
        duration: _dragging ? Duration.zero : motion.fast,
        curve: motion.standard,
        transform: Matrix4.translationValues(_offsetX, _offsetY, 0),
        child: widget.child,
      ),
    );
  }
}

enum _MiniDragAxis { none, horizontal, vertical }
