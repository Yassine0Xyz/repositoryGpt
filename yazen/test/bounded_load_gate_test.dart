import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/bounded_load_gate.dart';

void main() {
  test('newest-first gate reports stale queue evictions precisely', () async {
    final gate = BoundedLoadGate(
      maxConcurrent: 1,
      maxQueued: 1,
      preferNewest: true,
    );

    expect(await gate.acquireWithResult(), LoadPermitResult.acquired);
    final staleWaiter = gate.acquireWithResult();
    final newestWaiter = gate.acquireWithResult();

    expect(await staleWaiter, LoadPermitResult.queueEvicted);
    expect(gate.queueEvictions, 1);
    expect(gate.queueFullRejections, 0);

    gate.release();
    expect(await newestWaiter, LoadPermitResult.acquired);
    gate.release();
    expect(gate.activeLoads, 0);
  });

  test('zero-capacity gate reports queue-full rejection', () async {
    final gate = BoundedLoadGate(maxConcurrent: 1, maxQueued: 0);

    expect(await gate.acquireWithResult(), LoadPermitResult.acquired);
    expect(await gate.acquireWithResult(), LoadPermitResult.queueFull);
    expect(gate.queueFullRejections, 1);
    gate.release();
  });
}
