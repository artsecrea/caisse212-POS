import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/split_bill.dart';
import '../domain/services/payment_service.dart';
import '../providers/ticket_provider.dart';

/// [PaymentService] on this till's own database: the standalone till. Each
/// action is the [TicketRepository] call the screens made.
class LocalPaymentService implements PaymentService {
  LocalPaymentService(this._tickets);

  final TicketRepository _tickets;

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
final paymentServiceProvider = Provider<PaymentService>(
    (ref) => LocalPaymentService(ref.watch(ticketRepositoryProvider)));
