import 'package:drift/drift.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/booking_models.dart';
import 'api_service.dart';
import 'data_sync_service.dart';
import 'pending_operations_service.dart';

/// Thrown when a booking action is attempted with no connection.
///
/// Deliberately an error rather than a queued operation. A slot belongs to the
/// shop's one diary, held by the server; a terminal that promised a 3pm chair
/// while offline could not know another till had just sold it. So the booking
/// calls fail loudly and the UI tells staff to reconnect — walk-ins, which
/// claim no slot, keep selling through the ordinary offline order path.
class OfflineBookingException implements Exception {
  const OfflineBookingException();
  @override
  String toString() => 'Reconnect to book appointments';
}

/// Thrown when the line to be booked has no server identity yet — its order
/// has not reached the backend, so there is nothing for `/schedule` to address.
/// The caller's job is to sync the order first, which is why the appointment
/// flow insists on being online from the moment the order is created.
class UnsyncedLineException implements Exception {
  const UnsyncedLineException();
  @override
  String toString() => 'Sync the order before booking its slot';
}

/// The one path through which a slot is claimed or released.
///
/// Claiming is online-only and is **never** queued; releasing is offline-safe
/// and is. That asymmetry is the contract: a claim replayed against stale data
/// double-books a chair, a release replayed late only ever hands capacity back.
///
/// On a claim the local plan columns are written **after** the server accepts,
/// never before — an optimistic write the server then rejects would leave the
/// shop's agenda showing an appointment nobody owns.
class BookingService {
  final ApiService _api;
  final AppDatabase _db;
  final DataSyncService _sync;
  final PendingOperationsService _pending;
  final bool Function() _isOnline;
  final _logger = Logger.instance;

  BookingService(
      this._api, this._db, this._sync, this._pending, this._isOnline);

  bool get canBook => _isOnline();

  void _requireOnline() {
    if (!_isOnline()) throw const OfflineBookingException();
  }

  /// The server's id for a local line, resolving it from the backend if this
  /// device has not learned it yet. Null when the order is not on the server.
  Future<int?> resolveServerLineId(int localOrderProductId) async {
    final row = await (_db.select(_db.orderProducts)
          ..where((t) => t.id.equals(localOrderProductId)))
        .getSingleOrNull();
    if (row == null) return null;
    if (row.serverId != null) return row.serverId;

    final order = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(row.orderId)))
        .getSingleOrNull();
    final code = order?.code;
    if (code == null || code.isEmpty) return null;

    await _sync.ensureServerLineIds(code, row.orderId);

    final refreshed = await (_db.select(_db.orderProducts)
          ..where((t) => t.id.equals(localOrderProductId)))
        .getSingleOrNull();
    return refreshed?.serverId;
  }

  /// Claim a slot. Throws [OfflineBookingException], [UnsyncedLineException],
  /// [ScheduleConflict] (409 — slot gone, refetch availability and let staff
  /// pick again) or [ScheduleValidationError] (400).
  ///
  /// [localOrderProductId] is optional because the agenda can be showing a
  /// booking whose order this terminal never held; when present the local plan
  /// columns are kept in step with what the server just accepted.
  Future<void> schedule({
    required int serverOrderProductId,
    int? localOrderProductId,
    required DateTime planStartAt,
    DateTime? planEndAt,
    int? planWaiterId,
    int? planResourceId,
  }) async {
    _requireOnline();

    await _api.patchSchedule(
      serverOrderProductId,
      planStartAt: planStartAt,
      planEndAt: planEndAt,
      planWaiterId: planWaiterId,
      planResourceId: planResourceId,
    );

    if (localOrderProductId != null) {
      await (_db.update(_db.orderProducts)
            ..where((t) => t.id.equals(localOrderProductId)))
          .write(OrderProductsCompanion(
        planStartAt: Value(planStartAt),
        // The server derives the end from the service duration when we omit
        // it; mirroring null locally would leave the agenda unable to draw the
        // block, so fall back to the start until the next agenda pull.
        planEndAt: Value(planEndAt ?? planStartAt),
        planWaiterId: Value(planWaiterId),
        planResourceId: Value(planResourceId),
        updatedAt: Value(DateTime.now()),
      ));
    }
    _logger.info('Booked line #$serverOrderProductId at $planStartAt');
  }

  /// Release a slot.
  ///
  /// Unlike [schedule] this is offline-safe and **is** queued: freeing a slot
  /// only ever gives capacity back, so replaying it late can wrong nobody. The
  /// asymmetry is the whole point of the contract — claiming a slot on stale
  /// data double-books a chair, releasing one on stale data does not.
  ///
  /// The local plan fields are cleared immediately either way, so the agenda
  /// stops showing a booking the shop has already let go.
  Future<void> unschedule({
    required int serverOrderProductId,
    int? localOrderProductId,
  }) async {
    if (_isOnline()) {
      await _api.deleteSchedule(serverOrderProductId);
    } else {
      await _pending.queueDelete(
        entityType: 'SCHEDULE',
        entityId: localOrderProductId ?? serverOrderProductId,
        serverId: serverOrderProductId,
      );
      _logger.info(
          'Queued unschedule of line #$serverOrderProductId for reconnect');
    }

    if (localOrderProductId != null) {
      await (_db.update(_db.orderProducts)
            ..where((t) => t.id.equals(localOrderProductId)))
          .write(const OrderProductsCompanion(
        planStartAt: Value(null),
        planEndAt: Value(null),
        planWaiterId: Value(null),
        planResourceId: Value(null),
      ));
    }
    await _sync.removeCachedBooking(serverOrderProductId);
  }
}
