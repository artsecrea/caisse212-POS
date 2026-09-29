import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:loggecrea/loggecrea.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/error_text.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/order_models.dart';
import '../../core/enums.dart';
import '../../providers/order_provider.dart';
import '../../providers/booking_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/permission_service.dart';
import '../../services/activity_log_service.dart';
import '../widgets/print_status_indicator.dart';
import '../widgets/cash_pad.dart';
import '../widgets/print_options_dialog.dart';

/// The delivery fee a ticket still has to collect.
///
/// An order carries at most one delivery charge however many ways it is
/// divided: it rides the first settlement, so once anything on the order is
/// paid the remaining tickets collect nothing. Charging it per ticket would
/// bill a split table for delivery two or three times over.
double deliveryFeeToCollect(double orderFee, List<TicketData> allTickets) {
  if (orderFee <= 0) return 0.0;
  return allTickets.any((t) => t.isPaid) ? 0.0 : orderFee;
}

/// What the calculator should be pre-filled with when [ticket] becomes the
/// active one — the exact amount still owed, so a plain cash sale needs no
/// typing at all — or `null` when there is nothing sensible to pre-fill.
///
/// Null covers: no ticket selected, a ticket that is already paid (nothing
/// left to tender), an empty ticket, and the pathological case of a payable
/// amount that comes out to zero or less — each of those should open the
/// calculator blank, exactly as it always has, rather than pre-fill a
/// meaningless figure.
///
/// Pure — no `ref`, no widget state. Exercised directly in
/// `test/exact_amount_default_test.dart`.
double? exactAmountDueFor(
  TicketData? ticket,
  List<TicketData> allTickets, {
  required double orderDeliveryFee,
}) {
  if (ticket == null || ticket.isPaid || ticket.items.isEmpty) return null;
  final payable =
      ticket.total + deliveryFeeToCollect(orderDeliveryFee, allTickets);
  return payable > 0 ? payable : null;
}

/// One saved slice of a draft ticket split — see [TicketDraftSplits] for
/// what the fields mean. A plain record rather than the Drift row type so
/// [reconstructUnpaidTickets] has no database dependency and is trivial to
/// feed by hand in a test.
typedef DraftSplitRow = ({
  int orderProductId,
  int draftIndex,
  double quantity,
});

/// Rebuild the unpaid tickets from a saved draft split, or the plain
/// one-ticket default when [draftRows] is empty.
///
/// A stale claim — a [draftRows] entry naming an id [unpaidItems] no longer
/// has, or more quantity than the item still carries (the order was edited
/// elsewhere since the split was saved) — is dropped rather than trusted.
/// Whatever a row's claim leaves unaccounted for falls through to the
/// "leftover" bucket and lands on the first reconstructed ticket, the same
/// place the payment screen's own `_removeTicket`/`_commitAndPrune` already
/// send an orphaned line.
///
/// Pure — no DB, no widget, no `ref`. Exercised directly in
/// `test/ticket_draft_split_test.dart`.
List<TicketData> reconstructUnpaidTickets(
  List<OrderItem> unpaidItems,
  List<DraftSplitRow> draftRows, {
  required TransactionType defaultMethod,
  required double discountPercentage,
}) {
  TicketData wholeTicket() => TicketData(
        items: unpaidItems.map(TicketLine.whole).toList(),
        paymentMethod: defaultMethod,
        discountPercentage: discountPercentage,
      );

  if (unpaidItems.isEmpty) return [];
  if (draftRows.isEmpty) return [wholeTicket()];

  final byRowId = {
    for (final item in unpaidItems)
      if (item.id != null) item.id!: item,
  };
  final remaining = {
    for (final entry in byRowId.entries) entry.key: entry.value.quantity,
  };

  final byIndex = <int, List<DraftSplitRow>>{};
  for (final row in draftRows) {
    if (!byRowId.containsKey(row.orderProductId)) continue;
    final left = remaining[row.orderProductId] ?? 0.0;
    if (row.quantity <= 0 || row.quantity > left + _qtyEpsilon) continue;
    byIndex.putIfAbsent(row.draftIndex, () => []).add(row);
    remaining[row.orderProductId] = left - row.quantity;
  }

  final tickets = <TicketData>[];
  for (final idx in byIndex.keys.toList()..sort()) {
    final lines = [
      for (final row in byIndex[idx]!)
        TicketLine(
          item: byRowId[row.orderProductId]!.copyWith(quantity: row.quantity),
          sources: [(rowId: row.orderProductId, quantity: row.quantity)],
        ),
    ];
    tickets.add(TicketData(
      items: lines,
      paymentMethod: defaultMethod,
      discountPercentage: discountPercentage,
    ));
  }

  final leftoverLines = [
    for (final entry in remaining.entries)
      if (entry.value > _qtyEpsilon)
        TicketLine(
          item: byRowId[entry.key]!.copyWith(quantity: entry.value),
          sources: [(rowId: entry.key, quantity: entry.value)],
        ),
  ];
  if (leftoverLines.isEmpty) return tickets;
  if (tickets.isEmpty) {
    return [
      TicketData(
        items: leftoverLines,
        paymentMethod: defaultMethod,
        discountPercentage: discountPercentage,
      ),
    ];
  }
  tickets[0] = tickets[0].copyWith(items: [...tickets[0].items, ...leftoverLines]);
  return tickets;
}

/// Quantities are doubles because weighed goods exist; comparisons against
/// zero have to tolerate the rounding that division introduces.
const double _qtyEpsilon = 0.0001;

/// A claim on one `order_products` row: how much of its quantity a ticket
/// line is drawing from it.
typedef LineSource = ({int rowId, double quantity});

/// One line as the cashier sees it on a ticket.
///
/// Dividing and merging on this screen are **provisional**: they rearrange
/// lines in memory and record which persisted rows each line draws from, but
/// write nothing. The database learns about the arrangement only when a
/// ticket is actually paid, at which point [sources] says exactly which rows
/// to settle and for how much. Backing out of the screen therefore leaves the
/// order exactly as it was found.
///
/// Invariant: `item.quantity == sum of sources' quantities`. Everything that
/// reshapes a line has to keep that true, or the order can be paid for a
/// quantity it does not contain.
class TicketLine {
  final OrderItem item;
  final List<LineSource> sources;

  const TicketLine({required this.item, required this.sources});

  /// A line that still maps 1:1 onto its persisted row — how every line
  /// starts, before any division.
  factory TicketLine.whole(OrderItem item) => TicketLine(
        item: item,
        sources: item.id == null
            ? const []
            : [(rowId: item.id!, quantity: item.quantity)],
      );

  TicketLine copyWith({OrderItem? item, List<LineSource>? sources}) =>
      TicketLine(item: item ?? this.item, sources: sources ?? this.sources);

  /// Cut [take] units off this line, returning `(kept, taken)`.
  ///
  /// Sources are consumed in order so the two halves claim disjoint quantity
  /// and neither can be settled twice.
  (TicketLine, TicketLine) split(double take) {
    final kept = <LineSource>[];
    final taken = <LineSource>[];
    var outstanding = take;

    for (final source in sources) {
      if (outstanding <= _qtyEpsilon) {
        kept.add(source);
      } else if (source.quantity <= outstanding + _qtyEpsilon) {
        taken.add(source);
        outstanding -= source.quantity;
      } else {
        taken.add((rowId: source.rowId, quantity: outstanding));
        kept.add((rowId: source.rowId, quantity: source.quantity - outstanding));
        outstanding = 0;
      }
    }

    return (
      copyWith(item: item.copyWith(quantity: item.quantity - take), sources: kept),
      copyWith(item: item.copyWith(quantity: take), sources: taken),
    );
  }

  /// Absorb [other] into this line. Only ever called for lines the drag
  /// target has already accepted, which requires identical unit economics —
  /// otherwise one line's price would silently reprice the other's units.
  TicketLine mergedWith(TicketLine other) => TicketLine(
        item: item.copyWith(quantity: item.quantity + other.item.quantity),
        sources: [...sources, ...other.sources],
      );
}

/// Whether two lines describe the same thing at the same price, and can
/// therefore be shown — and charged — as one.
///
/// Product and variant are not enough: merging a line carrying extra
/// components, a note, or a different discount into a plain one would charge
/// the plain price for every unit and lose the modifiers. Serial lines never
/// combine — each names one physical unit.
bool canCombineLines(OrderItem a, OrderItem b) {
  if (a.isSerialLine || b.isSerialLine) return false;
  if (a.productId != b.productId || a.variantId != b.variantId) return false;
  if ((a.finalPrice - b.finalPrice).abs() > 0.001) return false;
  if ((a.discount - b.discount).abs() > 0.001) return false;
  if ((a.manualDiscount - b.manualDiscount).abs() > 0.001) return false;
  if ((a.tva - b.tva).abs() > 0.001) return false;
  if ((a.note ?? '') != (b.note ?? '')) return false;
  return _componentSignature(a) == _componentSignature(b);
}

String _componentSignature(OrderItem item) {
  final parts = item.components
      .map((c) => '${c.componentId}:${c.quantity}:${c.price}:${c.isSpecial}')
      .toList()
    ..sort();
  return parts.join('|');
}

/// Ticket data model for split payments
class TicketData {
  final int? ticketId;
  final String? ticketNum;
  final List<TicketLine> items;
  final TransactionType paymentMethod;
  final bool isPaid;
  final int printCount;
  final double discountPercentage;

  TicketData({
    this.ticketId,
    this.ticketNum,
    required this.items,
    this.paymentMethod = TransactionType.cash,
    this.isPaid = false,
    this.printCount = 0,
    this.discountPercentage = 0.0,
  });

  TicketData copyWith({
    int? ticketId,
    String? ticketNum,
    List<TicketLine>? items,
    TransactionType? paymentMethod,
    bool? isPaid,
    int? printCount,
    double? discountPercentage,
  }) {
    return TicketData(
      ticketId: ticketId ?? this.ticketId,
      ticketNum: ticketNum ?? this.ticketNum,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaid: isPaid ?? this.isPaid,
      printCount: printCount ?? this.printCount,
      discountPercentage: discountPercentage ?? this.discountPercentage,
    );
  }

