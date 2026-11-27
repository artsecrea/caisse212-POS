import '../models/split_bill.dart' show DraftSplitRow;
import '../../services/ticket_settlement_service.dart'
    show NoLines, SettledLines;

export '../../services/ticket_settlement_service.dart'
    show ClaimedQuantities, NoLines, SettledLines, UnpaidLinesOf, WholeRows;

/// A paid ticket just recorded: its id and number, and the rows that now
/// carry what it paid (see `TicketSettlementService.createPaidTicket`).
typedef PaidTicket = ({int ticketId, String ticketNum, Map<int, int> settledRows});

/// What a till does with the money side of an order: its tickets and the
/// split being drawn up. An interface because tickets are shared state — on a
/// hub, the hub numbers and records them — so a standalone till answers from
/// its own database (`LocalPaymentService`) and a hub-linked one will ask the
/// hub.
///
/// Nothing here prints: an action returns what was recorded, and the till
/// prints it on its own printers.
abstract interface class PaymentService {
  /// Take [amount] by [paymentMethod] on [orderId], settling [lines], in the
  /// open session and business day, and make the order the signed-in
  /// cashier's — money changed hands at this till. A ticket that settles
  /// lines also completes their kitchen when the till is set to.
  ///
  /// The ticket is numbered after the order's others. [checkCloudNumbers]
  /// also counts the numbers the cloud already holds for the order, when
  /// online, so two tills taking parts of one bill cannot mint the same one.
  /// [splitDetails] is the ticket's split; [splitFromSettled] decides it
  /// instead once the lines are settled.
  Future<PaidTicket> pay(
    int orderId, {
    required String paymentMethod,
    required double amount,
    SettledLines lines = const NoLines(),
    String? splitDetails,
    String? Function(Map<int, int> settledRows)? splitFromSettled,
    bool checkCloudNumbers = false,
  });

  /// Settle the [due] left on [orderId] in cash, all its unpaid lines at
  /// once, and mark it paid — the close-time "pay everything" and the bulk
  /// settlement of old orders. The ticket goes into [sessionId] (the order's
  /// own, which need not be the open one) and its business day, or [zDay]
  /// when an admin chose another. Null when nothing was due.
  Future<PaidTicket?> settleAsCash(int orderId, double due,
      {int? sessionId, DateTime? zDay});

  /// Once every line of [orderId] is paid or voided: mark it paid, free its
  /// table when the till is set to, drop its draft split, and send it to the
  /// cloud. Returns whether it was completed.
  Future<bool> completeIfSettled(int orderId);

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

  /// Delete paid line [lineId], options included, from its ticket
  /// [ticketId]: the ticket goes with it when it held only that line — the
  /// answer is true — otherwise its amount is what its other lines cost.
  Future<bool> removePaidLine(int lineId, {required int ticketId});
}
