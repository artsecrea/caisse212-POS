import 'dart:convert';

import 'package:dio/dio.dart' show DioException;
import 'package:drift/drift.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import 'api_service.dart';

/// Every notification to the admin devices goes through here.
///
/// It is written to `pending_notifications` first, then sent; its row is
/// deleted as soon as the server accepts it. When the network is down the row
/// stays, and [flush] — run by every sync cycle — delivers it later. Each row
/// carries a `clientRequestId` minted once, so a retry after a send that did
/// reach the server is deduplicated there instead of notifying twice.
typedef NotificationSender = Future<void> Function({
  required String type,
  required Map<String, String> params,
  String? refId,
  required String clientRequestId,
});

class NotificationOutbox {
  final AppDatabase _database;
  final NotificationSender _sender;
  final _logger = Logger.instance;

  NotificationOutbox(this._database, ApiService api)
      : _sender = api.sendNotification;

  /// For tests: deliver through [sender] instead of the network.
  NotificationOutbox.withSender(this._database, this._sender);

  /// A notification the server keeps refusing (4xx) is dropped after this
  /// many tries, so one malformed payload cannot hold the queue forever.
  static const int maxRefusals = 5;

  /// Queue [type] and try to deliver it now. Never throws: the caller's
  /// action (closing a session, giving a discount) must not fail because a
  /// notification could not go out.
  Future<void> send(
    String type,
    Map<String, String> params, {
    String? refId,
  }) async {
    try {
      final id = await _database.into(_database.pendingNotifications).insert(
            PendingNotificationsCompanion.insert(
              type: type,
              params: jsonEncode(params),
              refId: Value(refId),
              clientRequestId: const Uuid().v4(),
            ),
          );
      final row = await (_database.select(_database.pendingNotifications)
            ..where((n) => n.id.equals(id)))
          .getSingle();
      await _deliver(row);
    } catch (e) {
      _logger.warning('Notification $type not queued: $e');
    }
  }

  /// Deliver every queued notification, oldest first. Stops at the first
  /// network failure — the rest would fail the same way. Returns how many
  /// were delivered.
  Future<int> flush() async {
    final rows = await (_database.select(_database.pendingNotifications)
          ..orderBy([(n) => OrderingTerm.asc(n.id)]))
        .get();
    var sent = 0;
    for (final row in rows) {
      final outcome = await _deliver(row);
      if (outcome == _Outcome.sent) sent++;
      if (outcome == _Outcome.offline) break;
    }
    return sent;
  }

  Future<int> pendingCount() async {
    final count = _database.pendingNotifications.id.count();
    final query = _database.selectOnly(_database.pendingNotifications)
      ..addColumns([count]);
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<_Outcome> _deliver(PendingNotification row) async {
    try {
      final params = (jsonDecode(row.params) as Map)
          .map((k, v) => MapEntry(k.toString(), v.toString()));
      await _sender(
        type: row.type,
        params: params,
        refId: row.refId,
        clientRequestId: row.clientRequestId,
      );
      await (_database.delete(_database.pendingNotifications)
            ..where((n) => n.id.equals(row.id)))
          .go();
      return _Outcome.sent;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final refused = status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429;
      if (!refused) return _Outcome.offline;
      final attempts = row.attempts + 1;
      if (attempts >= maxRefusals) {
        _logger.error(
            'Notification ${row.type} dropped after $attempts refusals: $status');
        await (_database.delete(_database.pendingNotifications)
              ..where((n) => n.id.equals(row.id)))
            .go();
      } else {
        await (_database.update(_database.pendingNotifications)
              ..where((n) => n.id.equals(row.id)))
            .write(PendingNotificationsCompanion(
          attempts: Value(attempts),
          lastError: Value('HTTP $status'),
        ));
      }
      return _Outcome.refused;
    } on FormatException catch (e) {
      // A row that cannot be decoded will never send; drop it.
      _logger.error('Notification ${row.type} dropped, unreadable: $e');
      await (_database.delete(_database.pendingNotifications)
            ..where((n) => n.id.equals(row.id)))
          .go();
      return _Outcome.refused;
    } catch (e) {
      _logger.warning('Notification ${row.type} not delivered: $e');
      return _Outcome.offline;
    }
  }
}

enum _Outcome { sent, refused, offline }