  double get subtotal => items.fold<double>(
      0.0, (sum, l) => sum + (l.item.subtotalPerItem * l.item.quantity));
  double get itemDiscount =>
      items.fold<double>(0.0, (sum, l) => sum + l.item.totalDiscount);
  double get totalTva =>
      items.fold<double>(0.0, (sum, l) => sum + l.item.totalTva);

  double get manualDiscountAmount {
    final base = (subtotal + totalTva - itemDiscount);
    if (base <= 0 || discountPercentage <= 0) return 0.0;
    return base * (discountPercentage / 100.0);
  }

  double get total {
    final result = (subtotal + totalTva - itemDiscount) - manualDiscountAmount;
    return result < 0 ? 0.0 : result;
  }
}

/// Calculator state
class CalculatorState {
  final String display;
  final double enteredAmount;

  CalculatorState({
    this.display = '0',
    this.enteredAmount = 0.0,
  });

  CalculatorState copyWith({
    String? display,
    double? enteredAmount,
  }) {
    return CalculatorState(
      display: display ?? this.display,
      enteredAmount: enteredAmount ?? this.enteredAmount,
    );
  }
}

// Providers — autoDispose so state resets when dialog closes
final ticketsProvider = StateProvider.autoDispose<List<TicketData>>((ref) => []);
final calculatorProvider = StateProvider.autoDispose<CalculatorState>((ref) => CalculatorState());
final selectedTicketProvider = StateProvider.autoDispose<int?>((ref) => null);

/// Modern Payment Screen - Rebuilt for touch screens
class PaymentScreen extends ConsumerStatefulWidget {
  final CurrentOrder order;

  /// Force the ticket-division grid open for this visit, regardless of
  /// [AppSettings.alwaysShowTicketSplit] or how many tickets the order
  /// starts with — the long-press gesture on Proceed/Pay that lets a
  /// cashier divide an order into tickets before paying anything.
  final bool forceSplitOpen;

  const PaymentScreen({
    super.key,
    required this.order,
    this.forceSplitOpen = false,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _logger = Logger.instance;
  bool _isProcessing = false;

  /// Cashier's explicit show/hide of the ticket-division grid for this visit.
  /// `null` means "no opinion yet" and the default rule applies: always-on per
  /// settings, or auto-shown once the order actually has more than one ticket.
  bool? _splitPanelOverride;

  /// The vertical list of ticket cards in [_buildTicketsArea] — keyed and
  /// controller-driven so a drag can auto-scroll it, which a plain
  /// [ListView] does not do for itself. [_ticketsListKey] measures the
  /// list's own on-screen bounds; a `GlobalKey` on the `Expanded` around it
  /// would measure the wrong box, since `Expanded` has no size of its own to
  /// report.
  final ScrollController _ticketsScrollController = ScrollController();
  final GlobalKey _ticketsListKey = GlobalKey();

  /// True while a draft-ticket slip is being sent to the printer. Guards
  /// against a double tap queuing the same slip twice — a printed bill handed
  /// to a customer twice is a real-world mess, not just a wasted job.
  bool _isPrintingDraft = false;

  @override
  void initState() {
    super.initState();
    if (widget.forceSplitOpen) _splitPanelOverride = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeTickets();
    });
  }

  @override
  void dispose() {
    _ticketsScrollController.dispose();
    super.dispose();
  }

  /// Auto-scroll the tickets list while a ticket line is being dragged near
  /// its top or bottom edge.
  ///
  /// Called from every draggable line's `onDragUpdate` — a plain [ListView]
  /// has no such affordance on its own, so dragging a line toward a ticket
  /// currently below (or above) the fold otherwise strands the cashier
  /// mid-gesture with no way to reach it. A no-op once the list has nothing
  /// left to scroll toward in that direction.
  void _autoScrollTicketsOnDrag(Offset globalPosition) {
    if (!_ticketsScrollController.hasClients) return;
    final box =
        _ticketsListKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    const edgeZone = 60.0; // px from the edge that starts scrolling
    const step = 16.0; // px nudged per drag-update tick

    double delta = 0;
    if (globalPosition.dy < top + edgeZone) {
      delta = -step;
    } else if (globalPosition.dy > bottom - edgeZone) {
      delta = step;
    }
    if (delta == 0) return;

    final target = (_ticketsScrollController.offset + delta)
        .clamp(0.0, _ticketsScrollController.position.maxScrollExtent);
    if (target != _ticketsScrollController.offset) {
      _ticketsScrollController.jumpTo(target);
    }
  }

