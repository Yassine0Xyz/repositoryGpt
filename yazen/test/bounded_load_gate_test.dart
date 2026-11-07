import 'package:flutter_test/flutter_test.dart';
import 'package:yazen/services/bounded_load_gate.dart';

void main() {
  group('BoundedLoadGate', () {
    test('limits active loads and transfers permits to queued work', () async {
      final gate = BoundedLoadGate(maxConcurrent: 2, maxQueued: 3);

      expect(await gate.acquire(), isTrue);
      expect(await gate.acquire(), isTrue);
      expect(gate.activeLoads, 2);

      final first = gate.acquire();
      final second = gate.acquire();
      expect(gate.queuedLoads, 2);

      gate.release();
      expect(await first, isTrue);
      expect(gate.activeLoads, 2);
      gate.release();
      expect(await second, isTrue);
      expect(gate.activeLoads, 2);

      gate.release();
      gate.release();
      expect(gate.activeLoads, 0);
      expect(gate.queuedLoads, 0);
    });

    test('discards the oldest pending work when the queue is full', () async {
      final gate = BoundedLoadGate(maxConcurrent: 1, maxQueued: 2);

      expect(await gate.acquire(), isTrue);
      final oldest = gate.acquire();
      final middle = gate.acquire();
      final newest = gate.acquire();

      expect(gate.queuedLoads, 2);
      expect(await oldest, isFalse);

      gate.release();
      expect(await middle, isTrue);
      gate.release();
      expect(await newest, isTrue);
      gate.release();
      expect(gate.activeLoads, 0);
    });

    test('prioritizes newest viewport work when configured', () async {
      final gate = BoundedLoadGate(
        maxConcurrent: 1,
        maxQueued: 3,
        preferNewest: true,
      );

      expect(await gate.acquire(), isTrue);
      final oldest = gate.acquire();
      final middle = gate.acquire();
      final newest = gate.acquire();

      gate.release();
      expect(await newest, isTrue);
      gate.release();
      expect(await middle, isTrue);
      gate.release();
      expect(await oldest, isTrue);
      gate.release();
      expect(gate.activeLoads, 0);
    });

    test('drops oldest viewport request when newest-first queue is full', () async {
      final gate = BoundedLoadGate(
        maxConcurrent: 1,
        maxQueued: 2,
        preferNewest: true,
      );

      expect(await gate.acquire(), isTrue);
      final oldest = gate.acquire();
      final middle = gate.acquire();
      final newest = gate.acquire();

      expect(gate.queuedLoads, 2);
      expect(await oldest, isFalse);
      gate.release();
      expect(await newest, isTrue);
      gate.release();
      expect(await middle, isTrue);
      gate.release();
      expect(gate.activeLoads, 0);
    });

    test('rejects queued work immediately when maxQueued is zero', () async {
      final gate = BoundedLoadGate(maxConcurrent: 1, maxQueued: 0);

      expect(await gate.acquire(), isTrue);
      expect(await gate.acquire(), isFalse);
      expect(gate.rejectedLoads, 1);
      gate.release();
      expect(gate.activeLoads, 0);
    });

    test('counts requests evicted when the bounded queue overflows', () async {
      final gate = BoundedLoadGate(
        maxConcurrent: 1,
        maxQueued: 1,
        preferNewest: true,
      );

      expect(await gate.acquire(), isTrue);
      final evicted = gate.acquire();
      final newest = gate.acquire();

      expect(await evicted, isFalse);
      expect(gate.rejectedLoads, 1);
      gate.release();
      expect(await newest, isTrue);
      gate.release();
      expect(gate.rejectedLoads, 1);
    });
  });
}
