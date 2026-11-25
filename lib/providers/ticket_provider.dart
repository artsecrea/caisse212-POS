import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import '../services/pending_operations_service.dart';
import 'database_providers.dart';
import 'settings_provider.dart';
import '../utils/pos_log.dart';

class TicketRepository {
  final AppDatabase _database;
  final Ref? _ref;

  TicketRepository(this._database, [this._ref]);

  DateTime _currentZDay() {
    final ref = _ref;
    if (ref != null) return ref.read(currentZDayProvider);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

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

  // Create a new ticket — auto-fills zDay from the active session if the
  // caller didn't set it explicitly.
  Future<int> createTicket(TicketsCompanion ticket) async {
    final companion = ticket.zDay.present
        ? ticket
        : ticket.copyWith(zDay: Value(_currentZDay()));
    return await _database.into(_database.tickets).insert(companion);
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
        posLog('Failed to queue ticket update operation: $e');
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
        posLog('Queued delete operation for synced ticket #$ticketId');
      } catch (e) {
        posLog('Failed to queue ticket delete operation: $e');
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
    return _enrichTickets(tickets);
  }

  // ---------------------------------------------------------------------------
  // DB-side filter / sort / paginate
  // ---------------------------------------------------------------------------

  /// Builds a WHERE expression from filter params. All column references go
  /// through `_database.tickets` so the expression can be reused across
  /// SimpleSelectStatement and selectOnly queries on the same table.
  /// Local calendar day as 'YYYY-MM-DD' — the stable prefix shared by every
  /// datetime text encoding in the DB (see [_buildFilter]).
  static String _dayStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Expression<bool> _buildFilter({
    required String statusFilter,
    required String searchQuery,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final t = _database.tickets;
    final parts = <Expression<bool>>[];

    switch (statusFilter) {
      case 'PAID':
        parts
          ..add(t.isPaid.equals(true))
          ..add(t.isCancelled.equals(false));
      case 'UNPAID':
        parts
          ..add(t.isPaid.equals(false))
          ..add(t.isCancelled.equals(false));
      case 'CANCELLED':
        parts.add(t.isCancelled.equals(true));
    }

    if (searchQuery.isNotEmpty) {
      final q = '%$searchQuery%';
      final parsedId = int.tryParse(searchQuery);
      Expression<bool> textMatch = t.num.like(q);
      if (parsedId != null) {
        // Exact match on ticket id or orderId when query is numeric
        textMatch = textMatch | t.id.equals(parsedId) | t.orderId.equals(parsedId);
      }
      final q2 = searchQuery.trim();
      final orderNo = int.tryParse(q2.startsWith('#') ? q2.substring(1) : q2);
      if (orderNo != null &&
          _ref?.read(settingsProvider).showOrderNumberInLists == true) {
        textMatch = textMatch |
            CustomExpression<bool>('order_id IN (SELECT id FROM orders '
                'WHERE session_order_no = $orderNo)');
      }
      parts.add(textMatch);
    }

    // Compare on the calendar-day prefix (YYYY-MM-DD) rather than the full
    // timestamp. Dates are stored as TEXT, and historical rows may carry the
    // legacy UTC/space encoding whose separator sorts before 'T'; a raw
    // timestamp comparison silently drops same-day rows on the range's start
    // day. The day prefix is identical across every encoding, so it's exact
    // and timezone-stable. (Column name is unambiguous — single-table query.)
    if (startDate != null) {
      parts.add(CustomExpression<bool>(
        "substr(date, 1, 10) >= '${_dayStr(startDate)}'",
      ));
    }
    if (endDate != null) {
      parts.add(CustomExpression<bool>(
        "substr(date, 1, 10) <= '${_dayStr(endDate)}'",
      ));
    }

    if (parts.isEmpty) return const Constant(true);
    return parts.reduce((a, b) => a & b);
  }

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
  }) async {
    final filter = _buildFilter(
      statusFilter: statusFilter,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );

    // ── count ──────────────────────────────────────────────────────────────
    final countExpr = _database.tickets.id.count();
    final countQ = _database.selectOnly(_database.tickets)
      ..addColumns([countExpr])
      ..where(filter);
    final countRow = await countQ.getSingle();
    final total = countRow.read(countExpr) ?? 0;

    // ── page ───────────────────────────────────────────────────────────────
    final mode = sortAscending ? OrderingMode.asc : OrderingMode.desc;
    final pageQ = _database.select(_database.tickets)
      ..where((_) => filter)
      ..limit(limit, offset: offset);

    switch (sortColumn) {
      case 0:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.id, mode: mode)]);
      case 1:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.num, mode: mode)]);
      case 2:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.orderId, mode: mode)]);
      case 3: // item count — no cheap DB expression; fall back to id order
        pageQ.orderBy([(t) => OrderingTerm(expression: t.id, mode: mode)]);
      case 4:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.amount, mode: mode)]);
      case 5:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.paymentMethod, mode: mode)]);
      case 6: // status: sort cancelled / paid flags
        pageQ.orderBy([
          (t) => OrderingTerm(expression: t.isCancelled, mode: mode),
          (t) => OrderingTerm(expression: t.isPaid, mode: mode),
        ]);
      case 7:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.date, mode: mode)]);
      default:
        pageQ.orderBy([(t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc)]);
    }

    final tickets = await pageQ.get();
    return (await _enrichTickets(tickets), total);
  }

  /// Returns all tickets matching the filters (no pagination), sorted by date
  /// ascending. Used for bulk-reprint operations.
  Future<List<Ticket>> getAllFilteredTickets({
    String statusFilter = 'ALL',
    String searchQuery = '',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final filter = _buildFilter(
      statusFilter: statusFilter,
      searchQuery: searchQuery,
      startDate: startDate,
      endDate: endDate,
    );
    return (_database.select(_database.tickets)
          ..where((_) => filter)
          ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
        .get();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Enriches a list of Ticket rows with item counts and Z-lock flags using
  /// batch queries (2 DB round-trips regardless of list size).
  Future<List<TicketWithDetails>> _enrichTickets(List<Ticket> tickets) async {
    if (tickets.isEmpty) return [];

    // Batch item counts
    final ticketIds = tickets.map((t) => t.id).toList();
    final itemCounts = <int, int>{};
    final ops = await (_database.select(_database.orderProducts)
          ..where((op) => op.ticketId.isIn(ticketIds)))
        .get();
    for (final op in ops) {
      if (op.ticketId != null) {
        itemCounts[op.ticketId!] = (itemCounts[op.ticketId!] ?? 0) + 1;
      }
    }

    // Batch Z-lock status
    final sessionIds =
        tickets.where((t) => t.sessionId != null).map((t) => t.sessionId!).toSet();
    final endedSessionIds = <int>{};
    if (sessionIds.isNotEmpty) {
      final sessions = await (_database.select(_database.cashSessions)
            ..where((s) => s.id.isIn(sessionIds.toList())))
          .get();
      for (final s in sessions) {
        if (s.status == 'ended') endedSessionIds.add(s.id);
      }
    }

    // Batch per-order extras: session order number and delivery fee
    final orderNos = <int, int>{};
    final orderIds = tickets.map((t) => t.orderId).toSet().toList();
    final orderRows = await (_database.select(_database.orders)
          ..where((o) => o.id.isIn(orderIds)))
        .get();
    final feeByOrder = <int, double>{};
    for (final o in orderRows) {
      if (o.sessionOrderNo != null) orderNos[o.id] = o.sessionOrderNo!;
      if ((o.deliveryFee ?? 0) > 0) feeByOrder[o.id] = o.deliveryFee!;
    }
    // An order's one delivery fee belongs to its first ticket (lowest id —
    // tickets are inserted in payment order), as on the printed receipt.
    // Looked up across ALL the order's tickets, not just this page.
    final feeTicketIds = <int>{};
    if (feeByOrder.isNotEmpty) {
      final siblings = await (_database.select(_database.tickets)
            ..where((t) => t.orderId.isIn(feeByOrder.keys.toList())))
          .get();
      final firstByOrder = <int, int>{};
      for (final s in siblings) {
        final held = firstByOrder[s.orderId];
        if (held == null || s.id < held) firstByOrder[s.orderId] = s.id;
      }
      feeTicketIds.addAll(firstByOrder.values);
    }

    return tickets
        .map((t) => TicketWithDetails(
              ticket: t,
              itemCount: itemCounts[t.id] ?? 0,
              isZLocked: t.sessionId != null && endedSessionIds.contains(t.sessionId),
              orderNumber: orderNos[t.orderId],
              deliveryFee:
                  feeTicketIds.contains(t.id) ? feeByOrder[t.orderId]! : 0.0,
            ))
        .toList();
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

  /// Raw SQL on purpose: a reprint must not touch `updatedAt` or wake the
  /// ticket streams, so the row is not re-pushed as edited.
  Future<void> incrementPrintCount(int ticketId) async {
    await _database.customStatement(
      'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
      [ticketId],
    );
  }
}

// Helper class for ticket with details
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

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return TicketRepository(database, ref);
});

