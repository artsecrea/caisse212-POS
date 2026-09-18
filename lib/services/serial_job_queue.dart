import 'dart:async';

/// Runs jobs one at a time, in the order they were submitted.
///
/// Extracted from [PrintingService] so the concurrency rules that protect the
/// printer can be tested on their own — see `test/serial_job_queue_test.dart`.
///
/// The printer is a single physical resource with two independent producers:
/// the cashier's UI, and the LAN server's waiter-order handler, which fires its
/// prints unawaited. Before this queue existed, a waiter order arriving while
/// the cashier tapped Continue put two jobs on one printer at once:
///
///   * NETWORK — thermal printers accept ONE connection on :9100, so the
///     second connect is refused and burns a 3-attempt backoff before failing.
///   * USB/BLE — concurrent writes on one handle hit the dispatch timeout,
///     which drops the cached printer handle, so the NEXT print also pays a
///     rescan.
///
/// Both look to the cashier like "printing randomly takes forever".
class SerialJobQueue {
  /// The tail of the chain. Each new job is appended to it, so jobs run in
  /// submission order and never overlap.
  Future<void> _chain = Future<void>.value();

  /// Jobs already running on the queue carry this zone value, so a job that
  /// submits another job runs it inline on the slot it already holds instead of
  /// deadlocking while it waits for itself.
  ///
  /// A Zone is what makes re-entrancy detection correct rather than a plain
  /// bool: the value propagates through the running job's own async gaps ONLY.
  /// A fresh caller arriving from elsewhere while that job is mid-`await` runs
  /// in the root zone, sees nothing, and queues properly — which is exactly the
  /// case a bool flag would get wrong, since it cannot tell "nested inside the
  /// running job" from "a second producer arrived mid-job".
  static const Object _runningJobZoneKey = #serialJobQueueRunning;

  int _depth = 0;
  final _depthController = StreamController<int>.broadcast();

  /// Number of jobs submitted and not yet finished, including the running one.
  int get depth => _depth;

  /// Emits [depth] on every change, so a UI can show a non-blocking
  /// "N jobs pending" indicator instead of a modal overlay.
  Stream<int> get depthStream => _depthController.stream;

  /// True when called from inside a job this queue is running.
  bool get isOnQueue => Zone.current[_runningJobZoneKey] == true;

  /// Run [job] on the queue, or inline if already on it.
  ///
  /// The caller sees whatever [job] returns or throws. A job that throws does
  /// NOT break the chain: jobs queued behind it still run.
  Future<T> add<T>(Future<T> Function() job) {
    if (isOnQueue) return job();

    _depth++;
    _depthController.add(_depth);

    final completer = Completer<T>();

    _chain = _chain.then((_) async {
      // try/catch rather than `.then(onError:)`: a job that throws
      // synchronously would otherwise escape and leave `completer` uncompleted,
      // hanging its caller forever.
      try {
        completer.complete(
          await runZoned(job, zoneValues: const {_runningJobZoneKey: true}),
        );
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }).whenComplete(() {
      _depth--;
      _depthController.add(_depth);
    });

    return completer.future;
  }

  void dispose() {
    _depthController.close();
  }
}
