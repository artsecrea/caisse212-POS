import '../../data/database/app_database.dart' show Ticket;

/// A ticket as the tickets screen lists it.
class TicketWithDetails {
  final Ticket ticket;
  final int itemCount;
  final bool isZLocked; // True when linked session is ended (Z-report closed)
  final int? orderNumber; // Per-session number of the ticket's order
  /// The order's delivery fee when this is the ticket that collected it,
  /// else 0. Not part of [Ticket.amount], which stays products-only.
  final double deliveryFee;

  TicketWithDetails({
    required this.ticket,
    required this.itemCount,
    this.isZLocked = false,
    this.orderNumber,
    this.deliveryFee = 0.0,
  });

  /// What to show as the ticket's amount, with or without the fee.
  double displayAmount({required bool includeDeliveryFee}) =>
      ticket.amount + (includeDeliveryFee ? deliveryFee : 0.0);
}
