import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import '../services/pending_operations_service.dart';
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
    // Check if ticket was synced
    final existingTicket = await getTicketById(ticketId);
    final wasSynced = existingTicket?.isSynced ?? false;

    // Mark as not synced if changes were made
    final updatedTicket = ticket.copyWith(isSynced: const Value(false));

    await (_database.update(_database.tickets)
          ..where((tbl) => tbl.id.equals(ticketId)))
        .write(updatedTicket);

    // Queue update operation if ticket was previously synced
    if (wasSynced) {
      try {
        final pendingOpsService = PendingOperationsService(_database);
        await pendingOpsService.queueUpdate(
          entityType: 'TICKET',
          entityId: ticketId,
          serverId: ticketId,
          updateData: ticket.toColumns(false).map((k, v) => MapEntry(k, v.toString())),
        );
      } catch (e) {
        print('Failed to queue ticket update operation: $e');
      }
    }
  }

  // Delete a ticket
  Future<void> deleteTicket(int ticketId, {bool queueSyncOperation = true}) async {
    final ticket = await getTicketById(ticketId);

    // Z-report guard: refuse deletes on tickets from a closed session
    if (ticket?.sessionId != null) {
      final session = await (_database.select(_database.cashSessions)
            ..where((tbl) => tbl.id.equals(ticket!.sessionId!)))
          .getSingleOrNull();
      if (session?.status == 'ended') {
        throw Exception('Cannot delete ticket from a closed (Z-report) session');
      }
    }

    final wasSynced = ticket?.isSynced ?? false;

    // Queue delete operation if ticket was synced
    if (wasSynced && queueSyncOperation) {
      try {
        final pendingOpsService = PendingOperationsService(_database);
        await pendingOpsService.queueDelete(
          entityType: 'TICKET',
          entityId: ticketId,
          serverId: ticketId,
        );
        print('Queued delete operation for synced ticket #$ticketId');
      } catch (e) {
        print('Failed to queue ticket delete operation: $e');
      }
    }

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

    // Cache ended session IDs to avoid N+1 lookups
    final endedSessionIds = <int>{};
    final checkedSessionIds = <int>{};

    for (final ticket in tickets) {
      final items = await (_database.select(_database.orderProducts)
            ..where((tbl) => tbl.ticketId.equals(ticket.id)))
          .get();

      bool isZLocked = false;
      if (ticket.sessionId != null) {
        final sid = ticket.sessionId!;
        if (!checkedSessionIds.contains(sid)) {
          checkedSessionIds.add(sid);
          final session = await (_database.select(_database.cashSessions)
                ..where((tbl) => tbl.id.equals(sid)))
              .getSingleOrNull();
          if (session?.status == 'ended') endedSessionIds.add(sid);
        }
        isZLocked = endedSessionIds.contains(sid);
      }

      result.add(TicketWithDetails(
        ticket: ticket,
        itemCount: items.length,
        isZLocked: isZLocked,
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
  final bool isZLocked; // True when linked session is ended (Z-report closed)

  TicketWithDetails({
    required this.ticket,
    required this.itemCount,
    this.isZLocked = false,
  });
}

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return TicketRepository(database);
});

