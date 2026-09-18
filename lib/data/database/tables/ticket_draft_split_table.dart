import 'package:drift/drift.dart';

/// How an UNPAID order is currently divided into draft tickets on the
/// payment screen, so the arrangement survives closing the screen and
/// reopening it — and a restart — instead of resetting to "one ticket, every
/// unpaid line" every time.
///
/// LOCAL ONLY, deliberately: this table is never read by
/// `DataSyncService`, never appears in a sync payload, and the server has no
/// concept of it. A draft split is a cashier's in-progress arrangement, not
/// a fact about the order — the only thing that becomes a fact, and the
/// only thing the backend needs to know about, is an actual paid [Tickets]
/// row. Splitting across two terminals working the same order is not
/// supported; the second terminal simply doesn't see the first's draft.
///
/// One row is one slice: some quantity of one `order_products` row sitting
/// in one draft ticket. A single `order_products` row can appear in several
/// rows here (split across draft tickets) with quantities summing to at most
/// its live `quantity` — never to `order_products.ticket_id`, which stays
/// reserved for PAID lines everywhere else in this app (see the many
/// `ticketId != null` checks across the codebase that read it as "is this
/// line paid").
///
/// The whole set of rows for one order is replaced together on every save —
/// see `_persistDraftSplit` in `payment_screen.dart` — never patched
/// incrementally, so there is no possible partial/inconsistent state to read
/// back. [draftIndex] is a position (0, 1, 2, …) among the order's current
/// unpaid draft tickets, not a stable identity — it is safe to renumber
/// freely because the whole set is rewritten every time it changes.
class TicketDraftSplits extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get draftIndex => integer()();
  RealColumn get quantity => real()();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
}
