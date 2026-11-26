import '../models/split_bill.dart' show DraftSplitRow;

/// What a till does with the money side of an order: its tickets and the
/// split being drawn up. An interface because tickets are shared state — on a
/// hub, the hub numbers and records them — so a standalone till answers from
/// its own database (`LocalPaymentService`) and a hub-linked one will ask the
/// hub.
///
/// Nothing here prints: an action returns what was recorded, and the till
/// prints it on its own printers.
abstract interface class PaymentService {
  /// The draft split saved for [orderId], so a reopened payment screen gets
  /// the cashier's arrangement back.
  Future<List<DraftSplitRow>> draftSplit(int orderId);

  /// Replace [orderId]'s draft split with [rows], all at once.
  Future<void> saveDraftSplit(int orderId, List<DraftSplitRow> rows);

  /// Drop [orderId]'s draft split once it is settled.
  Future<void> clearDraftSplit(int orderId);

  /// Count one more print of [ticketId]. Not an edit: the ticket is not
  /// re-sent to the cloud for it.
  Future<void> recordPrint(int ticketId);

  /// Correct a ticket's payment method and amount after the fact.
  Future<void> editTicket(int ticketId,
      {required String paymentMethod, required double amount});

  /// Delete a ticket and unlink its lines, which become unpaid again.
  Future<void> deleteTicket(int ticketId);
}
