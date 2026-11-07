import 'dart:async';

import 'package:flutter/foundation.dart';

/// Temporarily yields non-essential animated background work while any app
/// scroll is active. This keeps decorative motion from competing with layout
/// and rasterization during fast scrolling.
abstract final class ScrollPerformanceMode {
  static final ValueNotifier<bool> isScrolling = ValueNotifier<bool>(false);
  static Timer? _idleTimer;

  static void noteScrollActivity() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!isScrolling.value) isScrolling.value = true;
  }

  static void noteScrollEnd() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 140), _resumeBackground);
  }

  static void _resumeBackground() {
    _idleTimer = null;
    if (isScrolling.value) isScrolling.value = false;
  }
}
