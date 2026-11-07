import 'dart:async';
import 'dart:collection';

/// Limits concurrent asynchronous work and bounds the waiting backlog.
///
/// When the queue is full, the oldest pending request is rejected. This is
/// useful for viewport-driven work such as artwork: after a fast scroll, recent
/// requests are more likely to correspond to the rows currently on screen.
class BoundedLoadGate {
  BoundedLoadGate({
    required this.maxConcurrent,
    required this.maxQueued,
    this.preferNewest = false,
  }) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent', 'Must be >= 1');
    }
    if (maxQueued < 0) {
      throw ArgumentError.value(maxQueued, 'maxQueued', 'Must be >= 0');
    }
  }

  final int maxConcurrent;
  final int maxQueued;

  /// When true, newer viewport work is released before stale queued work.
  /// Keep the default FIFO behavior for ordered/background operations.
  final bool preferNewest;
  final Queue<Completer<bool>> _waiters = Queue<Completer<bool>>();
  int _activeLoads = 0;
  int _rejectedLoads = 0;

  int get activeLoads => _activeLoads;
  int get rejectedLoads => _rejectedLoads;
  int get queuedLoads => _waiters.length;

  /// Returns false when this request was discarded while waiting.
  Future<bool> acquire() {
    if (_activeLoads < maxConcurrent) {
      _activeLoads++;
      return Future<bool>.value(true);
    }

    if (maxQueued == 0) {
      _rejectedLoads++;
      return Future<bool>.value(false);
    }

    final waiter = Completer<bool>();
    if (preferNewest) {
      _waiters.addFirst(waiter);
    } else {
      _waiters.addLast(waiter);
    }
    while (_waiters.length > maxQueued) {
      final stale =
          preferNewest ? _waiters.removeLast() : _waiters.removeFirst();
      if (!stale.isCompleted) {
        _rejectedLoads++;
        stale.complete(false);
      }
    }
    return waiter.future;
  }

  /// Releases a permit, transferring it directly to the next prioritized
  /// waiter so the active count never briefly drops below the limit.
  void release() {
    if (_activeLoads == 0) {
      throw StateError('No active load permit to release.');
    }

    while (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete(true);
        return;
      }
    }
    _activeLoads--;
  }
}
