import '../../data/database/app_database.dart' show OrderProduct, Ticket;
import '../models/ticket_read_models.dart';

/// What the screens read about tickets. An interface because, linked to a
/// hub, a till shows the hub's tickets: standalone, it reads its own
/// database (`TicketRepository`).
abstract interface class TicketQueries {
  /// How many draft tickets [orderId]'s split has, as it changes: distinct
  /// `draft_index` values, not rows — one draft ticket holds as many rows as
  /// it has lines, and a line divided across two tickets has a row in each.
  Stream<int> watchDraftTicketCount(int orderId);

  Future<Ticket?> getTicketById(int id);

  Future<List<Ticket>> getTicketsByOrderId(int orderId);

  /// Every ticket of [orderIds], in any state — the caller sorts paid from
  /// cancelled itself.
  Future<List<Ticket>> ticketsForOrders(List<int> orderIds);

  /// The 50 most recent paid tickets of [orderIds]. Capped because it feeds
  /// a profile's payment history; older history lives in the orders screen.
  /// A cancelled ticket still counts when it is marked paid.
  Future<List<Ticket>> paidTicketsForOrders(List<int> orderIds);

  /// Returns one page of tickets (already enriched with item count + Z-lock)
  /// and the total count of matching rows.
  Future<(List<TicketWithDetails>, int)> getTicketsPage({
    required int offset,
    required int limit,
    String statusFilter = 'ALL',
    String searchQuery = '',
    DateTime? startDate,
    DateTime? endDate,
    int sortColumn = 0,
    bool sortAscending = false,
  });

  /// Returns all tickets matching the filters (no pagination), sorted by date
  /// ascending. Used for bulk-reprint operations.
  Future<List<Ticket>> getAllFilteredTickets({
    String statusFilter = 'ALL',
    String searchQuery = '',
    DateTime? startDate,
    DateTime? endDate,
  });

  /// The order lines [ticketId] paid for.
  Future<List<OrderProduct>> linesOfTicket(int ticketId);

  /// [ticketId]'s lines in the shape the receipt printer takes for a reprint.
  /// A component since removed from the catalogue is left off the paper; a
  /// removed product still prints, as 'Unknown Product'.
  Future<List<Map<String, dynamic>>> printItemsOf(int ticketId);

  /// VAT carried by [ticketId]'s lines, summed the same way
  /// `OrderItem.totalTva` does (`unitaryTva * quantity`) so a reprint shows
  /// the figure the original receipt showed.
  Future<double> tvaTotalOf(int ticketId);

  /// The reductions printed on [ticketId]'s receipt: each line's catalogue and
  /// manual discount, plus its share of the order percentage — the same two
  /// parts the payment screen printed when the ticket was cut.
  ///
  /// Every line on the ticket counts, cancelled or not: it was paid for.
  Future<double> discountTotalOf(
      int ticketId, double orderDiscountPercentage);

  /// The delivery fee to show on a REPRINT of [ticketId], or null.
  ///
  /// An order carries one delivery charge, collected on whichever ticket
  /// settled first — which is the lowest-id ticket on that order, since ticket
  /// rows are inserted in payment order. Reprinting any later ticket of a
  /// divided order must not repeat the fee, or two receipts would each claim
  /// to have collected it. Every ticket of the order competes for "first",
  /// cancelled or unpaid ones included.
  Future<double?> deliveryFeeForTicket(int orderId, int ticketId);
}
