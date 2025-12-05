import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'database_providers.dart';

class TicketRepository {
  final AppDatabase _database;

  TicketRepository(this._database);

  // Get all tickets
  Future<List<Ticket>> getAllTickets() async {
    return await _database.select(_database.tickets).get();
  }

  // Get tickets by order ID
  Future<List<Ticket>> getTicketsByOrderId(int orderId) async {
    return await (_database.select(_database.tickets)
          ..where((tbl) => tbl.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
  }

  // Get ticket by ID
  Future<Ticket?> getTicketById(int id) async {
    return await (_database.select(_database.tickets)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  // Create a new ticket
  Future<int> createTicket(TicketsCompanion ticket) async {
    return await _database.into(_database.tickets).insert(ticket);
  }

  // Update a ticket
  Future<void> updateTicket(int ticketId, TicketsCompanion ticket) async {
    await (_database.update(_database.tickets)
          ..where((tbl) => tbl.id.equals(ticketId)))
        .write(ticket);
  }

  // Delete a ticket
  Future<void> deleteTicket(int ticketId) async {
    // First, set all order products with this ticketId to null
    await (_database.update(_database.orderProducts)
          ..where((tbl) => tbl.ticketId.equals(ticketId)))
        .write(const OrderProductsCompanion(
          ticketId: Value(null),
        ));

    // Then delete the ticket
    await (_database.delete(_database.tickets)
          ..where((tbl) => tbl.id.equals(ticketId)))
        .go();
  }

  // Get tickets with full details (including items)
  Future<List<TicketWithDetails>> getTicketsWithDetails() async {
    final tickets = await getAllTickets();
    final List<TicketWithDetails> result = [];

    for (final ticket in tickets) {
      final items = await (_database.select(_database.orderProducts)
            ..where((tbl) => tbl.ticketId.equals(ticket.id)))
          .get();

      result.add(TicketWithDetails(
        ticket: ticket,
        itemCount: items.length,
      ));
    }

    return result;
  }

  // Get tickets grouped by order
  Future<Map<int, List<Ticket>>> getTicketsGroupedByOrder() async {
    final tickets = await getAllTickets();
    final Map<int, List<Ticket>> grouped = {};

    for (final ticket in tickets) {
      if (!grouped.containsKey(ticket.orderId)) {
        grouped[ticket.orderId] = [];
      }
      grouped[ticket.orderId]!.add(ticket);
    }

    return grouped;
  }

  // Mark ticket as paid
  Future<void> markTicketAsPaid(int ticketId) async {
    await (_database.update(_database.tickets)
          ..where((tbl) => tbl.id.equals(ticketId)))
        .write(TicketsCompanion(
          isPaid: const Value(true),
          updatedAt: Value(DateTime.now()),
        ));
  }

  // Increment print count
  Future<void> incrementPrintCount(int ticketId) async {
    final ticket = await getTicketById(ticketId);
    if (ticket != null) {
      await (_database.update(_database.tickets)
            ..where((tbl) => tbl.id.equals(ticketId)))
          .write(TicketsCompanion(
            printCount: Value(ticket.printCount + 1),
            updatedAt: Value(DateTime.now()),
          ));
    }
  }
}

// Helper class for ticket with details
class TicketWithDetails {
  final Ticket ticket;
  final int itemCount;

  TicketWithDetails({
    required this.ticket,
    required this.itemCount,
  });
}

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return TicketRepository(database);
});

