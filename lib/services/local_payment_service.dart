import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/split_bill.dart';
import '../domain/services/payment_service.dart';
import '../providers/database_providers.dart';
import '../providers/network_provider.dart' show lastKnownOnlineStatusProvider;
import '../providers/order_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_manager_provider.dart' show kickOrderSync;
import '../providers/ticket_provider.dart';
import 'local_floor_service.dart';

/// [PaymentService] on this till's own database: the standalone till. Each
/// action is the sequence the payment screen, quick pay and the waiter
/// settlement each ran by hand.
class LocalPaymentService implements PaymentService {
  LocalPaymentService(this._ref);

  final Ref _ref;

  TicketRepository get _tickets => _ref.read(ticketRepositoryProvider);
  OrderRepository get _orders => _ref.read(orderRepositoryProvider);

  @override
  Future<PaidTicket> pay(
    int orderId, {
    required String paymentMethod,
    required double amount,
    SettledLines lines = const NoLines(),
    String? splitDetails,
    String? Function(Map<int, int> settledRows)? splitFromSettled,
    bool checkCloudNumbers = false,
  }) async {
    final num = checkCloudNumbers ? await _numberWithCloud(orderId) : null;
    final created =
        await _ref.read(ticketSettlementServiceProvider).createPaidTicket(
              orderId: orderId,
              num: num,
              paymentMethod: paymentMethod,
              amount: amount,
              splitDetails: splitDetails,
              sessionId: _ref.read(currentSessionProvider)?.id,
              // The open Z's business day, constant even after midnight.
              zDay: _ref.read(currentZDayProvider),
              lines: lines,
              splitFromSettled: splitFromSettled,
              // A part paid by amount settles no line, so no kitchen either.
              completeKitchen: lines is! NoLines &&
                  _ref.read(settingsProvider).paymentCompletesKitchen,
            );
    // Outside the payment's transaction: a claim must never be able to roll
    // back a completed payment.
    await _orders.claimOrderForCurrentUser(orderId);
    return (
      ticketId: created.ticketId,
      ticketNum: created.num,
      settledRows: created.settledRows,
    );
  }

  /// Max + 1 over this till's tickets AND, when online, the cloud's: two
  /// tills taking parts of one bill would otherwise both mint 0002, and the
  /// cloud keys tickets by (order, number). Offline the cloud cannot be
  /// asked; the bulk push is then the first place a clash could show.
  Future<String> _numberWithCloud(int orderId) async {
    var serverNums = const <String>[];
    final code = (await _orders.getOrderRow(orderId))?.code;
    if (code != null &&
        code.isNotEmpty &&
        _ref.read(lastKnownOnlineStatusProvider)) {
      final view = await _ref
          .read(apiServiceProvider)
          .fetchOrderSplit(code, timeout: const Duration(seconds: 2));
      // `usedTicketNumbers` includes cancelled tickets, which `tickets`
      // leaves out: re-using a cancelled number would upsert over that row
      // and un-cancel it. `tickets` is only the fallback for a server that
      // predates the field.
      final used = view?['usedTicketNumbers'];
      final tickets = view?['tickets'];
      if (used is List) {
        serverNums = [for (final n in used) '$n'];
      } else if (tickets is List) {
        serverNums = [
          for (final t in tickets)
            if (t is Map && t['ticketNumber'] != null) '${t['ticketNumber']}',
        ];
      }
    }
    return _ref
        .read(ticketSettlementServiceProvider)
        .nextTicketNum(orderId, serverNums: serverNums);
  }

  /// The status write is local and on the caller's path, so the table is
  /// free before the cashier is told the till is; the push is detached, and
  /// the order stays unsynced for the periodic sweep if it fails. The floor
  /// sweep clears tables stranded by orders that finished down a path that
  /// forgot to let go of theirs.
  @override
  Future<bool> completeIfSettled(int orderId) async {
    final settings = _ref.read(settingsProvider);
    final completed = await _orders.settleOrderAndFreeTable(
      orderId,
      paidStatus: settings.paidOrderDefaultStatus,
      clearTable: settings.autoClearTableAfterPaying,
    );
    await _ref
        .read(floorServiceProvider)
        .reconcile(freeOnPayment: settings.autoClearTableAfterPaying);
    if (!completed) return false;

    // Before the push, so `takenBy` goes up with the completion.
    await _orders.claimOrderForCurrentUser(orderId);
    // The division has done its job; left behind, its rows would be matched
    // against re-used row ids if the order were ever reopened.
    await _tickets.clearDraftSplit(orderId);
    kickOrderSync(_ref, orderId, 'paid order');
    return true;
  }

  @override
  Future<List<DraftSplitRow>> draftSplit(int orderId) async => [
        for (final r in await _tickets.draftSplitRows(orderId))
          (
            orderProductId: r.orderProductId,
            draftIndex: r.draftIndex,
            quantity: r.quantity,
          ),
      ];

  @override
  Future<void> saveDraftSplit(int orderId, List<DraftSplitRow> rows) =>
      _tickets.replaceDraftSplit(orderId, [
        for (final r in rows)
          TicketDraftSplitsCompanion.insert(
            orderId: orderId,
            orderProductId: r.orderProductId,
            draftIndex: r.draftIndex,
            quantity: r.quantity,
          ),
      ]);

  @override
  Future<void> clearDraftSplit(int orderId) =>
      _tickets.clearDraftSplit(orderId);

  @override
  Future<void> recordPrint(int ticketId) =>
      _tickets.incrementPrintCount(ticketId);

  @override
  Future<void> editTicket(int ticketId,
          {required String paymentMethod, required double amount}) =>
      _tickets.updateTicket(
        ticketId,
        TicketsCompanion(
          paymentMethod: Value(paymentMethod),
          amount: Value(amount),
          updatedAt: Value(DateTime.now()),
        ),
      );

  @override
  Future<void> deleteTicket(int ticketId) => _tickets.deleteTicket(ticketId);
}

/// The money actions for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final paymentServiceProvider =
    Provider<PaymentService>((ref) => LocalPaymentService(ref));
