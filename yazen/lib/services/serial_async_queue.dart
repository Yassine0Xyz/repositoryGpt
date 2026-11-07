/// Runs asynchronous operations in submission order and isolates failures.
///
/// Each operation receives its own future, so its caller still observes errors,
/// but one failure does not poison the tail or prevent later operations.
class SerialAsyncQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then<T>((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  /// Completes when every operation submitted before this getter has settled.
  Future<void> get idle => _tail;
}
