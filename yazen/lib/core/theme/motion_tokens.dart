import 'package:flutter/material.dart';

abstract final class MotionTokens {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);
  static const Duration hero = Duration(milliseconds: 520);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const Curve exit = Curves.easeInCubic;

  static const SpringDescription dragSettleSpring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 26,
  );
}

@immutable
class Motion {
  const Motion._(this.reducedMotion);

  final bool reducedMotion;

  factory Motion.of(BuildContext context) =>
      Motion._(MediaQuery.disableAnimationsOf(context));

  Duration get instant => reducedMotion ? Duration.zero : MotionTokens.instant;
  Duration get fast => reducedMotion ? Duration.zero : MotionTokens.fast;
  Duration get base => reducedMotion ? Duration.zero : MotionTokens.base;
  Duration get slow => reducedMotion ? Duration.zero : MotionTokens.slow;
  Duration get hero => reducedMotion ? Duration.zero : MotionTokens.hero;

  Curve get standard => MotionTokens.standard;
  Curve get emphasized => MotionTokens.emphasized;
  Curve get exit => MotionTokens.exit;

  SpringDescription get dragSettleSpring => MotionTokens.dragSettleSpring;
}