  Future<void> _initializeTickets() async {
    final items = widget.order.items;

    // Group items by ticketId
    final Map<int?, List<OrderItem>> grouped = {};
    for (var item in items) {
      grouped.putIfAbsent(item.ticketId, () => []).add(item);
    }

    final List<TicketData> tickets = [];

    // Create tickets for paid items
    grouped.forEach((ticketId, ticketItems) {
      if (ticketId != null) {
        // Generate ticket number from ID and get payment method from order data
        final ticketNumStr = ticketId.toString().padLeft(4, '0');

        tickets.add(TicketData(
          ticketId: ticketId,
          ticketNum: ticketNumStr,
          items: ticketItems.map(TicketLine.whole).toList(),
          paymentMethod: TransactionType.cash, // Will be overridden by actual payment method if available
          isPaid: true,
          discountPercentage: widget.order.discountPercentage,
        ));
      }
    });

    // Unpaid items: rebuild whatever draft split the cashier last saved for
    // this order (see [TicketDraftSplits]) rather than always collapsing
    // everything back into one ticket. An order nobody has split yet, or
    // whose draft turns out stale, falls through to that same one-ticket
    // default inside the helper.
    final unpaidItems = grouped[null] ?? [];
    if (unpaidItems.isNotEmpty) {
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.addAll(
        await _reconstructUnpaidTickets(unpaidItems, defaultMethod),
      );
    }

    // Ensure at least one ticket exists
    if (tickets.isEmpty) {
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.add(TicketData(
        items: [],
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    if (!mounted) return;
    ref.read(ticketsProvider.notifier).state = tickets;

    // Land on a ticket rather than on the "select a ticket" placeholder: the
    // first unpaid one is what the cashier wants in every ordinary case, and
    // falling back to index 0 means the payment pad is never dead on arrival.
    final unpaidIndices = [
      for (int i = 0; i < tickets.length; i++)
        if (!tickets[i].isPaid) i,
    ];
    final initialIndex =
        unpaidIndices.isNotEmpty ? unpaidIndices.first : (tickets.isEmpty ? null : 0);
    ref.read(selectedTicketProvider.notifier).state = initialIndex;

    _resetCalculatorFor(initialIndex, tickets);
  }

  /// Rebuild the unpaid tickets from whatever draft split was last saved for
  /// this order (see [TicketDraftSplits]), or the plain one-ticket default
  /// when there is no saved draft. The comparison against what the order
  /// actually still holds — dropping a stale claim rather than trusting it —
  /// is [reconstructUnpaidTickets]'s job; this is just the DB fetch.
  Future<List<TicketData>> _reconstructUnpaidTickets(
    List<OrderItem> unpaidItems,
    TransactionType defaultMethod,
  ) async {
    final orderId = widget.order.orderId;
    var draftRows = const <DraftSplitRow>[];
    if (orderId != null) {
      try {
        final database = ref.read(databaseProvider);
        final rows = await (database.select(database.ticketDraftSplits)
              ..where((t) => t.orderId.equals(orderId)))
            .get();
        draftRows = [
          for (final r in rows)
            (
              orderProductId: r.orderProductId,
              draftIndex: r.draftIndex,
              quantity: r.quantity,
            ),
        ];
      } catch (e) {
        _logger.error('Failed to load draft ticket split: $e');
      }
    }
    return reconstructUnpaidTickets(
      unpaidItems,
      draftRows,
      defaultMethod: defaultMethod,
      discountPercentage: widget.order.discountPercentage,
    );
  }

  /// Save the current unpaid-ticket arrangement as this order's draft split,
  /// replacing whatever was saved before it. See [TicketDraftSplits] — local
  /// only, and rewritten as a whole set rather than patched.
  ///
  /// Fire-and-forget by every call site: a save failure here must never
  /// block or crash the payment flow. Worst case, the arrangement resets to
  /// the plain one-ticket default next time the screen opens — exactly what
  /// happened every time, before this existed.
  Future<void> _persistDraftSplit(List<TicketData> tickets) async {
    final orderId = widget.order.orderId;
    if (orderId == null) return;
    try {
      final database = ref.read(databaseProvider);
      await database.transaction(() async {
        await (database.delete(database.ticketDraftSplits)
              ..where((t) => t.orderId.equals(orderId)))
            .go();
        final unpaid = tickets.where((t) => !t.isPaid).toList();
        for (var idx = 0; idx < unpaid.length; idx++) {
          for (final line in unpaid[idx].items) {
            for (final source in line.sources) {
              if (source.quantity <= 0) continue;
              await database.into(database.ticketDraftSplits).insert(
                    TicketDraftSplitsCompanion.insert(
                      orderId: orderId,
                      orderProductId: source.rowId,
                      draftIndex: idx,
                      quantity: source.quantity,
                    ),
                  );
            }
          }
        }
      });
    } catch (e) {
      _logger.error('Failed to persist draft ticket split: $e');
    }
  }

  /// Update the tickets provider AND persist the new arrangement as this
  /// order's draft split. The one path every user-driven change to
  /// [ticketsProvider] should go through — see [_persistDraftSplit].
  void _setTickets(List<TicketData> tickets) {
    ref.read(ticketsProvider.notifier).state = tickets;
    unawaited(_persistDraftSplit(tickets));
  }

  /// Whether the ticket-division grid is on screen.
  ///
  /// Shown by default: the grid is the whole point of the screen on anything
  /// bigger than a one-item sale. It only stands down when there is genuinely
  /// nothing to divide — a lone unit — where it would be an empty gesture
  /// stealing width from the pad.
  bool _splitVisible(List<TicketData> tickets, AppSettings settings) {
    // A hide override can never strand tickets off screen: once the order is
    // divided, the grid is the only way to reach the other tickets.
    if (tickets.length > 1) return true;
    if (_splitPanelOverride != null) return _splitPanelOverride!;
    if (settings.alwaysShowTicketSplit) return true;
    return _divisibleUnits > 1;
  }

  /// The delivery fee this payment should collect.
  ///
  /// An order carries at most one delivery charge no matter how many ways the
  /// bill is divided, so it rides on whichever ticket settles FIRST and is
  /// zero from then on. Keying off "nothing paid yet" rather than a fixed
  /// ticket index means it still gets collected when the cashier settles the
  /// tickets out of order.
  ///
  /// It is added to what the cashier collects, never to `TicketData.total` —
  /// the ticket row written to the database stays a products figure, which is
  /// what keeps the fee out of every sales and Z total.
  double _deliveryFeeFor(List<TicketData> allTickets) =>
      deliveryFeeToCollect(widget.order.deliveryFeeAmount, allTickets);

  // ── Division constraints ────────────────────────────────────────────────
  //
  // Two independent ceilings, both enforced at every entry point (New ticket,
  // custom divide) rather than only in the UI, because splitting
  // writes real `order_products` rows — an unchecked path leaves the database
  // divided in a way the screen then refuses to show.

  /// How many separate tickets the still-unpaid part of the order could
  /// possibly occupy: one per unit. Fractional lines (weighed goods) count as
  /// one — half a kilo can't be divided across two payers by tapping.
  int get _divisibleUnits {
    final tickets = ref.read(ticketsProvider);
    var units = 0;
    for (final ticket in tickets) {
      if (ticket.isPaid) continue;
      for (final line in ticket.items) {
        units += line.item.quantity >= 1 ? line.item.quantity.floor() : 1;
      }
    }
    return units;
  }

  int get _unpaidTicketCount =>
      ref.read(ticketsProvider).where((t) => !t.isPaid).length;

  int get _maxTickets => ref.read(settingsProvider).maxSplitTickets;

  /// `null` when another ticket is allowed, otherwise the reason to show.
  String? _blockNewTicketReason(AppLocalizations l10n) {
    final tickets = ref.read(ticketsProvider);
    if (tickets.any((t) => !t.isPaid && t.items.isEmpty)) {
      return l10n.translate('fill_empty_ticket_first');
    }
    if (tickets.length >= _maxTickets) {
      return l10n
          .translate('max_tickets_reached')
          .replaceAll('{0}', '$_maxTickets');
    }
    if (_unpaidTicketCount >= _divisibleUnits) {
      return l10n.translate('no_items_left_to_divide');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final settings = ref.watch(settingsProvider);
    // Watched HERE, not only inside the payment panel that actually reads it.
    //
    // `calculatorProvider` is autoDispose, and on the first frame no ticket
    // is selected yet — so `_buildPaymentPanel` returns its placeholder,
    // nothing watches the calculator, and the pre-filled exact amount that
    // `_initializeTickets` writes from its post-frame callback was being
    // disposed before any widget could read it. The pad then rebuilt at its
    // default '0'. Holding a listener for the dialog's whole lifetime is what
    // makes the pre-fill survive. No extra rebuilds: every `ref.watch` in
    // this file already invalidates this same State.
    ref.watch(calculatorProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    final showSplit = _splitVisible(tickets, settings);

    // Undivided orders don't need a 98%-wide canvas — a payment pad stretched
    // across a 27" till is worse, not better. Shrink to a comfortable column
    // and let the dialog centre itself; expand only when the grid is up.
    final maxWidth =
        showSplit ? screen.width * 0.98 : (screen.width * 0.98).clamp(0.0, 720.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(8),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: screen.height * 0.98,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.3),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(showSplit: showSplit, tickets: tickets),
                Expanded(
                  child: showSplit
                      ? Row(
                          children: [
                            // Tickets area — 60% width
                            Expanded(
                              flex: 6,
                              child: _buildTicketsArea(tickets),
                            ),
                            Container(width: 1, color: theme.dividerColor),
                            // Payment calculator — 40% width
                            Expanded(
                              flex: 4,
                              child: _buildPaymentPanel(),
                            ),
                          ],
                        )
                      : _buildPaymentPanel(),
                ),
              ],
            ),
            // Print status — a corner pill, not the full-screen scrim this
            // used to be. Paying no longer waits on the printer, so the
            // receipt printing in the background must not block the screen.
            // See [PrintStatusIndicator].
            const PrintStatusIndicator(),
          ],
        ),
      ),
    );
  }

  /// Leave the screen without taking any payment, keeping the division.
  ///
  /// This is the whole "divide the order now, collect later" flow: the draft
  /// split is already persisted by [_setTickets] on every rearrangement, so
  /// closing loses nothing — but a bare X reads as "cancel", so an order left
  /// divided says so on the way out. Reopening the payment screen (or the
  /// order, from a table) rebuilds exactly these tickets.
  ///
  /// The messenger is captured BEFORE the pop: afterwards this dialog's
  /// context is defunct and `ScaffoldMessenger.of` would throw.
  /// Leave with the division saved and nothing paid.
  ///
  /// The result distinguishes the two ways out, because the caller does
  /// different things with them (see `_showPaymentDialog`):
  ///   * `false` — the explicit "Save & continue" button. The cashier is done
  ///     with this order for now, so the till is freed like a plain Continue.
  ///   * `null`  — the header X, Escape or the barrier. Reads as "I opened
  ///     this by mistake", so the order stays in the panel.
  ///
  /// No snackbar either way: the division is already persisted by
  /// [_setTickets] and the order panel shows the ticket count.
  void _closeKeepingDivision({bool freeTheTill = false}) {
    Navigator.of(context).pop(freeTheTill ? false : null);
  }

  Widget _buildHeader({required bool showSplit, required List<TicketData> tickets}) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // Hiding the grid while tickets exist would strand the paid ones out of
    // sight, so the toggle only offers "hide" on an undivided order.
    final canCollapse = tickets.length <= 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.payments_rounded,
            size: 28,
            color: theme.colorScheme.onPrimaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('split_payment'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                Text(
                  'Order: ${widget.order.orderCode}',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          // Show/hide the ticket-division grid. Always reachable so the
          // "on demand" mode is discoverable without a trip to settings.
          TextButton.icon(
            onPressed: (showSplit && !canCollapse)
                ? null
                : () => setState(() => _splitPanelOverride = !showSplit),
            icon: Icon(
              showSplit ? Icons.view_agenda_rounded : Icons.call_split_rounded,
              size: 20,
            ),
            label: Text(
              showSplit
                  ? l10n.translate('hide_tickets')
                  : l10n.translate('divide_ticket'),
              style: const TextStyle(fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              disabledForegroundColor:
                  theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.35),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _closeKeepingDivision,
            icon: Icon(
              Icons.close_rounded,
              size: 26,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            tooltip: l10n.translate('close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketsArea(List<TicketData> tickets) {
    final hasUnpaidTicketsWithItems = tickets.any((t) => !t.isPaid && t.items.isNotEmpty);
    final l10n = AppLocalizations.of(context)!;
    final blockReason = _blockNewTicketReason(l10n);
    final paidCount = tickets.where((t) => t.isPaid).length;

    return Column(
      children: [
        // Tickets header with buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${l10n.translate('tickets')} (${tickets.length}/$_maxTickets)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$paidCount ${l10n.translate('paid').toLowerCase()} · '
                      '${tickets.length - paidCount} ${l10n.translate('remaining').toLowerCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Pay All button - always visible
              ElevatedButton.icon(
                onPressed: hasUnpaidTicketsWithItems ? _payAllTickets : null,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(l10n.translate('pay_all'), style: const TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(width: 8),
              // Print every divided ticket's slip in one go. Only once the
              // order is actually divided — on a single ticket this would be
              // the order ticket the main screen already printed. Individual
              // slips stay available from each ticket's own printer icon, for
              // the common case of one party asking for theirs.
              if (tickets.where((t) => !t.isPaid && t.items.isNotEmpty).length >
                  1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed:
                        _isPrintingDraft ? null : _printAllDraftTickets,
                    icon: _isPrintingDraft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.print_rounded, size: 18),
                    label: Text(l10n.translate('print_all_tickets'),
                        style: const TextStyle(fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      disabledForegroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
              Tooltip(
                message: blockReason ?? '',
                child: ElevatedButton.icon(
                  onPressed: blockReason == null ? _addNewTicket : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(l10n.translate('new_ticket'), style: const TextStyle(fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    disabledBackgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // UX hint bar — spells out the three gestures the grid supports, plus
        // whatever constraint is currently blocking a new ticket.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              Icon(
                blockReason == null
                    ? Icons.touch_app_rounded
                    : Icons.info_outline_rounded,
                size: 13,
                color: blockReason == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  blockReason ?? l10n.translate('ticket_division_hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: blockReason == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Colors.orange.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // One ticket per row.
        //
        // These used to be tall grid tiles, up to four across. A split of two
        // filled the screen with two half-empty columns, and the cashier read
        // each ticket top to bottom in a narrow strip while the width went
        // unused. A row is the shape of the information: who, what, how much —
        // and several fit on screen at once without any of them being big.
        Expanded(
          child: tickets.isEmpty
              ? Center(child: Text(l10n.translate('no_tickets')))
              : ListView.separated(
                  key: _ticketsListKey,
                  controller: _ticketsScrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _buildTicketCard(index, tickets[index]),
                ),
        ),
      ],
    );
  }

  /// One ticket as a row: identity on the left, its lines in the middle,
  /// money on the right.
  ///
  /// Height is fixed rather than intrinsic so a ticket holding one item and a
  /// ticket holding nine are the same size in the list — the eye can then
  /// scan down the totals column instead of re-finding it on every card. The
  /// lines scroll inside the row when there are more than fit.
  Widget _buildTicketCard(int index, TicketData ticket) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedIndex = ref.watch(selectedTicketProvider);
    final isSelected = selectedIndex == index;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final tickets = ref.watch(ticketsProvider);
    final l10n = AppLocalizations.of(context)!;

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => !ticket.isPaid,
      onAcceptWithDetails: (details) {
        if (!ticket.isPaid) {
          _moveItemToTicket(details.data, index);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty && !ticket.isPaid;

        final accent = ticket.isPaid
            ? Colors.green.shade700
            : theme.colorScheme.primary;

        return GestureDetector(
          onTap: () => _selectTicket(index),
          child: Container(
            height: 172,
            decoration: BoxDecoration(
              color: ticket.isPaid
                  ? (isDark
                      ? Colors.green.shade900.withValues(alpha: 0.3)
                      : Colors.green.shade50)
                  : (isDraggingOver
                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                      : (isSelected
                          ? theme.colorScheme.primaryContainer
                          : theme.cardColor)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDraggingOver
                    ? theme.colorScheme.primary
                    : (isSelected
                        ? theme.colorScheme.primary
                        : (ticket.isPaid ? Colors.green : theme.dividerColor)),
                width: isDraggingOver ? 3 : (isSelected ? 2 : 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Identity
                Container(
                  width: 132,
                  padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            ticket.isPaid
                                ? Icons.check_circle_rounded
                                : Icons.receipt_rounded,
                            size: 18,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ticket.ticketNum != null
                                  ? '#${ticket.ticketNum}'
                                  : '${index + 1}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: ticket.isPaid ? accent : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!ticket.isPaid && tickets.length > 1)
                            IconButton(
                              onPressed: () => _removeTicket(index),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              tooltip: l10n.translate('remove_ticket'),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 26, minHeight: 26),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ticket.items.length} ${l10n.translate('items')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        currencyFormatter.format(ticket.total),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                      if (!ticket.isPaid && ticket.items.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildTicketPrintButton(ticket),
                      ],
                    ],
                  ),
                ),

                VerticalDivider(width: 1, color: theme.dividerColor),

                // ── Its lines
                Expanded(
                  child: ticket.items.isEmpty
                      ? Center(
                          child: Text(
                            l10n.translate('drag_items_here'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          itemCount: ticket.items.length,
                          itemBuilder: (context, i) => _buildDraggableTicketItem(
                              index, i, ticket.items[i], ticket.isPaid),
                        ),
                ),

                // ── Money. Only unpaid tickets need a tender picker; a paid
                // one says so and stops taking up the space.
                if (!ticket.isPaid) ...[
                  VerticalDivider(width: 1, color: theme.dividerColor),
                  SizedBox(
                    width: 188,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SingleChildScrollView(
                        child: _buildPaymentMethodButtons(index, ticket),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDraggableTicketItem(int ticketIndex, int itemIndex, TicketLine line, bool isPaid) {
    final item = line.item;
    if (isPaid) {
      return _buildTicketItem(item);
    }

    final theme = Theme.of(context);

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) {
        final draggedItem = (details.data['line'] as TicketLine).item;
        // Same product at the same price, from any ticket including this one.
        return canCombineLines(draggedItem, item) &&
            !(details.data['ticketIndex'] == ticketIndex && details.data['itemIndex'] == itemIndex);
      },
      onAcceptWithDetails: (details) {
        _mergeItems(details.data, ticketIndex, itemIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isMergeTarget = candidateData.isNotEmpty;

        return Draggable<Map<String, dynamic>>(
          data: {
            'ticketIndex': ticketIndex,
            'itemIndex': itemIndex,
            'line': line,
          },
          onDragUpdate: (details) =>
              _autoScrollTicketsOnDrag(details.globalPosition),
          feedback: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.primary, width: 2),
              ),
              child: _buildTicketItemContent(item),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _buildTicketItem(item),
          ),
          child: GestureDetector(
            // Both gestures open the divide dialog. A tap used to peel one
            // unit off and write the new order_product row there and then, so
            // a mis-tap — or a drag the arena scored as a tap — duplicated the
            // line silently. Nothing is persisted now until the dialog's
            // confirm button; the old one-tap behaviour survives as the
            // dialog's "1 + rest" preset.
            onTap: item.quantity > 1 ? () => _showCustomDivideDialog(line, ticketIndex, itemIndex) : null,
            onLongPress: item.quantity > 1 ? () => _showCustomDivideDialog(line, ticketIndex, itemIndex) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMergeTarget
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isMergeTarget
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: isMergeTarget ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Merge indicator overlay when dragging over
                  if (isMergeTarget) ...[
                    Icon(Icons.merge_rounded, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Expanded(child: _buildTicketItemContent(item)),
                  // Split hint for items with qty > 1
                  if (item.quantity > 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.call_split_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTicketItemContent(OrderItem item) {
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
            border: item.quantity > 1
                ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Text(
            '${formatQty(item.quantity)}x',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.displayName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (item.components.isNotEmpty)
                Text(
                  item.components.map((c) => c.name).join(', '),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (item.note != null && item.note!.isNotEmpty)
                Text(
                  '📝 ${item.note}',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Colors.amber.shade800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          currencyFormatter.format(item.totalPrice),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTicketItem(OrderItem item) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: _buildTicketItemContent(item),
    );
  }

  Widget _buildPaymentMethodButtons(int index, TicketData ticket) {
    final theme = Theme.of(context);
    return Row(
      children: TransactionType.values.map((method) {
        final isSelected = ticket.paymentMethod == method;
        return Expanded(
          child: GestureDetector(
            onTap: () => _updatePaymentMethod(index, method),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected ? theme.colorScheme.primary : theme.dividerColor,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getPaymentIcon(method),
                    size: 18,
                    color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.value,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getPaymentIcon(TransactionType type) {
    switch (type) {
      case TransactionType.cash:
        return Icons.money_rounded;
      case TransactionType.card:
        return Icons.credit_card_rounded;
      case TransactionType.mobile:
        return Icons.phone_android_rounded;
      case TransactionType.other:
        return Icons.more_horiz_rounded;
    }
  }

  Widget _buildPaymentPanel() {
    final selectedIndex = ref.watch(selectedTicketProvider);
    final tickets = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (selectedIndex == null || selectedIndex >= tickets.length) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 80,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('select_ticket_to_pay'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    final ticket = tickets[selectedIndex];

    if (ticket.isPaid) {
      return _buildPaidTicketPanel(ticket);
    }

    if (ticket.items.isEmpty) {
      return _buildEmptyTicketPanel();
    }

    return _buildActivePaymentPanel(selectedIndex, ticket);
  }

  Widget _buildEmptyTicketPanel() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 80, color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text(
            l10n.translate('ticket_has_no_items'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPaidTicketPanel(TicketData ticket) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 100,
            color: Colors.green.shade600,
          ),
          const SizedBox(height: 24),
          Text(
            'Ticket Paid',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Ticket #${ticket.ticketNum}',
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          Text(
            currencyFormatter.format(ticket.total),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _printTicket(ticket),
              icon: const Icon(Icons.print_rounded, size: 28),
              label: Text(AppLocalizations.of(context)!.translate('print_receipt'), style: const TextStyle(fontSize: 18)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the backend still expects on this order, shown above the pad.
  ///
  /// Only for orders the server has an opinion about, which in practice means
  /// service orders taking a deposit at booking and the rest after the
  /// appointment. Prominent because it is the number the cashier is about to
  /// get wrong: the ticket in front of them is one instalment, not the bill.
  Widget _buildBalanceDue(
      ThemeData theme, AppLocalizations l10n, CurrencyFormatter formatter) {
    final orderId = widget.order.orderId;
    if (orderId == null) return const SizedBox.shrink();

    final order = ref.watch(orderPaymentPositionProvider(orderId)).valueOrNull;
    final balance = order?.balanceDue;
    // null = the server never told us; 0 or less = nothing outstanding. Only
    // a real outstanding figure earns the space.
    if (balance == null || balance <= 0.004) return const SizedBox.shrink();

    final paid = order?.amountPaid ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 18, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('balance_due'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (paid > 0)
                  Text(
                    '${l10n.translate('amount_paid')}: ${formatter.format(paid)}'
                    '${order?.paymentStatus != null ? ' · ${order!.paymentStatus}' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            formatter.format(balance),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivePaymentPanel(int ticketIndex, TicketData ticket) {
    final calcState = ref.watch(calculatorProvider);
    final allTickets = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context)!;

    final orderTotal = allTickets.fold<double>(0, (s, t) => s + t.total);
    final paidTotal = allTickets.where((t) => t.isPaid).fold<double>(0, (s, t) => s + t.total);
    final progressFraction = orderTotal > 0 ? (paidTotal / orderTotal).clamp(0.0, 1.0) : 0.0;
    final deliveryFee = _deliveryFeeFor(allTickets);
    final payable = ticket.total + deliveryFee;
    final canPay = ticket.items.isNotEmpty && calcState.enteredAmount >= payable && !_isProcessing;

    return Column(
      children: [
        // Ticket summary. The progress bar only earns its space once the order
        // is actually divided — on a single ticket "1/1 paid" is noise.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    allTickets.length > 1
                        ? '${l10n.translate('ticket')} ${ticketIndex + 1}  ·  ${currencyFormatter.format(ticket.total)}'
                        : '${l10n.translate('total_due')}  ·  ${currencyFormatter.format(ticket.total)}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                  if (ticket.totalTva > 0)
                    Text(
                      '${l10n.translate('tva')}: ${currencyFormatter.format(ticket.totalTva)}',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                ],
              ),
              // Delivery fee spelled out as its own line, so the cashier can
              // see why the amount to collect is above the products total.
              if (deliveryFee > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.delivery_dining, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text('${l10n.translate('delivery_fee')}:',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                      ],
                    ),
                    Text(
                      '+ ${currencyFormatter.format(deliveryFee)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${l10n.translate('to_collect')}:',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(
                      currencyFormatter.format(payable),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ],
              if (allTickets.length > 1) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${l10n.translate('paid')}: ${currencyFormatter.format(paidTotal)}'
                      '  (${allTickets.where((t) => t.isPaid).length}/${allTickets.length})',
                      style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                    ),
                    Text(
                      '${l10n.translate('remaining')}: ${currencyFormatter.format(orderTotal - paidTotal)}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        _buildBalanceDue(theme, l10n, currencyFormatter),

        // One pad for the ticket in hand: what came in, what goes back,
        // note shortcuts, keypad. There is no second prompt before this
        // screen — this *is* the cash-given step, and because it reads the
        // selected ticket it works the same undivided or split ten ways.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: CashPad(
              amountDue: payable,
              entered: calcState.enteredAmount,
              onKey: _onCalculatorButton,
              onAmount: _setExactAmount,
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Action buttons
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: canPay ? () => _processPayment(ticketIndex, ticket) : null,
                  icon: _isProcessing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 22),
                  label: Text(l10n.translate('complete_payment'), style: const TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Leave with the division saved and nothing paid — the
              // explicit counterpart to Complete Payment above. The header X
              // does the same thing, but an X reads as "cancel": a cashier
              // dividing a bill to collect later needs to see that finishing
              // without taking money is a real, intended action.
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.tonalIcon(
                  onPressed: _isProcessing
                      ? null
                      : () => _closeKeepingDivision(freeTheTill: true),
                  icon: const Icon(Icons.save_outlined, size: 20),
                  label: Text(
                    l10n.translate('save_division_continue'),
                    style: const TextStyle(fontSize: 15),
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _clearCalculator,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: Text(l10n.translate('clear'), style: const TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _setExactAmount(double amount) {
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: amount.toStringAsFixed(2),
      enteredAmount: amount,
    );
  }

  /// The calculator a freshly-selected (or freshly available) ticket should
  /// open showing: pre-filled with the exact amount still owed via
  /// [_setExactAmount], so an exact cash sale needs no typing at all — tap
  /// straight through to a tender button. Blank for a paid ticket, an empty
  /// one, or no ticket at all: there is nothing to pre-fill, and a payment
  /// index out of range for [tickets] falls back to blank rather than throw.
  void _resetCalculatorFor(int? ticketIndex, List<TicketData> tickets) {
    final ticket = (ticketIndex != null &&
            ticketIndex >= 0 &&
            ticketIndex < tickets.length)
        ? tickets[ticketIndex]
        : null;
    final amount = exactAmountDueFor(
      ticket,
      tickets,
      orderDeliveryFee: widget.order.deliveryFeeAmount,
    );
    if (amount == null) {
      ref.read(calculatorProvider.notifier).state = CalculatorState();
    } else {
      _setExactAmount(amount);
    }
  }

  // Event handlers
  void _selectTicket(int index) {
    final previous = ref.read(selectedTicketProvider);
    ref.read(selectedTicketProvider.notifier).state = index;
    // Tendered cash belongs to the ticket it was keyed against. Carrying it
    // over would let a 200 entered for a 180 ticket silently "cover" the next
    // 50 one, so switching tickets always starts from an empty pad.
    if (previous != index) {
      _resetCalculatorFor(index, ref.read(ticketsProvider));
    }
  }

  void _addNewTicket() {
    final l10n = AppLocalizations.of(context)!;
    final blockReason = _blockNewTicketReason(l10n);

    if (blockReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(blockReason),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    final tickets = ref.read(ticketsProvider);
    final defaultMethod = TransactionType.fromString(ref.read(settingsProvider).defaultPaymentMethod);
    final newTickets = [
      ...tickets,
      TicketData(
        items: [],
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ),
    ];
    _setTickets(newTickets);
    ref.read(selectedTicketProvider.notifier).state = newTickets.length - 1;
  }

  void _removeTicket(int index) {
    final tickets = ref.read(ticketsProvider);
    final l10n = AppLocalizations.of(context)!;

    if (tickets.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('cannot_remove_last_ticket'))),
      );
      return;
    }

    if (tickets[index].isPaid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('cannot_remove_paid_ticket'))),
      );
      return;
    }

    final removedLines = tickets[index].items;
    final updatedTickets = List<TicketData>.from(tickets);
    updatedTickets.removeAt(index);

    if (removedLines.isNotEmpty) {
      final destIdx = updatedTickets.indexWhere((t) => !t.isPaid);
      if (destIdx != -1) {
        updatedTickets[destIdx] = updatedTickets[destIdx].copyWith(
          items: [...updatedTickets[destIdx].items, ...removedLines],
        );
      }
    }

    final selected = ref.read(selectedTicketProvider);
    if (selected != null && selected >= updatedTickets.length) {
      ref.read(selectedTicketProvider.notifier).state = null;
    }

    _setTickets(updatedTickets);
  }

  void _updatePaymentMethod(int index, TransactionType method) {
    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(tickets);
    updatedTickets[index] = tickets[index].copyWith(paymentMethod: method);
    _setTickets(updatedTickets);
  }

  /// Commit a rearrangement, dropping the source ticket when the line that
  /// just left was its last.
  ///
  /// Only ever the *source*. An empty ticket the cashier has deliberately just
  /// added is somewhere to drag things to — pruning every empty ticket would
  /// delete it out from under them mid-drag. A paid ticket is history and the
  /// last remaining ticket is the screen itself, so neither is ever dropped.
  ///
  /// Selection follows the line: emptying the ticket you were standing on
  /// moves you to the one the line went to, and the pad clears with it,
  /// because tendered cash belongs to the ticket it was keyed against.
  void _commitAndPrune(
      List<TicketData> tickets, int sourceIndex, int targetIndex) {
    final source = tickets[sourceIndex];
    var selected = ref.read(selectedTicketProvider);
    var selectionChangedTicket = false;

    if (!source.isPaid && source.items.isEmpty && tickets.length > 1) {
      tickets.removeAt(sourceIndex);
      final target = targetIndex > sourceIndex ? targetIndex - 1 : targetIndex;

      if (selected == sourceIndex) {
        selected = target;
        selectionChangedTicket = true;
      } else if (selected != null && selected > sourceIndex) {
        // Same ticket, one place to the left — not a different ticket, so the
        // pad keeps whatever was keyed against it.
        selected -= 1;
      }
    }

    _setTickets(tickets);

    if (selected != null && selected >= tickets.length) {
      selected = tickets.isEmpty ? null : tickets.length - 1;
      selectionChangedTicket = true;
    }
    ref.read(selectedTicketProvider.notifier).state = selected;
    if (selectionChangedTicket) {
      _resetCalculatorFor(selected, tickets);
    }
  }

  /// Drag a whole line onto another ticket. State only — the row it draws
  /// from is untouched until that ticket is paid.
  void _moveItemToTicket(Map<String, dynamic> data, int targetTicketIndex) {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final itemIndex = data['itemIndex'] as int;

    if (sourceTicketIndex == targetTicketIndex) return;

    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(
      tickets.map((ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items))),
    );
    if (sourceTicketIndex >= updatedTickets.length ||
        targetTicketIndex >= updatedTickets.length ||
        itemIndex >= updatedTickets[sourceTicketIndex].items.length) {
      return;
    }

    final moved = updatedTickets[sourceTicketIndex].items.removeAt(itemIndex);

    // Fold into a line already on the target when the two are the same thing
    // at the same price; otherwise the line lands beside it.
    final mergeIndex = updatedTickets[targetTicketIndex].items.indexWhere(
      (existing) => canCombineLines(existing.item, moved.item),
    );

    if (mergeIndex != -1) {
      final existing = updatedTickets[targetTicketIndex].items[mergeIndex];
      updatedTickets[targetTicketIndex].items[mergeIndex] = existing.mergedWith(moved);
    } else {
      updatedTickets[targetTicketIndex].items.add(moved);
    }

    _commitAndPrune(updatedTickets, sourceTicketIndex, targetTicketIndex);
  }

  void _onCalculatorButton(String button) {
    final calcState = ref.read(calculatorProvider);
    String newDisplay = calcState.display;

    if (button == '⌫') {
      newDisplay = newDisplay.length > 1 ? newDisplay.substring(0, newDisplay.length - 1) : '0';
    } else if (button == '.') {
      if (!newDisplay.contains('.')) newDisplay += '.';
    } else {
      newDisplay = newDisplay == '0' ? button : newDisplay + button;
    }

    final amount = double.tryParse(newDisplay) ?? 0.0;
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: newDisplay,
      enteredAmount: amount,
    );
  }

  void _clearCalculator() {
    ref.read(calculatorProvider.notifier).state = CalculatorState();
  }

  Future<void> _processPayment(int ticketIndex, TicketData ticket) async {
    if (_isProcessing) return;
    if (!ref.read(permissionServiceProvider).hasPermission(Permissions.ticketsCreate)) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('no_permission')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isProcessing = true);
    final database = ref.read(databaseProvider);
    final session = ref.read(currentSessionProvider);
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);

    // Snapshot the tendered amount before anything clears the pad — the
    // receipt's "given / change" block is built from it further down.
    // 0 means "nobody keyed a tender" (Pay-all, card, exact-by-default), and
    // the print side treats null as "don't print those lines".
    final tendered = ref.read(calculatorProvider).enteredAmount;
    final double? amountGiven = tendered > 0 ? tendered : null;
    // The fee is part of what the customer hands over, so the change is
    // measured against products + fee. Captured before the ticket is written,
    // because writing it flips `isPaid` and the fee would then read as 0.
    final deliveryFee = _deliveryFeeFor(ref.read(ticketsProvider));
    final double? changeDue =
        amountGiven == null ? null : (amountGiven - ticket.total - deliveryFee);

    // Require an active cash session so the ticket is linked to a Z-report.
    if (session == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('no_active_session')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      setState(() => _isProcessing = false);
      return;
    }

    // Guard: payment screen must always be opened for a saved order.
    final orderId = widget.order.orderId;
    if (orderId == null) {
      _logger.error('_processPayment: orderId is null — order was not saved before payment');
      setState(() => _isProcessing = false);
      return;
    }

    try {
      // Get next ticket number — query fresh from DB to avoid collisions in batch pay
      final existingTickets = await (database.select(database.tickets)
            ..where((t) => t.orderId.equals(orderId)))
          .get();

      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);

      final newTicketNum = maxTicketNum + 1;
      final ticketNumStr = newTicketNum.toString().padLeft(4, '0');

      // Insert ticket + settle its rows atomically — a crash between the two
      // steps would leave an orphaned ticket with products still PENDING, or
      // a division half applied.
      late final int ticketId;
      await database.transaction(() async {
        ticketId = await database.into(database.tickets).insert(
          TicketsCompanion.insert(
            num: ticketNumStr,
            orderId: orderId,
            paymentMethod: ticket.paymentMethod.value,
            amount: ticket.total,
            sessionId: Value(session.id),
            // z_day = the active Z's opening day (all sessions in a Z share one
            // z_day). Stays constant even if the ticket is cut after midnight.
            zDay: Value(ref.read(currentZDayProvider)),
            isPaid: const Value(true),
            printCount: const Value(0),
            date: Value(DateTime.now()),
          ),
        );

        await _materializeTicket(database, ticket, ticketId);
      });

      // Money changed hands at THIS till, so the order is now this cashier's
      // — including a part payment, where the rest of the bill follows the
      // person who took the first of it. Outside the transaction above: a
      // claim must never be able to roll back a completed payment.
      await ref
          .read(orderRepositoryProvider)
          .claimOrderForCurrentUser(widget.order.orderId!);

      // Update UI state immediately (synchronous, no frame callback)
      // This is critical for _payAllTickets to see the correct state on next iteration.
      if (mounted) {
        final updatedItems = ticket.items
            .map((line) => line.copyWith(
                item: line.item.copyWith(ticketId: ticketId, state: 'PAID')))
            .toList();
        final currentTickets = ref.read(ticketsProvider);
        final updatedTickets = List<TicketData>.from(currentTickets);
        if (ticketIndex < updatedTickets.length) {
          updatedTickets[ticketIndex] = ticket.copyWith(
            isPaid: true,
            ticketId: ticketId,
            ticketNum: ticketNumStr,
            items: updatedItems,
          );
        }
        _setTickets(updatedTickets);
        _resetCalculatorFor(ticketIndex, updatedTickets);

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.translate('ticket_paid_successfully').replaceAll('{0}', ticketNumStr)),
              backgroundColor: Colors.green.shade700,
            ),
          );
        }
      }

      // Print ticket — read the payload off local state now, print detached.
      // PrintingService queues the job behind anything a waiter is already
      // printing, so paying never waits on the printer. In _payAllTickets this
      // also means each ticket's paperwork queues in order while the next
      // ticket is already being settled.
      final prefs = ref.read(sharedPreferencesProvider);
      final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';
      final storeAddress = prefs.getString('business_address');
      final storePhone = prefs.getString('business_phone');

      final itemsForPrint = ticket.items.map((line) {
        final item = line.item;
        return {
          'name': item.displayName,
          'quantity': item.quantity,
          'price': item.totalPrice,
          'components': item.components
              .map((c) => {
                    'name': c.name,
                    'quantity': c.quantity,
                    'removalCharge': c.removalCharge,
                  })
              .toList(),
        };
      }).toList();

      unawaited(() async {
        try {
          await printingService.printPaymentDocuments(
            ticketId: ticketId,
            ticketNumber: ticketNumStr,
            // Products only — this is the figure the ticket row carries and the
            // one every sales/Z total is built from. The delivery fee travels
            // beside it as its own line.
            amount: ticket.total,
            deliveryFee: deliveryFee > 0 ? deliveryFee : null,
            tvaAmount: ticket.totalTva,
            // Same two parts TicketData.total already subtracts, so the row
            // reconciles with the total printed under it.
            discountAmount: ticket.itemDiscount + ticket.manualDiscountAmount,
            discountReason: widget.order.discountReason,
            amountGiven: amountGiven,
            changeDue: changeDue,
            paymentMethod: ticket.paymentMethod.value,
            createdAt: DateTime.now(),
            items: itemsForPrint,
            orderType: widget.order.type,
            hasTable: widget.order.tableId != null,
            orderCode: widget.order.orderCode,
            cashierName: currentUser?.firstName,
            waiterName: widget.order.waiterName,
            storeName: businessName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            customerName: widget.order.customerName,
            customerPhone: widget.order.customerPhone,
            deliveryAddress: widget.order.deliveryAddress,
            tableName: widget.order.tableName,
            numberOfPersons: widget.order.numberOfPersons,
          );

          await database.customStatement(
            'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
            [ticketId],
          );
        } catch (e) {
          _logger.error('Print failed: $e');
        }
      }());

      // Audit log: payment taken
      await ref.read(activityLogServiceProvider).logPayment(
            ticket.total.toStringAsFixed(2),
            widget.order.orderCode ?? '#${widget.order.orderId ?? ''}',
            userId: currentUser?.id,
            username: currentUser?.effectiveDisplayName,
          );

      // Check if all order products are now paid -> mark order as COMPLETED and sync
      await _checkAndCompleteOrder(orderId);
    } catch (e) {
      _logger.error('Payment failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n
                .translate('payment_failed')
                .replaceAll('{0}', errorText(e, l10n))),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Write the arrangement the cashier built on screen into `order_products`,
  /// settling everything [ticket] claims onto [ticketId].
  ///
  /// This is the *only* place the division work reaches the database, and it
  /// runs inside the payment transaction. Until a ticket is paid the order
  /// rows are exactly as they were loaded, so abandoning the screen — or
  /// paying only part of a divided order — leaves nothing half-cut behind.
  ///
  /// Claims are summed per row first, because merging lets one row back
  /// several lines of the same ticket. A row claimed in full is simply marked
  /// PAID; a row claimed in part keeps its id on the **unpaid remainder** —
  /// the other tickets still point at that id — and the paid portion is cut
  /// onto a row of its own.
  Future<void> _materializeTicket(
      AppDatabase database, TicketData ticket, int ticketId) async {
    final claims = <int, double>{};
    for (final line in ticket.items) {
      for (final source in line.sources) {
        claims[source.rowId] = (claims[source.rowId] ?? 0) + source.quantity;
      }
    }

    for (final entry in claims.entries) {
      final row = await (database.select(database.orderProducts)
            ..where((t) => t.id.equals(entry.key)))
          .getSingleOrNull();
      // Gone, or already settled on an earlier ticket — either way this
      // ticket has no claim left to press.
      if (row == null || row.ticketId != null) continue;

      final claimed = entry.value;
      final remainder = row.quantity - claimed;

      if (remainder <= _qtyEpsilon) {
        await (database.update(database.orderProducts)
              ..where((t) => t.id.equals(row.id)))
            .write(OrderProductsCompanion(
          ticketId: Value(ticketId),
          state: const Value('PAID'),
          updatedAt: Value(DateTime.now()),
        ));
        continue;
      }

      // Kitchen credit follows the food: the paid slice takes as much of the
      // already-sent quantity as it covers, so the remainder can still fire a
      // modifications-only ticket for what genuinely has not gone through.
      final printedForSlice =
          row.kdsPrintedQuantity < claimed ? row.kdsPrintedQuantity : claimed;
      // Same rule for the customer slip: credit follows the units.
      final slippedForSlice = row.orderTicketPrintedQuantity < claimed
          ? row.orderTicketPrintedQuantity
          : claimed;

      await (database.update(database.orderProducts)
            ..where((t) => t.id.equals(row.id)))
          .write(OrderProductsCompanion(
        quantity: Value(remainder),
        kdsPrintedQuantity: Value(row.kdsPrintedQuantity - printedForSlice),
        orderTicketPrintedQuantity:
            Value(row.orderTicketPrintedQuantity - slippedForSlice),
        updatedAt: Value(DateTime.now()),
      ));

      final sliceId = await database.into(database.orderProducts).insert(
            OrderProductsCompanion.insert(
              orderId: row.orderId,
              productId: row.productId,
              variantId: Value(row.variantId),
              ticketId: Value(ticketId),
              quantity: Value(claimed),
              unitaryPrice: row.unitaryPrice,
              cost: Value(row.cost),
              unitaryDiscount: Value(row.unitaryDiscount),
              unitaryTva: Value(row.unitaryTva),
              manualDiscount: Value(row.manualDiscount),
              manualDiscountReason: Value(row.manualDiscountReason),
              // serverId is deliberately not carried: the backend knows that
              // id as the original line, and two local rows answering to it
              // would corrupt the delta push and any refund keyed on it.
              saleUomId: Value(row.saleUomId),
              note: Value(row.note),
              state: const Value('PAID'),
              planStartAt: Value(row.planStartAt),
              planEndAt: Value(row.planEndAt),
              planWaiterId: Value(row.planWaiterId),
              planResourceId: Value(row.planResourceId),
              kdsPrintedAt: Value(row.kdsPrintedAt),
              kdsPrintedQuantity: Value(printedForSlice),
              orderTicketPrintedQuantity: Value(slippedForSlice),
              preparingAt: Value(row.preparingAt),
              readyAt: Value(row.readyAt),
              servedAt: Value(row.servedAt),
              zDay: Value(row.zDay),
            ),
          );

      final components = await (database.select(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(row.id)))
          .get();
      for (final component in components) {
        await database.into(database.orderProductComponents).insert(
              OrderProductComponentsCompanion.insert(
                componentId: component.componentId,
                orderProductId: sliceId,
                quantity: Value(component.quantity),
                price: Value(component.price),
                isSpecial: Value(component.isSpecial),
                // Carry the snapshot across the split, not the live name.
                name: Value(component.name),
              ),
            );
      }

      _logger.info(
          'Settled $claimed of order_product #${row.id} on ticket #$ticketId '
          '(new row #$sliceId, ${remainder.toStringAsFixed(3)} left unpaid)');
    }
  }

  /// Pay all unpaid tickets — reads fresh state before each payment to avoid stale-state bugs
  Future<void> _payAllTickets() async {
    if (!ref.read(permissionServiceProvider).hasPermission(Permissions.ticketsCreate)) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('no_permission')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    // Snapshot the count once; iterate by re-reading state each time so we always
    // operate on the up-to-date ticket list (state is now updated synchronously in _processPayment).
    final initialCount = ref.read(ticketsProvider).length;

    for (int i = 0; i < initialCount; i++) {
      final currentTickets = ref.read(ticketsProvider);
      if (i >= currentTickets.length) break;
      final ticket = currentTickets[i];
      if (!ticket.isPaid && ticket.items.isNotEmpty) {
        await _processPayment(i, ticket);
      }
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('all_tickets_paid_successfully')),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Check if all order products are settled, mark order as paid default status
  /// and sync. "Settled" tolerates CANCELED lines — a voided item no longer
  /// blocks completion — and the status bump + table free happen atomically,
  /// keyed on the order's real table occupancy (not the possibly-stale
  /// in-memory `tableId`). See [OrderRepository.settleOrderAndFreeTable].
  Future<void> _checkAndCompleteOrder(int orderId) async {
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final settings = ref.read(settingsProvider);
      final paidStatus = settings.paidOrderDefaultStatus;

      final completed = await orderRepo.settleOrderAndFreeTable(
        orderId,
        paidStatus: paidStatus,
        clearTable: settings.autoClearTableAfterPaying,
      );

      // Sweep the rest of the floor while we are here. Cheap, and it clears
      // tables stranded by an earlier order that finished down a path which
      // forgot to let go of its table.
      await orderRepo.reconcileTableOccupancy(
          freeOnPayment: settings.autoClearTableAfterPaying);

      if (completed) {
        _logger.info('Order #$orderId marked as $paidStatus (all lines settled)');
        // Before the sync below, so `takenBy` goes up with the completion
        // rather than needing a second push.
        await orderRepo.claimOrderForCurrentUser(orderId);

        // The division has done its job. Leaving the rows behind would have
        // them reconstructed against re-used row ids if this order is ever
        // reopened, and nothing else ever reads them again.
        try {
          final database = ref.read(databaseProvider);
          await (database.delete(database.ticketDraftSplits)
                ..where((t) => t.orderId.equals(orderId)))
              .go();
        } catch (e) {
          _logger.error('Failed to clear draft split for #$orderId: $e');
        }

        // Auto-sync if online — detached, so the payment screen closes on the
        // local commit instead of on a network round-trip. settleOrderAndFreeTable
        // passes queueSyncOperation: false, so this is the paid order's only
        // prompt push; it writes isSynced = false, so the periodic sweep stays
        // the backstop if it fails.
        final isOnline = ref.read(lastKnownOnlineStatusProvider);
        if (isOnline) {
          final syncManager = ref.read(syncManagerProvider.notifier);
          unawaited(() async {
            try {
              await syncManager.autoSyncOrder(orderId);
              _logger.info('Auto-synced $paidStatus order #$orderId');
            } catch (e) {
              _logger.error('Auto-sync failed for order #$orderId: $e');
            }
          }());
        }

        // Close payment dialog with success
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      _logger.error('Error checking/completing order #$orderId: $e');
    }
  }

  /// Tap: Quick split – peel off 1 unit from the item into a NEW ticket
  /// Merge two same-product lines when one is dropped onto another. State
  /// only: the merged line simply claims both lines' rows, so nothing is
  /// written and nothing is deleted.
  void _mergeItems(Map<String, dynamic> data, int targetTicketIndex, int targetItemIndex) {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final sourceItemIndex = data['itemIndex'] as int;

    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(
      tickets.map((ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items))),
    );
    if (targetTicketIndex >= updatedTickets.length ||
        sourceTicketIndex >= updatedTickets.length ||
        targetItemIndex >= updatedTickets[targetTicketIndex].items.length ||
        sourceItemIndex >= updatedTickets[sourceTicketIndex].items.length) {
      return;
    }

    final target = updatedTickets[targetTicketIndex].items[targetItemIndex];
    final source = updatedTickets[sourceTicketIndex].items[sourceItemIndex];
    if (!canCombineLines(target.item, source.item)) return;

    updatedTickets[targetTicketIndex].items[targetItemIndex] = target.mergedWith(source);
    // Remove the source last: on a same-ticket merge the target sits at an
    // index this shifts, and it has already been written.
    updatedTickets[sourceTicketIndex].items.removeAt(sourceItemIndex);

    _commitAndPrune(updatedTickets, sourceTicketIndex, targetTicketIndex);

    final mergedQty = target.item.quantity + source.item.quantity;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.merge_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${source.item.displayName} → ${formatQty(mergedQty)}x'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  /// Divide dialog with slider and constraints, opened by tapping a line.
  /// Only works for whole-number quantities — fractional (weighed) items
  /// cannot be split sensibly with an integer slider.
  ///
  /// Purely a preview: the split is written only when the confirm button is
  /// pressed, so backing out costs nothing.
  void _showCustomDivideDialog(TicketLine line, int ticketIndex, int itemIndex) {
    final item = line.item;
    if (item.quantity < 2 || item.quantity != item.quantity.truncateToDouble()) return;
    if (_isProcessing) return;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    int splitQty = 1;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final qty1 = splitQty;
            final qty2 = item.quantity - splitQty;
            final price1 = item.totalPrice / item.quantity * qty1;
            final price2 = item.totalPrice / item.quantity * qty2;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.call_split_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('divide_quantity'),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product name
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${formatQty(item.quantity)}x',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                            ),
                          ),
                          Text(
                            currencyFormatter.format(item.totalPrice),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Slider
                    Row(
                      children: [
                        _buildSplitPreview(theme, currencyFormatter, qty1, price1, theme.colorScheme.primary),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              activeTrackColor: theme.colorScheme.primary,
                              inactiveTrackColor: theme.colorScheme.secondary.withValues(alpha: 0.3),
                              thumbColor: theme.colorScheme.primary,
                              overlayColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                              trackHeight: 6,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                            ),
                            child: Slider(
                              value: splitQty.toDouble(),
                              min: 1,
                              max: item.quantity - 1,
                              divisions: item.quantity.toInt() - 2 > 0 ? item.quantity.toInt() - 2 : 1,
                              onChanged: (val) {
                                setDialogState(() => splitQty = val.round());
                              },
                            ),
                          ),
                        ),
                        _buildSplitPreview(theme, currencyFormatter, qty2, price2, theme.colorScheme.secondary),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Quick presets for common splits
                    if (item.quantity > 2)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: _buildQuickSplitChips(item, setDialogState, (val) => splitQty = val, splitQty),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(l10n.translate('cancel')),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    // qty1 is the left-hand preview and stays where it is;
                    // it is the second portion that moves to its own ticket.
                    _divideLine(line, qty2, ticketIndex, itemIndex);
                  },
                  icon: const Icon(Icons.call_split_rounded, size: 18),
                  label: Text('${l10n.translate('split_into_quantities')}: $qty1 + $qty2'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSplitPreview(ThemeData theme, CurrencyFormatter formatter, num qty, double price, Color color) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${qty}x',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            formatter.format(price),
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuickSplitChips(OrderItem item, StateSetter setDialogState, Function(int) onSplitChanged, int currentSplit) {
    // Guard already enforced by _showCustomDivideDialog, but be defensive.
    if (item.quantity != item.quantity.truncateToDouble()) return [];
    final chips = <Widget>[];
    final qty = item.quantity.toInt();

    // Half split
    if (qty % 2 == 0) {
      final half = qty ~/ 2;
      chips.add(_buildSplitChip('½ + ½', half, currentSplit, setDialogState, onSplitChanged));
    }

    // Thirds
    if (qty % 3 == 0) {
      final third = qty ~/ 3;
      chips.add(_buildSplitChip('⅓ + ⅔', third, currentSplit, setDialogState, onSplitChanged));
    }

    // 1 + rest
    if (qty > 2) {
      chips.add(_buildSplitChip('1 + ${qty - 1}', 1, currentSplit, setDialogState, onSplitChanged));
    }

    // rest + 1
    if (qty > 3) {
      chips.add(_buildSplitChip('${qty - 1} + 1', qty - 1, currentSplit, setDialogState, onSplitChanged));
    }

    return chips;
  }

  Widget _buildSplitChip(String label, int splitVal, int currentSplit, StateSetter setDialogState, Function(int) onSplitChanged) {
    final theme = Theme.of(context);
    final isSelected = currentSplit == splitVal;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setDialogState(() => onSplitChanged(splitVal));
      },
      selectedColor: theme.colorScheme.primaryContainer,
      labelStyle: TextStyle(
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? theme.colorScheme.onPrimaryContainer : null,
      ),
    );
  }

  /// Cut [takeQty] units off the line into a ticket of their own.
  ///
  /// Synchronous and state-only. Nothing reaches `order_products` here — the
  /// two halves simply divide the line's claim on the rows behind it, and the
  /// database is told about the arrangement when a ticket is paid.
  void _divideLine(TicketLine line, double takeQty, int ticketIndex, int itemIndex) {
    if (_isProcessing) return;
    if (takeQty <= 0 || takeQty >= line.item.quantity) return;

    final tickets = ref.read(ticketsProvider);
    // An empty unpaid ticket is somewhere to put the second portion without
    // adding to the count, so the ceiling only bites when one has to be made.
    final emptyIdx = tickets.indexWhere((t) => !t.isPaid && t.items.isEmpty);
    if (emptyIdx == -1 && tickets.length >= _maxTickets) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n
              .translate('max_tickets_reached')
              .replaceAll('{0}', '$_maxTickets')),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      return;
    }

    final updatedTickets = List<TicketData>.from(
      tickets.map((ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items))),
    );
    if (ticketIndex >= updatedTickets.length ||
        itemIndex >= updatedTickets[ticketIndex].items.length) {
      return;
    }

    final (kept, taken) = line.split(takeQty);
    updatedTickets[ticketIndex].items[itemIndex] = kept;

    if (emptyIdx != -1) {
      updatedTickets[emptyIdx].items.add(taken);
    } else {
      updatedTickets.add(TicketData(
        items: [taken],
        paymentMethod: TransactionType.fromString(
          ref.read(settingsProvider).defaultPaymentMethod,
        ),
        discountPercentage: widget.order.discountPercentage,
      ));
    }

    _setTickets(updatedTickets);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.call_split_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('${line.item.displayName}: '
                '${formatQty(kept.item.quantity)} + ${formatQty(taken.item.quantity)}'),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  /// The delivery fee a reprint of [ticket] should show, or null. Mirrors
  /// [_deliveryFeeFor]: the charge was collected on the first ticket cut, so
  /// only the lowest-id paid ticket carries it.
  double? _reprintDeliveryFee(TicketData ticket) {
    final fee = widget.order.deliveryFeeAmount;
    if (fee <= 0 || ticket.ticketId == null) return null;

    final paidIds = ref
        .read(ticketsProvider)
        .map((t) => t.ticketId)
        .whereType<int>()
        .toList();
    if (paidIds.isEmpty) return null;

    final firstId = paidIds.reduce((a, b) => a < b ? a : b);
    return ticket.ticketId == firstId ? fee : null;
  }

  /// Print ONE draft ticket's slip, with nothing paid.
  ///
  /// Deliberately [PrintingService.printOrderReceipt] and NOT
  /// `printTicketReceipt`: the latter is a payment receipt — it carries a
  /// ticket number, a tender method and a "PAYMENT RECEIPT" banner, and
  /// handing one to a customer who has not paid misrepresents the sale. What
  /// this prints is an order slip for that share of the bill, which is what
  /// a divided table actually wants: each party gets their own slip, the
  /// division stays remembered, and the money is collected afterwards.
  ///
  /// The order is cloned down to just this ticket's lines so the slip totals
  /// that share alone. Nothing is written: the draft split is already
  /// persisted by [_setTickets], and no `tickets` row exists until payment.
  /// The bill button on a ticket card: prints THIS division on its own with
  /// nothing paid — the "divide the bill, hand each party their slip, collect
  /// later" flow.
  ///
  /// Deliberately a full-width labelled button rather than a bare icon: this
  /// is the addition the customer is handed, not a minor affordance, and a
  /// 16px printer glyph wedged next to the ticket number went unnoticed.
  ///
  /// Shown on a single ticket too — an undivided table still wants its bill
  /// before paying — and it does NOT consult the orderTicket print rule, so a
  /// shop with automatic order tickets switched off can still print one on
  /// request. The arrow opens the full print options, where the per-station
  /// and KDS choices live.
  Widget _buildTicketPrintButton(TicketData ticket) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      height: 34,
      child: PopupMenuButton<String>(
        enabled: !_isPrintingDraft,
        tooltip: '',
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        onSelected: (v) => v == 'bill'
            ? _printDraftTicket(ticket)
            : _openPrintOptionsForTicket(ticket),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'bill',
            child: Row(children: [
              const Icon(Icons.receipt_long_outlined, size: 18),
              const SizedBox(width: 8),
              Text(l10n.translate('print_this_ticket')),
            ]),
          ),
          PopupMenuItem(
            value: 'options',
            child: Row(children: [
              const Icon(Icons.tune_rounded, size: 18),
              const SizedBox(width: 8),
              Text(l10n.translate('print_options')),
            ]),
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isPrintingDraft)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.print_rounded,
                    size: 17, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  l10n.translate('bill_addition'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Icon(Icons.arrow_drop_down_rounded,
                  size: 18, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// Send ONE draft ticket's slip. Returns whether the printer took it.
  ///
  /// No permission check and no busy flag — both belong to the callers, so
  /// printing five slips checks the permission once and holds the flag across
  /// the whole run rather than flickering it per slip.
  Future<bool> _printOneDraftSlip(TicketData ticket) async {
    if (ticket.items.isEmpty) return false;
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    // Only this ticket's lines. `clearDeliveryFee` because the fee belongs
    // to the order as a whole, not to one share of it — charging it on
    // every slip of a divided delivery would bill it two or three times
    // over, the same rule `deliveryFeeToCollect` already enforces at
    // payment time.
    final slice = widget.order.copyWith(
      items: [for (final line in ticket.items) line.item],
      clearDeliveryFee: true,
    );

    return printingService.printOrderReceipt(
      order: slice,
      cashierName: currentUser?.firstName,
      storeName: prefs.getString('business_name'),
      storeAddress: prefs.getString('business_address'),
      storePhone: prefs.getString('business_phone'),
      customerName: widget.order.customerName,
    );
  }

  /// Open the full print-options dialog for ONE draft ticket.
  ///
  /// Reuses [showPrintOptionsDialog] rather than growing a second print UI:
  /// that dialog already offers receipt-and-or-KDS, the KDS mode, and — the
  /// part that matters here — a per-STATION picker, so the cashier can send
  /// just the bar's half of a divided ticket to the bar. It calls the printing
  /// service directly, so like the bill button it ignores the automatic print
  /// rules; an explicit request is not an automatic one.
  ///
  /// The order is narrowed to this ticket's lines first, exactly as
  /// [_printOneDraftSlip] does, so whatever the cashier chooses applies to
  /// this share of the bill and not the whole table.
  Future<void> _openPrintOptionsForTicket(TicketData ticket) async {
    if (ticket.items.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    if (!_ensureCanPrint(l10n)) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final slice = widget.order.copyWith(
      items: [for (final line in ticket.items) line.item],
      clearDeliveryFee: true,
    );
    await showPrintOptionsDialog(
      context,
      order: slice,
      cashierName: ref.read(currentUserProvider)?.firstName,
      storeName: prefs.getString('business_name'),
      storeAddress: prefs.getString('business_address'),
      storePhone: prefs.getString('business_phone'),
    );
  }

  /// True when the cashier may print, complaining on screen when they may not.
  bool _ensureCanPrint(AppLocalizations l10n) {
    if (ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ticketsPrint)) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.translate('no_permission')),
      backgroundColor: Colors.red,
    ));
    return false;
  }

  Future<void> _printDraftTicket(TicketData ticket) async {
    if (_isPrintingDraft) return;
    final l10n = AppLocalizations.of(context)!;
    if (!_ensureCanPrint(l10n)) return;
    if (ticket.items.isEmpty) return;

    setState(() => _isPrintingDraft = true);
    try {
      final ok = await _printOneDraftSlip(ticket);
      if (!mounted) return;
      // Silent on success — the paper is the confirmation. Only a failure
      // needs saying, because nothing came out to say it.
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate('print_failed')),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      _logger.error('Draft ticket print failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorText(e, l10n)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isPrintingDraft = false);
    }
  }

  /// Print every divided ticket's slip, one after another.
  ///
  /// Sequential with a pause between jobs, not concurrent: back-to-back jobs
  /// are what the printing service's own `consolidateKdsJob` setting exists
  /// to avoid — some Windows spoolers silently drop the third of a rapid
  /// burst. Slower, but a missing slip on a divided bill is worse.
  ///
  /// Reports how many actually printed rather than claiming success: a
  /// printer that quits after two of five must not look like it did all five.
  Future<void> _printAllDraftTickets() async {
    if (_isPrintingDraft) return;
    final l10n = AppLocalizations.of(context)!;
    if (!_ensureCanPrint(l10n)) return;

    final pending = [
      for (final t in ref.read(ticketsProvider))
        if (!t.isPaid && t.items.isNotEmpty) t,
    ];
    if (pending.isEmpty) return;

    setState(() => _isPrintingDraft = true);
    var printed = 0;
    try {
      for (var i = 0; i < pending.length; i++) {
        if (!mounted) break;
        if (await _printOneDraftSlip(pending[i])) printed++;
        if (i < pending.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
      if (!mounted) return;
      // Nothing to say when every slip came out. A printer that quit after
      // two of five must not look like it did all five, though.
      if (printed != pending.length) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n
              .translate('draft_tickets_printed_count')
              .replaceAll('{0}', '$printed')
              .replaceAll('{1}', '${pending.length}')),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      _logger.error('Print all draft tickets failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(errorText(e, l10n)),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isPrintingDraft = false);
    }
  }

  Future<void> _printTicket(TicketData ticket) async {
    if (ticket.ticketId == null) return;
    if (!ref.read(permissionServiceProvider).hasPermission(Permissions.ticketsPrint)) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.translate('no_permission')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    try {
      final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';
      final itemsForPrint = ticket.items.map((line) => {
        'name': line.item.displayName,
        'quantity': line.item.quantity,
        'price': line.item.totalPrice,
        'components': line.item.components
            .map((c) => {
                  'name': c.name,
                  'quantity': c.quantity,
                  'price': c.price,
                  'removalCharge': c.removalCharge,
                })
            .toList(),
      }).toList();

      await printingService.printTicketReceipt(
        ticketId: ticket.ticketId!,
        ticketNumber: ticket.ticketNum ?? ticket.ticketId.toString(),
        amount: ticket.total,
        // Reprint must not repeat the fee on a divided order: it was collected
        // once, on the ticket that settled first (the lowest ticket id).
        deliveryFee: _reprintDeliveryFee(ticket),
        tvaAmount: ticket.totalTva,
        // Per-line reductions plus the order-level remise — the same two parts
        // TicketData.total already subtracts, so the row always reconciles
        // with the figure printed beneath it.
        discountAmount: ticket.itemDiscount + ticket.manualDiscountAmount,
        discountReason: widget.order.discountReason,
        paymentMethod: ticket.paymentMethod.value,
        createdAt: DateTime.now(),
        items: itemsForPrint,
        orderCode: widget.order.orderCode,
        cashierName: currentUser?.firstName,
        storeName: businessName,
        storeAddress: prefs.getString('business_address'),
        storePhone: prefs.getString('business_phone'),
        customerName: widget.order.customerName,
        customerPhone: widget.order.customerPhone,
        deliveryAddress: widget.order.deliveryAddress,
        tableName: widget.order.tableName,
        numberOfPersons: widget.order.numberOfPersons,
        orderType: widget.order.type,
        isReprint: true,
      );

      final database = ref.read(databaseProvider);
      await database.customStatement(
        'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
        [ticket.ticketId!],
      );
    } catch (e) {
      _logger.error('Reprint failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

}




