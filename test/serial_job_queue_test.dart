import 'dart:async';

import 'package:caisse212/services/serial_job_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SerialJobQueue', () {
    test('runs jobs one at a time, never overlapping', () async {
      final queue = SerialJobQueue();
      var running = 0;
      var maxConcurrent = 0;
      final order = <int>[];

      Future<void> job(int id) => queue.add(() async {
            running++;
            maxConcurrent = running > maxConcurrent ? running : maxConcurrent;
            // Several async gaps: a job holds the slot across all of them.
            await Future<void>.delayed(const Duration(milliseconds: 5));
            await Future<void>.delayed(const Duration(milliseconds: 5));
            order.add(id);
            running--;
          });

      // Submitted together, exactly as the cashier and the waiter handler do.
      await Future.wait([job(1), job(2), job(3), job(4)]);

      expect(maxConcurrent, 1, reason: 'jobs must never overlap on the printer');
      expect(order, [1, 2, 3, 4], reason: 'jobs run in submission order');
      expect(queue.depth, 0);
    });

    test('a job submitted from inside a job runs inline, without deadlocking',
        () async {
      // printPaymentDocuments -> printTicketReceipt -> kickCashDrawer are all
      // queued entry points. The inner ones must not wait for the slot the
      // outer one is already holding.
      final queue = SerialJobQueue();
      final steps = <String>[];

      final result = await queue.add(() async {
        steps.add('outer-start');
        expect(queue.isOnQueue, isTrue);

        final inner = await queue.add(() async {
          steps.add('inner');
          await Future<void>.delayed(const Duration(milliseconds: 1));
          return 'inner-result';
        });

        steps.add('outer-end');
        return inner;
      }).timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('re-entrant add() deadlocked'),
      );

      expect(result, 'inner-result');
      expect(steps, ['outer-start', 'inner', 'outer-end']);
      expect(queue.depth, 0);
    });

    test('a job arriving mid-await from outside still queues', () async {
      // The case a bool re-entrancy flag gets wrong: while job A is parked on
      // an await, a SECOND producer submits job B. B is not nested inside A and
      // must wait, not run inline.
      final queue = SerialJobQueue();
      final events = <String>[];
      final aStarted = Completer<void>();

      final a = queue.add(() async {
        events.add('a-start');
        aStarted.complete();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        events.add('a-end');
      });

      await aStarted.future; // A is now parked mid-await.
      final b = queue.add(() async => events.add('b'));

      await Future.wait([a, b]);
      expect(events, ['a-start', 'a-end', 'b']);
    });

    test('a failing job does not wedge the queue, and the caller sees the error',
        () async {
      // A dead printer must not stop every ticket queued behind it.
      final queue = SerialJobQueue();
      final ran = <String>[];

      final failing = queue.add(() async {
        ran.add('failing');
        throw StateError('printer offline');
      });

      final after = queue.add(() async {
        ran.add('after');
        return 'ok';
      });

      await expectLater(failing, throwsA(isA<StateError>()));
      expect(await after, 'ok');
      expect(ran, ['failing', 'after']);
      expect(queue.depth, 0);
    });

    test('a job throwing synchronously still completes its caller', () async {
      final queue = SerialJobQueue();

      // Not an `async` closure: this throws before returning a Future.
      Future<void> syncThrow() => queue.add<void>(() => throw StateError('boom'));

      await expectLater(
        syncThrow().timeout(const Duration(seconds: 2)),
        throwsA(isA<StateError>()),
      );
      expect(await queue.add(() async => 'still alive'), 'still alive');
    });

    test('depth reports queued work and drains to zero', () async {
      final queue = SerialJobQueue();
      final seen = <int>[];
      final sub = queue.depthStream.listen(seen.add);

      final release = Completer<void>();
      final a = queue.add(() => release.future);
      final b = queue.add(() async {});

      expect(queue.depth, 2, reason: 'one running + one waiting');

      release.complete();
      await Future.wait([a, b]);

      expect(queue.depth, 0);
      expect(seen, containsAllInOrder([1, 2]));
      await sub.cancel();
      queue.dispose();
    });
  });
}
