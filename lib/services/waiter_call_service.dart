import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../providers/settings_provider.dart';
import 'activity_log_service.dart' show activityLogServiceProvider;
import 'lan_notification_hub.dart';
import 'waiter_notification_inbox.dart';

/// A cashier asking a waiter to come — one ring on one phone.
class WaiterCall {
  final String id;
  final int waiterId;
  final String waiterName;

  /// Free text the cashier typed. Optional by design: the common case is
  /// "come here", and making the cashier write that every time would get the
  /// feature switched off within a week.
  final String? message;

  final int? tableId;
  final String? tableName;

  /// Who rang, for the waiter's screen and the audit trail.
  final String fromUser;

  /// Whether the phone should keep ringing until the waiter dismisses it.
  final bool ringUntilDismissed;

  final DateTime createdAt;
  DateTime? acknowledgedAt;

  WaiterCall({
    required this.id,
    required this.waiterId,
    required this.waiterName,
    required this.fromUser,
    required this.createdAt,
    this.message,
    this.tableId,
    this.tableName,
    this.ringUntilDismissed = true,
    this.acknowledgedAt,
  });

  Map<String, dynamic> toPayload() => {
        'callId': id,
        'waiterId': waiterId,
        'waiterName': waiterName,
        'message': message,
        'tableId': tableId,
        'tableName': tableName,
        'from': fromUser,
        'ringUntilDismissed': ringUntilDismissed,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Places calls to waiters and tracks the ones nobody has answered yet.
///
/// Delivery is best-effort push over [LanNotificationHub], but the pending
/// list is the part that makes it reliable: a call placed while the waiter's
/// phone was locked, reconnecting, or not yet logged in is replayed the moment
/// that waiter opens a stream. Without it the cashier presses "call", sees a
/// confirmation, and nothing ever rings.
class WaiterCallService {
  /// A call nobody answered stops chasing the waiter after this long. It is
  /// generous on purpose — the failure this guards against is a call from the
  /// lunch rush ringing a phone at closing time, not a waiter who took two
  /// minutes to look at their screen.
  static const Duration pendingTtl = Duration(minutes: 10);

  final Ref _ref;
  final _uuid = const Uuid();

  /// Unanswered calls, newest last, keyed by call id.
  final Map<String, WaiterCall> _pending = {};

  final StreamController<WaiterCall> _acks =
      StreamController<WaiterCall>.broadcast();

  WaiterCallService(this._ref);

  /// Calls a waiter acknowledged from their phone. The POS listens so the
  /// cashier learns someone is on the way instead of calling twice.
  Stream<WaiterCall> get acknowledgements => _acks.stream;

  String _channelFor(int waiterId) => 'waiter:$waiterId';

  /// Ring [waiterId]. Returns the number of devices the event reached — 0
  /// means the waiter has no app connected right now, and the call sits in
  /// [pendingFor] until they log in or it expires.
  ///
  /// Throws [StateError] when the feature is switched off, so a stale UI path
  /// can never push a notification the owner disabled.
  Future<({WaiterCall call, int devices})> call({
    required int waiterId,
    required String waiterName,
    String? message,
    int? tableId,
    String? tableName,
    required String fromUser,
  }) async {
    final settings = _ref.read(settingsProvider);
    if (!settings.waiterCallEnabled) {
      throw StateError('waiter_calls_disabled');
    }

    _purgeExpired();

    final trimmed = message?.trim();
    final call = WaiterCall(
      id: _uuid.v4(),
      waiterId: waiterId,
      waiterName: waiterName,
      fromUser: fromUser,
      createdAt: DateTime.now(),
      message: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      tableId: tableId,
      tableName: tableName,
      ringUntilDismissed: settings.waiterCallRingUntilDismissed,
    );
    _pending[call.id] = call;
    _ref.read(waiterNotificationInboxProvider).add(
          id: call.id,
          waiterId: waiterId,
          type: 'waiter-call',
          data: call.toPayload(),
          at: call.createdAt,
        );

    final devices = _ref
        .read(lanNotificationHubProvider)
        .publish(_channelFor(waiterId), LanEvent('waiter-call', call.toPayload()));

    // ignore: unawaited_futures
    _ref.read(activityLogServiceProvider).logWaiterCalled(
          waiterName: waiterName,
          tableName: call.tableName,
          message: call.message,
          username: fromUser,
        );

    Logger.instance.info(
        'WaiterCallService: called $waiterName (#$waiterId) → $devices device(s)'
        '${call.tableName == null ? '' : ' for table ${call.tableName}'}');

    return (call: call, devices: devices);
  }

  /// The waiter dismissed the notification on their phone.
  ///
  /// Silences the call on that waiter's *other* devices too — a waiter with a
  /// phone in their pocket and a tablet on the pass should not have to dismiss
  /// the same call twice.
  WaiterCall? acknowledge(String callId, {String? by}) {
    final call = _pending.remove(callId);
    if (call == null) return null;
    call.acknowledgedAt = DateTime.now();
    _ref
        .read(waiterNotificationInboxProvider)
        .markRead(call.waiterId, [call.id]);

    _ref.read(lanNotificationHubProvider).publish(
          _channelFor(call.waiterId),
          LanEvent('waiter-call-cancelled', {
            'callId': call.id,
            'reason': 'acknowledged',
            'by': by ?? call.waiterName,
          }),
        );

    if (!_acks.isClosed) _acks.add(call);
    Logger.instance
        .info('WaiterCallService: call ${call.id} acknowledged by ${by ?? call.waiterName}');
    return call;
  }

  /// The cashier took it back (or the waiter turned up in person).
  WaiterCall? cancel(String callId) {
    final call = _pending.remove(callId);
    if (call == null) return null;
    _ref.read(lanNotificationHubProvider).publish(
          _channelFor(call.waiterId),
          LanEvent('waiter-call-cancelled', {
            'callId': call.id,
            'reason': 'cancelled',
          }),
        );
    return call;
  }

  /// Unanswered calls for [waiterId], oldest first. Replayed on reconnect.
  List<WaiterCall> pendingFor(int waiterId) {
    _purgeExpired();
    return _pending.values.where((c) => c.waiterId == waiterId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Same list, already framed for the SSE stream.
  List<LanEvent> replayEventsFor(int waiterId) => pendingFor(waiterId)
      .map((c) => LanEvent('waiter-call', c.toPayload()))
      .toList();

  void _purgeExpired() {
    final cutoff = DateTime.now().subtract(pendingTtl);
    _pending.removeWhere((_, c) => c.createdAt.isBefore(cutoff));
  }

  void dispose() {
    _pending.clear();
    _acks.close();
  }
}

final waiterCallServiceProvider = Provider<WaiterCallService>((ref) {
  final service = WaiterCallService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Acknowledgements as they arrive from the floor, for the POS to react to.
final waiterCallAckProvider = StreamProvider<WaiterCall>(
    (ref) => ref.watch(waiterCallServiceProvider).acknowledgements);
