import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Coalesces fast-scroll-thumb pointer updates to one scroll jump per frame.
///
/// Pointer events can outnumber display frames. Keeping only the latest thumb
/// position avoids redundant scroll/viewport work for positions that cannot
/// be painted before the next frame.
class LibraryViewportEngine {
  LibraryViewportEngine({required ScrollController scrollController})
    : _scrollController = scrollController;

  final ScrollController _scrollController;
  double? _pendingThumbTop;
  double _pendingThumbTravel = 1;
  int? _pendingFrameCallback;
  bool _disposed = false;

  void queueThumbPosition({required double top, required double travel}) {
    if (_disposed || !top.isFinite || !travel.isFinite || travel <= 0) return;
    _pendingThumbTop = top;
    _pendingThumbTravel = travel;
    if (_pendingFrameCallback != null) return;

    _pendingFrameCallback = SchedulerBinding.instance.scheduleFrameCallback(
      (_) {
        _pendingFrameCallback = null;
        _applyPendingJump();
      },
    );
  }

  void flushPendingJump() {
    if (_disposed) return;
    final callback = _pendingFrameCallback;
    if (callback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
      _pendingFrameCallback = null;
    }
    _applyPendingJump();
  }

  void _applyPendingJump() {
    final top = _pendingThumbTop;
    final travel = _pendingThumbTravel;
    _pendingThumbTop = null;
    if (_disposed ||
        top == null ||
        !_scrollController.hasClients ||
        _scrollController.positions.length != 1) {
      return;
    }

    final position = _scrollController.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }
    if (!travel.isFinite || travel <= 0) return;

    final ratio = (top / travel).clamp(0.0, 1.0).toDouble();
    final target = position.maxScrollExtent * ratio;
    if ((position.pixels - target).abs() > 0.5) {
      _scrollController.jumpTo(target);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final callback = _pendingFrameCallback;
    if (callback != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(callback);
    }
    _pendingFrameCallback = null;
    _pendingThumbTop = null;
  }
}
