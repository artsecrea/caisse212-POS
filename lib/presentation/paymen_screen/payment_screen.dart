import 'dart:async' show unawaited;

import 'package:flutter/gestures.dart' show GestureBinding, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/error_text.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/order_models.dart';
import '../../domain/models/order_money.dart';
import '../../domain/models/split_bill.dart';
import '../../core/enums.dart';
import '../../providers/order_provider.dart';
import '../../providers/ticket_provider.dart';
import '../../services/ticket_settlement_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/network_provider.dart';
import '../../services/permission_service.dart';
import '../../services/activity_log_service.dart';
import '../widgets/print_status_indicator.dart';
import '../widgets/adaptive_text_field.dart';
import '../widgets/cash_pad.dart';
import '../widgets/print_options_dialog.dart';
import '../../utils/snackbar_helper.dart';

/// The delivery fee a ticket still has to collect.
///
/// An order carries at most one delivery charge however many ways it is
/// divided: it rides the first settlement, so once anything on the order is
/// paid the remaining tickets collect nothing. Charging it per ticket would
/// bill a split table for delivery two or three times over.
///
/// [moneyPartsPaid]: a split-by-amount part is a settlement too, though it
/// is not one of [allTickets].
double deliveryFeeToCollect(
  double orderFee,
  List<TicketData> allTickets, {
  bool moneyPartsPaid = false,
}) {
  if (orderFee <= 0) return 0.0;
  if (moneyPartsPaid) return 0.0;
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
///
/// [moneyCredit] is what split-by-amount parts have already paid towards
/// the bill; it comes off the ticket's own total.
double? exactAmountDueFor(
  TicketData? ticket,
  List<TicketData> allTickets, {
  required double orderDeliveryFee,
  double moneyCredit = 0,
}) {
  if (ticket == null || ticket.isPaid || ticket.items.isEmpty) return null;
  final payable =
      ticketDueAfterCredit(ticket.total, moneyCredit) +
      deliveryFeeToCollect(
        orderDeliveryFee,
        allTickets,
        moneyPartsPaid: moneyCredit > 0,
      );
  return payable > 0 ? payable : null;
}

/// What a ticket still owes once split-by-amount parts are taken off it.
double ticketDueAfterCredit(double ticketTotal, double moneyCredit) {
  final due = roundMoney(ticketTotal - moneyCredit);
  return due < 0 ? 0.0 : due;
}

/// One bar of a split-by-amount still to collect. [part] is the EQUAL part
/// number it stands for; null for a custom amount's rest, or anything the
/// plan does not cover.
typedef UpcomingPart = ({int? part, double amount});

/// A split-by-amount being collected: which group, how it divides, which
/// parts are already in, and the bar the pad is currently set up to take.
class MoneySplitPlan {
  final String groupId;
  final SplitMode mode;

  /// EQUAL: how many parts, and the bill they are cut from.
  final int parts;
  final double base;

  /// EQUAL: the 1-based parts already paid. Tables settle in whatever order
  /// people reach for their wallets, so this is a set, not a counter.
  final Set<int> paidParts;

  /// Index into [upcoming] of the bar the pad collects. The cashier picks
  /// it by tapping a bar; it falls back to the first one.
  final int selected;

  /// AMOUNT: what the cashier typed for this part.
  final double customAmount;

  const MoneySplitPlan({
    required this.groupId,
    required this.mode,
    required this.parts,
    required this.base,
    this.paidParts = const {},
    this.selected = 0,
    this.customAmount = 0,
  });

  /// The bars left to pay, in order, adding up to [due]: the last one takes
  /// the exact remainder, and whatever the plan does not cover is one more.
  List<UpcomingPart> upcoming(double due) {
    final bars = mode == SplitMode.equal
        ? <UpcomingPart>[
            for (var i = 1; i <= parts; i++)
              if (!paidParts.contains(i))
                (part: i, amount: equalPartAmount(base, parts, i)),
          ]
        : <UpcomingPart>[(part: null, amount: roundMoney(customAmount))];
    final planned = bars.fold<double>(0, (s, b) => s + b.amount);
    if (bars.isEmpty || roundMoney(due - planned) > 0.005) {
      bars.add((part: null, amount: roundMoney(due - planned)));
    } else {
      final last = bars.removeLast();
      final amount = roundMoney(due - (planned - last.amount));
      bars.add((part: last.part, amount: amount < 0 ? 0.0 : amount));
    }
    return [
      for (final b in bars)
        (part: b.part, amount: b.amount > due ? due : b.amount),
    ];
  }

  /// Whether the bar at [index] can be picked: an EQUAL split only takes
  /// its own parts, never a stray remainder.
  bool canSelect(double due, int index) {
    final bars = upcoming(due);
    if (index < 0 || index >= bars.length || bars[index].amount <= 0.005) {
      return false;
    }
    return mode != SplitMode.equal || bars[index].part != null;
  }

  /// The bar the pad collects now.
  UpcomingPart current(double due) {
    final bars = upcoming(due);
    return canSelect(due, selected) ? bars[selected] : bars.first;
  }

  /// What the pad collects now, never more than [due].
  double amountFor(double due) => current(due).amount;

  MoneySplitPlan withSelected(int index) => MoneySplitPlan(
    groupId: groupId,
    mode: mode,
    parts: parts,
    base: base,
    paidParts: paidParts,
    selected: index,
    customAmount: customAmount,
  );

  /// The plan once EQUAL [part] is in, back on the first bar; null when
  /// nothing of the plan is left to take.
  MoneySplitPlan? afterPaying(int? part) {
    if (mode != SplitMode.equal || part == null) return null;
    final paid = {...paidParts, part};
    if (paid.length >= parts) return null;
    return MoneySplitPlan(
      groupId: groupId,
      mode: mode,
      parts: parts,
      base: base,
      paidParts: paid,
    );
  }
}

/// One saved slice of a draft ticket split — see [TicketDraftSplits] for
/// what the fields mean. A plain record rather than the Drift row type so
/// [reconstructUnpaidTickets] has no database dependency and is trivial to
/// feed by hand in a test.
typedef DraftSplitRow = ({int orderProductId, int draftIndex, double quantity});

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
    tickets.add(
      TicketData(
        items: lines,
        paymentMethod: defaultMethod,
        discountPercentage: discountPercentage,
      ),
    );
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
  tickets[0] = tickets[0].copyWith(
    items: [...tickets[0].items, ...leftoverLines],
  );
  return tickets;
}

/// An open split-by-amount group as the screen rebuilds it: its id and the
/// lines its parts were paid towards (empty for parts written before a
/// ticket could be split on its own).
typedef OpenMoneyGroup = ({String groupId, List<SplitForLine> forLines});

/// Put every open split-by-amount group back on a ticket of its own, holding
/// the lines its parts were paid towards, carved out of the [unpaid] tickets
/// wherever the draft split left them.
///
/// The parts' `forLines` are the authority, not the saved draft: the draft
/// is local and can be stale after a reload from the server, while
/// `forLines` travel with the tickets. A line is found by `lineUid` when the
/// part carries one (any till), else by local row id (this till's own).
///
/// Groups paid against the same lines share one ticket. Parts written before
/// `forLines` existed paid towards the whole order, so any such group folds
/// every unpaid line into one ticket, as the screen always did for them. A
/// group none of whose lines is still unpaid — settled or removed since — is
/// left off: crediting it to some other ticket would discount the wrong
/// customer.
///
/// Pure — exercised in `test/money_split_tickets_test.dart`.
List<TicketData> attachMoneyGroups(
  List<TicketData> unpaid,
  List<OpenMoneyGroup> groups, {
  required Map<int, String?> lineUidByRowId,
}) {
  if (groups.isEmpty || unpaid.isEmpty) return unpaid;

  if (groups.any((g) => g.forLines.isEmpty)) {
    return [
      unpaid.first.copyWith(
        items: [for (final t in unpaid) ...t.items],
        moneyGroups: [for (final g in groups) g.groupId],
      ),
    ];
  }

  final rowIdByUid = {
    for (final e in lineUidByRowId.entries)
      if (e.value != null) e.value!: e.key,
  };
  int? rowOf(SplitForLine l) => l.lineUid != null
      ? rowIdByUid[l.lineUid]
      : (lineUidByRowId.containsKey(l.localLineId) ? l.localLineId : null);

  // Same lines, same ticket: a second split started on a ticket whose first
  // one was cut short lists exactly the lines the first one did.
  final buckets = <String, List<OpenMoneyGroup>>{};
  for (final g in groups) {
    final claims = [
      for (final l in g.forLines)
        if (rowOf(l) case final row?) '$row:${l.qty}',
    ]..sort();
    buckets.putIfAbsent(claims.join(','), () => []).add(g);
  }

  final tickets = [
    for (final t in unpaid) t.copyWith(items: List<TicketLine>.from(t.items)),
  ];
  final carved = <TicketData>[];
  for (final entry in buckets.entries) {
    if (entry.key.isEmpty) continue;
    final pieces = <TicketLine>[];
    for (final l in entry.value.first.forLines) {
      final row = rowOf(l);
      if (row == null) continue;
      for (final piece in _carveRow(tickets, row, l.qty)) {
        final at = pieces.indexWhere(
          (p) => canCombineLines(p.item, piece.item),
        );
        if (at == -1) {
          pieces.add(piece);
        } else {
          pieces[at] = pieces[at].mergedWith(piece);
        }
      }
    }
    if (pieces.isEmpty) continue;
    carved.add(
      TicketData(
        items: pieces,
        paymentMethod: unpaid.first.paymentMethod,
        discountPercentage: unpaid.first.discountPercentage,
        moneyGroups: [for (final g in entry.value) g.groupId],
      ),
    );
  }

  return [...carved, ...tickets.where((t) => t.items.isNotEmpty)];
}

/// Take up to [qty] of row [rowId] off whichever [tickets] hold it, in
/// order, and return what was taken as lines of their own. Mutates the
/// tickets' (already copied) item lists.
List<TicketLine> _carveRow(List<TicketData> tickets, int rowId, double qty) {
  final taken = <TicketLine>[];
  var need = qty;
  for (var t = 0; t < tickets.length && need > _qtyEpsilon; t++) {
    final items = tickets[t].items;
    for (var i = 0; i < items.length && need > _qtyEpsilon; i++) {
      final line = items[i];
      final held = line.sources
          .where((s) => s.rowId == rowId)
          .fold<double>(0, (s, src) => s + src.quantity);
      if (held <= _qtyEpsilon) continue;
      final take = held < need ? held : need;
      var left = take;
      final kept = <LineSource>[];
      for (final s in line.sources) {
        if (s.rowId != rowId || left <= _qtyEpsilon) {
          kept.add(s);
        } else if (s.quantity <= left + _qtyEpsilon) {
          left -= s.quantity;
        } else {
          kept.add((rowId: s.rowId, quantity: s.quantity - left));
          left = 0;
        }
      }
      taken.add(
        TicketLine(
          item: line.item.copyWith(quantity: take),
          sources: [(rowId: rowId, quantity: take)],
        ),
      );
      final rest = line.item.quantity - take;
      if (rest > _qtyEpsilon) {
        items[i] = line.copyWith(
          item: line.item.copyWith(quantity: rest),
          sources: kept,
        );
      } else {
        items.removeAt(i);
        i--;
      }
      need -= take;
    }
  }
  return taken;
}

/// Quantities are doubles because weighed goods exist; comparisons against
/// zero have to tolerate the rounding that division introduces.
const double _qtyEpsilon = TicketSettlementService.qtyEpsilon;

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
        kept.add((
          rowId: source.rowId,
          quantity: source.quantity - outstanding,
        ));
        outstanding = 0;
      }
    }

    return (
      copyWith(
        item: item.copyWith(quantity: item.quantity - take),
        sources: kept,
      ),
      copyWith(
        item: item.copyWith(quantity: take),
        sources: taken,
      ),
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
  final parts =
      item.components
          .map(
            (c) => '${c.componentId}:${c.quantity}:${c.price}:${c.isSpecial}',
          )
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

  /// Split-by-amount groups running on this ticket. Their paid parts are
  /// credit off [total], and while there is one the ticket's lines are
  /// locked: the parts were paid towards exactly these lines.
  final List<String> moneyGroups;

  TicketData({
    this.ticketId,
    this.ticketNum,
    required this.items,
    this.paymentMethod = TransactionType.cash,
    this.isPaid = false,
    this.printCount = 0,
    this.discountPercentage = 0.0,
    this.moneyGroups = const [],
  });

  TicketData copyWith({
    int? ticketId,
    String? ticketNum,
    List<TicketLine>? items,
    TransactionType? paymentMethod,
    bool? isPaid,
    int? printCount,
    double? discountPercentage,
    List<String>? moneyGroups,
  }) {
    return TicketData(
      ticketId: ticketId ?? this.ticketId,
      ticketNum: ticketNum ?? this.ticketNum,
      items: items ?? this.items,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      isPaid: isPaid ?? this.isPaid,
      printCount: printCount ?? this.printCount,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      moneyGroups: moneyGroups ?? this.moneyGroups,
    );
  }

  double get subtotal => items.fold<double>(
    0.0,
    (sum, l) => sum + (l.item.subtotalPerItem * l.item.quantity),
  );
  double get itemDiscount =>
      items.fold<double>(0.0, (sum, l) => sum + l.item.totalDiscount);
  double get totalTva =>
      items.fold<double>(0.0, (sum, l) => sum + l.item.totalTva);

  double get _linesNet =>
      items.fold<double>(0.0, (sum, l) => sum + l.item.totalPrice);

  double get manualDiscountAmount {
    final base = _linesNet;
    if (base <= 0 || discountPercentage <= 0) return 0.0;
    return orderDiscountAmount(base, discountPercentage);
  }

  double get total {
    final result = _linesNet - manualDiscountAmount;
    return result < 0 ? 0.0 : result;
  }
}

/// Calculator state
class CalculatorState {
  final String display;
  final double enteredAmount;

  CalculatorState({this.display = '0', this.enteredAmount = 0.0});

  CalculatorState copyWith({String? display, double? enteredAmount}) {
    return CalculatorState(
      display: display ?? this.display,
      enteredAmount: enteredAmount ?? this.enteredAmount,
    );
  }
}

// Providers — autoDispose so state resets when dialog closes
final ticketsProvider = StateProvider.autoDispose<List<TicketData>>(
  (ref) => [],
);
final calculatorProvider = StateProvider.autoDispose<CalculatorState>(
  (ref) => CalculatorState(),
);
final selectedTicketProvider = StateProvider.autoDispose<int?>((ref) => null);

/// Modern Payment Screen - Rebuilt for touch screens
class PaymentScreen extends ConsumerStatefulWidget {
  final CurrentOrder order;

  /// Force the ticket-division grid open for this visit, regardless of
  /// [AppSettings.alwaysShowTicketSplit] or how many tickets the order
  /// starts with — the long-press gesture on Proceed/Pay that lets a
  /// cashier divide an order into tickets before paying anything.
  final bool forceSplitOpen;

  /// Started when Pay was tapped; only used to log how long opening took.
  final Stopwatch? perfSince;

  const PaymentScreen({
    super.key,
    required this.order,
    this.forceSplitOpen = false,
    this.perfSince,
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

  /// The sideways strip of ticket columns in [_buildTicketsArea] — keyed
  /// and controller-driven so a drag can auto-scroll it, which a plain
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

  /// Paid parts of each open split-by-amount group, by group id: tickets
  /// whose `split` is AMOUNT/EQUAL and that claim no line. The line-built
  /// [ticketsProvider] never shows them; their money is credit off the
  /// ticket that lists the group in [TicketData.moneyGroups].
  Map<String, List<Ticket>> _groupParts = const {};

  /// The split-by-amount each group's pad is collecting, by group id.
  Map<String, MoneySplitPlan> _plans = const {};

  List<Ticket> _partsOf(TicketData ticket) =>
      [for (final g in ticket.moneyGroups) ...?_groupParts[g]]
        ..sort((a, b) => a.id.compareTo(b.id));

  double _creditOf(TicketData ticket) =>
      roundMoney(_partsOf(ticket).fold<double>(0, (s, t) => s + t.amount));

  /// The VAT inside [amount] when it is only a share of [ticket]'s total.
  double _tvaShare(TicketData ticket, double amount) => ticket.total > 0.005
      ? roundMoney(ticket.totalTva * amount / ticket.total)
      : 0.0;

  MoneySplitPlan? _planOf(TicketData ticket) {
    for (final g in ticket.moneyGroups) {
      if (_plans[g] case final plan?) return plan;
    }
    return null;
  }

  bool get _anyMoneyPartPaid => _groupParts.values.any((p) => p.isNotEmpty);

  /// Forget [groups] once their ticket is paid in full.
  void _dropGroups(Iterable<String> groups) {
    _groupParts = {..._groupParts}..removeWhere((k, _) => groups.contains(k));
    _plans = {..._plans}..removeWhere((k, _) => groups.contains(k));
  }

  @override
  void initState() {
    super.initState();
    if (widget.forceSplitOpen) _splitPanelOverride = true;
    final tInit = widget.perfSince?.elapsedMilliseconds;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tFrame = widget.perfSince?.elapsedMilliseconds;
      await _initializeTickets();
      if (widget.perfSince case final sw?) {
        _logger.info('[PERF] payment screen: created=${tInit}ms '
            'firstFrame=${tFrame}ms ticketsReady=${sw.elapsedMilliseconds}ms '
            '(since Pay tap)');
      }
    });
  }

  @override
  void dispose() {
    _ticketsScrollController.dispose();
    super.dispose();
  }

  /// Auto-scroll the tickets strip while a ticket line is being dragged near
  /// its left or right edge.
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

    final left = box.localToGlobal(Offset.zero).dx;
    final right = left + box.size.width;
    const edgeZone = 80.0; // px from the edge that starts scrolling
    const step = 18.0; // px nudged per drag-update tick

    double delta = 0;
    if (globalPosition.dx < left + edgeZone) {
      delta = -step;
    } else if (globalPosition.dx > right - edgeZone) {
      delta = step;
    }
    if (delta == 0) return;

    final target = (_ticketsScrollController.offset + delta).clamp(
      0.0,
      _ticketsScrollController.position.maxScrollExtent,
    );
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

        tickets.add(
          TicketData(
            ticketId: ticketId,
            ticketNum: ticketNumStr,
            items: ticketItems.map(TicketLine.whole).toList(),
            paymentMethod: TransactionType
                .cash, // Will be overridden by actual payment method if available
            isPaid: true,
            discountPercentage: widget.order.discountPercentage,
          ),
        );
      }
    });

    // Unpaid items: rebuild whatever draft split the cashier last saved for
    // this order (see [TicketDraftSplits]) rather than always collapsing
    // everything back into one ticket. An order nobody has split yet, or
    // whose draft turns out stale, falls through to that same one-ticket
    // default inside the helper.
    // A cancelled line is shown on the order but owed by nobody, so it never
    // goes on a ticket.
    final unpaidItems =
        (grouped[null] ?? const <OrderItem>[]).where((i) => i.isOwed).toList();
    if (unpaidItems.isNotEmpty) {
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.addAll(
        await _reconstructUnpaidTickets(unpaidItems, defaultMethod),
      );
    }

    // Parts already paid by amount go back under the ticket they were paid
    // towards — rebuilt from the parts themselves, so a reload from the
    // server or another till's parts land in the right place.
    final moneyParts = await _loadMoneyParts();
    final groupParts = <String, List<Ticket>>{};
    final groups = <OpenMoneyGroup>[];
    for (final part in moneyParts) {
      final split = SplitDetails.decode(part.splitDetails);
      if (split == null) continue;
      final list = groupParts.putIfAbsent(split.groupId, () {
        groups.add((groupId: split.groupId, forLines: split.forLines));
        return [];
      });
      list.add(part);
    }
    if (groups.isNotEmpty) {
      final unpaid = tickets.where((t) => !t.isPaid).toList();
      final attached = attachMoneyGroups(
        unpaid,
        groups,
        lineUidByRowId: await _lineUids(),
      );
      tickets
        ..removeWhere((t) => !t.isPaid)
        ..addAll(attached);
    }

    // Ensure at least one ticket exists
    if (tickets.isEmpty) {
      final defaultMethod = TransactionType.fromString(
        ref.read(settingsProvider).defaultPaymentMethod,
      );
      tickets.add(
        TicketData(
          items: [],
          paymentMethod: defaultMethod,
          discountPercentage: widget.order.discountPercentage,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _groupParts = groupParts;
      _plans = {
        for (final e in groupParts.entries)
          if (_resumeMoneyPlan(e.value) case final plan?) e.key: plan,
      };
    });
    ref.read(ticketsProvider.notifier).state = tickets;

    // On a divided order the pad stays away until a ticket is tapped, so the
    // strip has the whole width to show who owes what. With a single unpaid
    // ticket there is nothing to choose, so it opens on the pad and an
    // ordinary sale stays one tap — unless the cashier came here to divide.
    final unpaidIndices = [
      for (int i = 0; i < tickets.length; i++)
        if (!tickets[i].isPaid) i,
    ];
    final int? initialIndex;
    if (!_splitVisible(tickets, ref.read(settingsProvider))) {
      initialIndex = unpaidIndices.isNotEmpty
          ? unpaidIndices.first
          : (tickets.isEmpty ? null : 0);
    } else if (unpaidIndices.length == 1 && !widget.forceSplitOpen) {
      initialIndex = unpaidIndices.first;
    } else {
      initialIndex = null;
    }
    ref.read(selectedTicketProvider.notifier).state = initialIndex;

    _resetCalculatorFor(initialIndex, tickets);
  }

  /// This order's paid, non-cancelled split-by-amount tickets, oldest first.
  /// Includes parts another till took, once the payment pull brought them.
  Future<List<Ticket>> _loadMoneyParts() async {
    final orderId = widget.order.orderId;
    if (orderId == null) return const [];
    try {
      return await ref.read(orderRepositoryProvider).moneySplitParts(orderId);
    } catch (e) {
      _logger.error('Failed to load split parts: $e');
      return const [];
    }
  }

  /// Every row of this order with its cross-till `lineUid`.
  Future<Map<int, String?>> _lineUids() async {
    final orderId = widget.order.orderId;
    if (orderId == null) return const {};
    try {
      final database = ref.read(databaseProvider);
      final rows = await (database.select(
        database.orderProducts,
      )..where((p) => p.orderId.equals(orderId))).get();
      return {for (final r in rows) r.id: r.lineUid};
    } catch (e) {
      _logger.error('Failed to load line uids: $e');
      return const {};
    }
  }

  /// What a money part pays towards: [ticket]'s lines, by local row and by
  /// the `lineUid` every till shares.
  Future<List<SplitForLine>> _forLinesOf(TicketData ticket) async {
    final uids = await _lineUids();
    return [
      for (final line in ticket.items)
        for (final s in line.sources)
          if (s.quantity > 0)
            SplitForLine(
              localLineId: s.rowId,
              lineUid: uids[s.rowId],
              qty: s.quantity,
            ),
    ];
  }

  /// An EQUAL split left half-paid picks up with the parts still out when
  /// the screen is reopened — on this till or another. Parts may have been
  /// paid in any order.
  MoneySplitPlan? _resumeMoneyPlan(List<Ticket> parts) {
    if (parts.isEmpty) return null;
    final last = SplitDetails.decode(parts.last.splitDetails);
    if (last == null || last.mode != SplitMode.equal) return null;
    final paid = {
      for (final t in parts)
        if (SplitDetails.decode(t.splitDetails) case final d?
            when d.mode == SplitMode.equal)
          d.part,
    };
    if (paid.length >= last.parts) return null;
    return MoneySplitPlan(
      groupId: last.groupId,
      mode: SplitMode.equal,
      parts: last.parts,
      base: last.orderTotal,
      paidParts: paid,
    );
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
        final rows = await (database.select(
          database.ticketDraftSplits,
        )..where((t) => t.orderId.equals(orderId))).get();
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
        await (database.delete(
          database.ticketDraftSplits,
        )..where((t) => t.orderId.equals(orderId))).go();
        final unpaid = tickets.where((t) => !t.isPaid).toList();
        for (var idx = 0; idx < unpaid.length; idx++) {
          for (final line in unpaid[idx].items) {
            for (final source in line.sources) {
              if (source.quantity <= 0) continue;
              await database
                  .into(database.ticketDraftSplits)
                  .insert(
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
    // A ticket being shared by amount shows its parts on the strip only.
    if (tickets.any((t) => !t.isPaid && t.moneyGroups.isNotEmpty)) return true;
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
  double _deliveryFeeFor(List<TicketData> allTickets) => deliveryFeeToCollect(
    widget.order.deliveryFeeAmount,
    allTickets,
    moneyPartsPaid: _anyMoneyPartPaid,
  );

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
    final maxWidth = showSplit
        ? screen.width * 0.98
        : (screen.width * 0.98).clamp(0.0, 720.0);

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
                      ? _buildSplitBody(tickets)
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

  /// The divided layout: the tickets strip across the full width, and the
  /// pad sliding in beside it only while a ticket is selected.
  Widget _buildSplitBody(List<TicketData> tickets) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedTicketProvider);
    final open = selected != null && selected < tickets.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = (constraints.maxWidth * 0.42).clamp(360.0, 520.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _buildTicketsArea(tickets)),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: open ? panelWidth : 0,
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: theme.dividerColor)),
              ),
              child: ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  minWidth: panelWidth,
                  maxWidth: panelWidth,
                  child: open
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPanelBar(selected, tickets[selected]),
                            Expanded(child: _buildPaymentPanel()),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Which ticket the pad is for, and the way to put the pad away.
  Widget _buildPanelBar(int index, TicketData ticket) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 4, 4),
      color: ticket.isPaid
          ? Colors.green.withValues(alpha: 0.12)
          : theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(
            ticket.isPaid ? Icons.check_circle_rounded : Icons.receipt_rounded,
            size: 18,
            color: ticket.isPaid
                ? Colors.green.shade700
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ticket.ticketNum != null
                  ? '#${ticket.ticketNum}'
                  : '${l10n.translate('ticket')} ${index + 1}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _isProcessing ? null : () => _selectTicket(null),
            icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
            tooltip: l10n.translate('close'),
          ),
        ],
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

  Widget _buildHeader({
    required bool showSplit,
    required List<TicketData> tickets,
  }) {
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
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
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
                : () {
                    setState(() => _splitPanelOverride = !showSplit);
                    // Without the strip there is no ticket to tap, so the
                    // pad has to come up on its own.
                    if (showSplit &&
                        tickets.isNotEmpty &&
                        ref.read(selectedTicketProvider) == null) {
                      _selectTicket(
                        tickets
                            .indexWhere((t) => !t.isPaid)
                            .clamp(0, tickets.length - 1),
                      );
                    }
                  },
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
              disabledForegroundColor: theme.colorScheme.onPrimaryContainer
                  .withValues(alpha: 0.35),
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

  /// The order the strip shows [tickets] in: unpaid first, paid at the end.
  ///
  /// Only the on-screen order. Every handler keeps working with the real
  /// [ticketsProvider] index (it is also the ticket's label and its part
  /// number in the split pushed to the server), so a ticket that gets paid
  /// slides to the end without anything else having to be renumbered.
  List<int> _displayOrder(List<TicketData> tickets) => [
    for (int i = 0; i < tickets.length; i++)
      if (!tickets[i].isPaid) i,
    for (int i = 0; i < tickets.length; i++)
      if (tickets[i].isPaid) i,
  ];

  static const _ticketColumnGap = 10.0;
  double _ticketColumnWidth = 260;

  /// Bring the ticket at real index [index] into view on the strip.
  void _scrollTicketIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ticketsScrollController.hasClients) return;
      final position = _displayOrder(ref.read(ticketsProvider)).indexOf(index);
      if (position < 0) return;
      final scroll = _ticketsScrollController.position;
      final start = position * (_ticketColumnWidth + _ticketColumnGap);
      final end = start + _ticketColumnWidth;
      double? target;
      if (start < scroll.pixels) {
        target = start;
      } else if (end > scroll.pixels + scroll.viewportDimension) {
        target = end - scroll.viewportDimension + 12;
      }
      if (target == null) return;
      _ticketsScrollController.animateTo(
        target.clamp(0.0, scroll.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _buildTicketsArea(List<TicketData> tickets) {
    final theme = Theme.of(context);
    final hasUnpaidTicketsWithItems = tickets.any(
      (t) => !t.isPaid && t.items.isNotEmpty,
    );
    final l10n = AppLocalizations.of(context)!;
    final blockReason = _blockNewTicketReason(l10n);
    final paidCount = tickets.where((t) => t.isPaid).length;
    final order = _displayOrder(tickets);

    final secondaryStyle = ElevatedButton.styleFrom(
      disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
      disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    return Column(
      children: [
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Print every divided ticket's slip in one go. Only once the
              // order is actually divided — on a single ticket this would be
              // the order ticket the main screen already printed.
              if (tickets.where((t) => !t.isPaid && t.items.isNotEmpty).length >
                  1)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ElevatedButton.icon(
                    onPressed: _isPrintingDraft ? null : _printAllDraftTickets,
                    icon: _isPrintingDraft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_rounded, size: 18),
                    label: Text(
                      l10n.translate('print_all_tickets'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    style: secondaryStyle,
                  ),
                ),
              Tooltip(
                message: blockReason ?? '',
                child: ElevatedButton.icon(
                  onPressed: blockReason == null ? _addNewTicket : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    l10n.translate('new_ticket'),
                    style: const TextStyle(fontSize: 14),
                  ),
                  style: secondaryStyle,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: hasUnpaidTicketsWithItems && !_isProcessing
                    ? _payAllTickets
                    : null,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(
                  l10n.translate('pay_all'),
                  style: const TextStyle(fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Hint bar — the gestures the strip supports, or whatever constraint
        // is currently blocking a new ticket.
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
                    ? theme.colorScheme.onSurfaceVariant
                    : Colors.orange.shade700,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  blockReason ?? l10n.translate('ticket_division_hint'),
                  style: TextStyle(
                    fontSize: 11,
                    color: blockReason == null
                        ? theme.colorScheme.onSurfaceVariant
                        : Colors.orange.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Tickets side by side, unpaid first. Columns stretch to share the
        // width when they all fit and keep a readable minimum when they don't,
        // at which point the strip scrolls sideways.
        Expanded(
          child: tickets.isEmpty
              ? Center(child: Text(l10n.translate('no_tickets')))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const pad = 12.0;
                    final available = constraints.maxWidth - pad * 2;
                    final fit =
                        (available - _ticketColumnGap * (order.length - 1)) /
                        order.length;
                    _ticketColumnWidth = fit.clamp(240.0, 360.0);
                    // A wheel only scrolls along its own axis, so a plain mouse
                    // would never move a sideways strip. Lines lists that can
                    // still scroll claim the wheel first; elsewhere it moves
                    // the strip.
                    return Listener(
                      onPointerSignal: (event) {
                        if (event is! PointerScrollEvent ||
                            event.scrollDelta.dx != 0 ||
                            !_ticketsScrollController.hasClients) {
                          return;
                        }
                        GestureBinding.instance.pointerSignalResolver.register(
                          event,
                          (e) {
                            final position = _ticketsScrollController.position;
                            final target =
                                (position.pixels +
                                        (e as PointerScrollEvent)
                                            .scrollDelta
                                            .dy)
                                    .clamp(0.0, position.maxScrollExtent);
                            if (target != position.pixels) {
                              _ticketsScrollController.jumpTo(target);
                            }
                          },
                        );
                      },
                      child: Scrollbar(
                        controller: _ticketsScrollController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          key: _ticketsListKey,
                          controller: _ticketsScrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(pad, 4, pad, 14),
                          itemCount: order.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: _ticketColumnGap),
                          itemBuilder: (context, position) {
                            final index = order[position];
                            return SizedBox(
                              key: ValueKey('ticket-col-$index'),
                              width: _ticketColumnWidth,
                              child: _buildTicketColumn(index, tickets[index]),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// One ticket as a column: who and how much on top, its lines in the
  /// middle (scrolling inside the column when there are many), tender and
  /// slip at the bottom. Tapping it opens the pad for it; tapping it again
  /// puts the pad away.
  Widget _buildTicketColumn(int index, TicketData ticket) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = ref.watch(selectedTicketProvider) == index;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final tickets = ref.watch(ticketsProvider);
    final l10n = AppLocalizations.of(context)!;
    final accent = ticket.isPaid
        ? Colors.green.shade700
        : theme.colorScheme.primary;
    // Being shared out by amount: its lines stay put and it shows what is
    // left once the parts already paid are off.
    final shared = !ticket.isPaid && ticket.moneyGroups.isNotEmpty;
    final credit = shared ? _creditOf(ticket) : 0.0;

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => !ticket.isPaid && !shared,
      onAcceptWithDetails: (details) => _moveItemToTicket(details.data, index),
      builder: (context, candidateData, rejectedData) {
        final isDraggingOver = candidateData.isNotEmpty && !ticket.isPaid;

        return Material(
          color: ticket.isPaid
              ? (isDark
                    ? Colors.green.shade900.withValues(alpha: 0.3)
                    : Colors.green.shade50)
              : (isDraggingOver
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : (isSelected
                          ? theme.colorScheme.primaryContainer
                          : theme.cardColor)),
          elevation: isSelected ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isDraggingOver || isSelected
                  ? theme.colorScheme.primary
                  : (ticket.isPaid ? Colors.green : theme.dividerColor),
              width: isDraggingOver ? 3 : (isSelected ? 2 : 1),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _selectTicket(index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Identity and total
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                  child: Row(
                    children: [
                      Icon(
                        ticket.isPaid
                            ? Icons.check_circle_rounded
                            : Icons.receipt_rounded,
                        size: 20,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket.ticketNum != null
                                  ? '#${ticket.ticketNum}'
                                  : '${l10n.translate('ticket')} ${index + 1}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: ticket.isPaid ? accent : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              ticket.isPaid
                                  ? l10n.translate('paid')
                                  : '${ticket.items.length} ${l10n.translate('items')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: ticket.isPaid
                                    ? accent
                                    : theme.colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!ticket.isPaid && !shared && tickets.length > 1)
                        IconButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _removeTicket(index),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: l10n.translate('remove_ticket'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                if (shared)
                  _buildSharedTicketBand(
                    theme,
                    l10n,
                    currencyFormatter,
                    index,
                    ticket,
                  ),

                // ── Its lines
                Expanded(
                  child: ticket.items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.move_down_rounded,
                                  size: 32,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.translate('drag_items_here'),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.45),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                          itemCount: ticket.items.length,
                          itemBuilder: (context, i) =>
                              _buildDraggableTicketItem(
                                index,
                                i,
                                ticket.items[i],
                                ticket.isPaid || shared,
                              ),
                        ),
                ),

                // ── Money
                Divider(height: 1, color: theme.dividerColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      if (!ticket.isPaid) ...[
                        Icon(
                          _getPaymentIcon(ticket.paymentMethod),
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            currencyFormatter.format(
                              shared
                                  ? ticketDueAfterCredit(ticket.total, credit)
                                  : ticket.total,
                            ),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                        ),
                      ),
                      if (!ticket.isPaid && ticket.items.isNotEmpty)
                        SizedBox(
                          width: 112,
                          child: _buildTicketPrintButton(ticket),
                        ),
                    ],
                  ),
                ),
                if (!ticket.isPaid && !shared && ticket.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: _buildSplitStartButton(index, ticket),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// On a ticket being shared out by amount: one bar per part across the
  /// full width — paid ones filled with their amount and how they were paid
  /// (one person in cash and the next by card is common), the part the pad
  /// is collecting outlined, the rest after it — and the one action that
  /// applies right now.
  Widget _buildSharedTicketBand(
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyFormatter formatter,
    int index,
    TicketData ticket,
  ) {
    final plan = _planOf(ticket);
    final paidInPlan = plan == null
        ? 0
        : (_groupParts[plan.groupId]?.length ?? 0);

    final String actionLabel;
    final VoidCallback action;
    if (plan != null && paidInPlan == 0) {
      actionLabel = l10n.translate('cancel');
      action = () => _cancelMoneyPlan(index);
    } else if (plan != null) {
      actionLabel = l10n.translate('split_pay_rest');
      action = () => _cancelMoneyPlan(index);
    } else {
      actionLabel = l10n.translate('split_part_next');
      action = () => _startSplitOn(index);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      color: theme.colorScheme.primary.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  l10n.translate('split_shared_ticket'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                height: 32,
                child: TextButton(
                  onPressed: _isProcessing ? null : action,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildSplitSegments(theme, l10n, formatter, index, ticket),
        ],
      ),
    );
  }

  /// The parts of [ticket]'s split as equal-width bars filling the row.
  /// Tapping a part still to pay sets the pad up for that one.
  Widget _buildSplitSegments(
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyFormatter formatter,
    int index,
    TicketData ticket,
  ) {
    final due = ticketDueAfterCredit(ticket.total, _creditOf(ticket));
    final plan = _planOf(ticket);

    final upcoming = plan != null
        ? plan.upcoming(due)
        : <UpcomingPart>[(part: null, amount: due)];
    final currentIndex = plan != null && plan.canSelect(due, plan.selected)
        ? plan.selected
        : 0;

    Widget bar({
      required double amount,
      String? method,
      required bool current,
      VoidCallback? onTap,
    }) {
      final paid = method != null;
      final fg = paid
          ? Colors.white
          : (current
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant);
      return Expanded(
        child: Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: paid
                ? Colors.green.shade600
                : (current
                      ? theme.colorScheme.primary.withValues(alpha: 0.10)
                      : theme.colorScheme.surface),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: paid
                  ? Colors.green.shade600
                  : (current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant),
              width: current ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatter.format(amount),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                    ),
                    Text(
                      paid
                          ? l10n.translate(method.toLowerCase())
                          : l10n.translate(current ? 'split_now' : 'remaining'),
                      style: TextStyle(fontSize: 10, color: fg),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        for (final part in _partsOf(ticket))
          bar(amount: part.amount, method: part.paymentMethod, current: false),
        for (var i = 0; i < upcoming.length; i++)
          if (upcoming[i].amount > 0.005)
            bar(
              amount: upcoming[i].amount,
              current: i == currentIndex,
              onTap: plan != null && plan.canSelect(due, i) && !_isProcessing
                  ? () => _selectSplitPart(index, plan, i)
                  : null,
            ),
      ],
    );
  }

  /// Collect bar [part] of ticket [index]'s split next — whichever person
  /// is ready pays, not the next in line. Opens the pad on that ticket.
  void _selectSplitPart(int index, MoneySplitPlan plan, int part) {
    if (ref.read(selectedTicketProvider) != index) _selectTicket(index);
    if (plan.selected == part) return;
    setState(() => _plans = {..._plans, plan.groupId: plan.withSelected(part)});
    // The keyed tender was against the other part's amount.
    _resetCalculatorFor(index, ref.read(ticketsProvider));
  }

  /// Split-by-amount button for an unpaid ticket — no icon, just what it does.
  Widget _buildSplitStartButton(int index, TicketData ticket) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 40,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isProcessing ? null : () => _startSplitOn(index),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          l10n.translate('split_by_amount_short'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Open the pad on ticket [index] and ask how to split it by amount.
  void _startSplitOn(int index) {
    final tickets = ref.read(ticketsProvider);
    if (index >= tickets.length || tickets[index].isPaid) return;
    if (ref.read(selectedTicketProvider) != index) {
      ref.read(selectedTicketProvider.notifier).state = index;
      _resetCalculatorFor(index, tickets);
    }
    _openMoneySplitDialog(tickets[index]);
  }

  Widget _buildDraggableTicketItem(
    int ticketIndex,
    int itemIndex,
    TicketLine line,
    bool isPaid,
  ) {
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
            !(details.data['ticketIndex'] == ticketIndex &&
                details.data['itemIndex'] == itemIndex);
      },
      onAcceptWithDetails: (details) {
        _mergeItems(details.data, ticketIndex, itemIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isMergeTarget = candidateData.isNotEmpty;

        return Draggable<Map<String, dynamic>>(
          // Sideways picks the line up — the other tickets sit beside this
          // one. Up and down is left to the ticket's own list, so a long
          // ticket scrolls instead of grabbing whatever line is under the
          // finger.
          affinity: Axis.horizontal,
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
            onTap: item.quantity > 1
                ? () => _showCustomDivideDialog(line, ticketIndex, itemIndex)
                : null,
            onLongPress: item.quantity > 1
                ? () => _showCustomDivideDialog(line, ticketIndex, itemIndex)
                : null,
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
                    Icon(
                      Icons.merge_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.3,
                        ),
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
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.5,
                  )
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
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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

  /// The tender tiles. Icon beside the label when a tile is wide enough,
  /// stacked when it is not; either way the content is scaled down rather
  /// than allowed to overflow — the old fixed icon+label column was a few
  /// pixels taller than the 48px compact row and striped on short screens.
  Widget _buildPaymentMethodButtons(int index, TicketData ticket) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    const methods = TransactionType.pickable;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = constraints.maxWidth / methods.length;
        final inline = tileWidth >= 104;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < methods.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: i == 0 ? 0 : 3,
                    end: i == methods.length - 1 ? 0 : 3,
                  ),
                  child: _paymentMethodTile(
                    theme,
                    l10n,
                    index,
                    methods[i],
                    selected: ticket.paymentMethod == methods[i],
                    inline: inline,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _paymentMethodTile(
    ThemeData theme,
    AppLocalizations l10n,
    int index,
    TransactionType method, {
    required bool selected,
    required bool inline,
  }) {
    final fg = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final icon = Icon(_getPaymentIcon(method), size: 22, color: fg);
    final label = Text(
      l10n.translate(method.value.toLowerCase()),
      style: TextStyle(
        fontSize: inline ? 14 : 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: fg,
      ),
      maxLines: 1,
    );

    return Material(
      color: selected
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : theme.dividerColor,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _updatePaymentMethod(index, method),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: inline
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, const SizedBox(width: 6), label],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [icon, label],
                    ),
            ),
          ),
        ),
      ),
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
      case TransactionType.exchange:
        return Icons.swap_horiz_rounded;
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
          Icon(
            Icons.inbox_rounded,
            size: 80,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.translate('ticket_has_no_items'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
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
              label: Text(
                AppLocalizations.of(context)!.translate('print_receipt'),
                style: const TextStyle(fontSize: 18),
              ),
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
    ThemeData theme,
    AppLocalizations l10n,
    CurrencyFormatter formatter,
  ) {
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
          const Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: Colors.deepOrange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.translate('balance_due'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (paid > 0)
                  Text(
                    '${l10n.translate('amount_paid')}: ${formatter.format(paid)}'
                    '${order?.paymentStatus != null ? ' · ${order!.paymentStatus}' : ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
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
    return LayoutBuilder(
      // Below this height the stacked actions squeeze the keypad into slivers.
      builder: (context, constraints) => _buildActivePaymentPanelBody(
        ticketIndex,
        ticket,
        compact: constraints.maxHeight < 700,
      ),
    );
  }

  Widget _buildActivePaymentPanelBody(
    int ticketIndex,
    TicketData ticket, {
    required bool compact,
  }) {
    final calcState = ref.watch(calculatorProvider);
    final allTickets = ref.watch(ticketsProvider);
    final theme = Theme.of(context);
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context)!;

    final orderTotal = allTickets.fold<double>(0, (s, t) => s + t.total);
    // Parts paid by amount are money in too, though no ticket line shows it.
    final paidTotal =
        allTickets
            .where((t) => t.isPaid)
            .fold<double>(0, (s, t) => s + t.total) +
        _groupParts.values
            .expand((p) => p)
            .fold<double>(0, (s, t) => s + t.amount);
    final progressFraction = orderTotal > 0
        ? (paidTotal / orderTotal).clamp(0.0, 1.0)
        : 0.0;
    final deliveryFee = _deliveryFeeFor(allTickets);
    final credit = _creditOf(ticket);
    final due = ticketDueAfterCredit(ticket.total, credit);
    final plan = _planOf(ticket);
    // With a split by amount running, the pad collects the part, not the bill.
    final payable = (plan != null ? plan.amountFor(due) : due) + deliveryFee;
    // Nothing keyed means "exact" — a card, or cash with no change to give
    // — and prints no given/change lines. A cent of float error must not
    // lock the button on an exact tender.
    final canPay =
        ticket.items.isNotEmpty &&
        (calcState.enteredAmount <= 0 ||
            calcState.enteredAmount + 0.001 >= payable) &&
        !_isProcessing;
    final stripShown = _splitVisible(allTickets, ref.watch(settingsProvider));

    return Column(
      children: [
        // Ticket summary — only when the strip is away. With the strip up the
        // tickets themselves carry every figure, and the pad gets the room.
        if (!stripShown)
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
                          ? '${l10n.translate('ticket')} ${ticketIndex + 1}  ·  ${currencyFormatter.format(due)}'
                          : '${l10n.translate('total_due')}  ·  ${currencyFormatter.format(due)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (ticket.totalTva > 0)
                      Text(
                        '${l10n.translate('tva')}: ${currencyFormatter.format(ticket.totalTva)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
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
                          Icon(
                            Icons.delivery_dining,
                            size: 14,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${l10n.translate('delivery_fee')}:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '+ ${currencyFormatter.format(deliveryFee)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l10n.translate('to_collect')}:',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        currencyFormatter.format(payable),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
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
                      backgroundColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l10n.translate('paid')}: ${currencyFormatter.format(paidTotal)}'
                        '  (${allTickets.where((t) => t.isPaid).length}/${allTickets.length})',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                        ),
                      ),
                      Text(
                        '${l10n.translate('remaining')}: ${currencyFormatter.format(orderTotal - paidTotal)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

        _buildBalanceDue(theme, l10n, currencyFormatter),

        // Undivided and no strip: the only place to start a split. Once one
        // runs the strip comes up and the ticket carries it from there.
        if (!stripShown && plan == null && due > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: _buildSplitStartButton(ticketIndex, ticket),
          ),

        // Tender for the ticket in hand — chosen here, next to the pad that
        // takes it, rather than on the ticket.
        Padding(
          padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, 0),
          child: SizedBox(
            height: compact ? 46 : 52,
            child: _buildPaymentMethodButtons(ticketIndex, ticket),
          ),
        ),

        // One pad for the ticket in hand: what came in, what goes back,
        // note shortcuts, keypad. There is no second prompt before this
        // screen — this *is* the cash-given step, and because it reads the
        // selected ticket it works the same undivided or split ten ways.
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, compact ? 6 : 8, 12, 0),
            child: CashPad(
              amountDue: payable,
              entered: calcState.enteredAmount,
              onKey: _onCalculatorButton,
              onAmount: _setExactAmount,
            ),
          ),
        ),

        SizedBox(height: compact ? 4 : 6),

        // Action buttons
        Container(
          padding: EdgeInsets.all(compact ? 8 : 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: _buildPaymentActions(
            theme,
            l10n,
            ticketIndex,
            ticket,
            canPay: canPay,
            compact: compact,
          ),
        ),
      ],
    );
  }

  /// Pay, save-and-leave and clear.
  ///
  /// Stacked three high these ate ~170px, which on a short till screen came
  /// straight out of the keypad. Now Pay keeps its own full-width row and the
  /// two secondary actions share one; on a short panel all three share a row.
  Widget _buildPaymentActions(
    ThemeData theme,
    AppLocalizations l10n,
    int ticketIndex,
    TicketData ticket, {
    required bool canPay,
    required bool compact,
  }) {
    final pay = ElevatedButton.icon(
      onPressed: canPay
          ? () => _planOf(ticket) != null
                ? _processMoneyPart(ticketIndex, ticket)
                : _processPayment(ticketIndex, ticket)
          : null,
      icon: _isProcessing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.check_circle_rounded, size: 22),
      label: Text(
        l10n.translate('complete_payment'),
        style: const TextStyle(fontSize: 16),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green.shade600,
        foregroundColor: Colors.white,
        disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    // Leave with the division saved and nothing paid — the explicit
    // counterpart to Complete Payment. The header X does the same thing, but
    // an X reads as "cancel": a cashier dividing a bill to collect later
    // needs to see that finishing without taking money is a real action.
    final save = FilledButton.tonalIcon(
      onPressed: _isProcessing
          ? null
          : () => _closeKeepingDivision(freeTheTill: true),
      icon: const Icon(Icons.save_outlined, size: 20),
      label: Text(
        l10n.translate('save_division_continue'),
        style: const TextStyle(fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );

    final clearStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    if (compact) {
      return SizedBox(
        height: 52,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Tooltip(
              message: l10n.translate('clear'),
              child: OutlinedButton(
                onPressed: _clearCalculator,
                style: clearStyle,
                child: const Icon(Icons.clear_rounded, size: 20),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(flex: 2, child: save),
            const SizedBox(width: 6),
            Expanded(flex: 3, child: pay),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 52, child: pay),
        const SizedBox(height: 6),
        SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: save),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _clearCalculator,
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: Text(
                    l10n.translate('clear'),
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: clearStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The pad after [ticketIndex] has just been settled. On the strip it goes
  /// away and the paid ticket slides to the end, leaving the next one a tap
  /// away; without the strip it stays on the paid ticket for its reprint.
  void _afterTicketPaid(int ticketIndex, List<TicketData> tickets) {
    if (_splitVisible(tickets, ref.read(settingsProvider))) {
      ref.read(selectedTicketProvider.notifier).state = null;
      _resetCalculatorFor(null, tickets);
    } else {
      _resetCalculatorFor(ticketIndex, tickets);
    }
  }

  void _setExactAmount(double amount) {
    ref.read(calculatorProvider.notifier).state = CalculatorState(
      display: amount.toStringAsFixed(2),
      enteredAmount: amount,
    );
  }

  /// Every ticket opens on an empty pad: the cashier keys what was handed
  /// over, or taps Exact. Pre-filling the total made the first key append
  /// to it instead of starting a fresh amount.
  void _resetCalculatorFor(int? ticketIndex, List<TicketData> tickets) {
    ref.read(calculatorProvider.notifier).state = CalculatorState();
  }

  // Event handlers

  /// Select [index] — opening the pad for it — or, on the strip, tap the
  /// selected ticket again (or pass null) to put the pad away.
  void _selectTicket(int? index) {
    final previous = ref.read(selectedTicketProvider);
    if (index != null &&
        index == previous &&
        _splitVisible(ref.read(ticketsProvider), ref.read(settingsProvider))) {
      if (_isProcessing) return;
      index = null;
    }
    if (index == null && _isProcessing) return;
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
      SnackBarHelper.showToast(blockReason, kind: ToastKind.warning);
      return;
    }

    final tickets = ref.read(ticketsProvider);
    final defaultMethod = TransactionType.fromString(
      ref.read(settingsProvider).defaultPaymentMethod,
    );
    final newTickets = [
      ...tickets,
      TicketData(
        items: [],
        paymentMethod: defaultMethod,
        discountPercentage: widget.order.discountPercentage,
      ),
    ];
    _setTickets(newTickets);
    // An empty ticket has nothing to pay, so it does not open the pad — it
    // just comes into view, ready for lines to be dragged onto it.
    _scrollTicketIntoView(newTickets.length - 1);
  }

  void _removeTicket(int index) {
    final tickets = ref.read(ticketsProvider);
    final l10n = AppLocalizations.of(context)!;

    if (tickets.length <= 1) {
      SnackBarHelper.showToast(
        l10n.translate('cannot_remove_last_ticket'),
        kind: ToastKind.error,
      );
      return;
    }

    if (tickets[index].isPaid) {
      SnackBarHelper.showToast(
        l10n.translate('cannot_remove_paid_ticket'),
        kind: ToastKind.error,
      );
      return;
    }
    if (_rejectIfMoneyLocked([tickets[index]])) return;

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

    // Indices after the removed ticket shift down by one; the removed one
    // itself takes the pad with it.
    final selected = ref.read(selectedTicketProvider);
    int? newSelected = selected;
    if (selected == index) {
      newSelected = null;
    } else if (selected != null && selected > index) {
      newSelected = selected - 1;
    }

    _setTickets(updatedTickets);
    ref.read(selectedTicketProvider.notifier).state = newSelected;
    if (selected == index) _resetCalculatorFor(null, updatedTickets);
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
    List<TicketData> tickets,
    int sourceIndex,
    int targetIndex,
  ) {
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
    if (sourceTicketIndex < tickets.length &&
        targetTicketIndex < tickets.length &&
        _rejectIfMoneyLocked([
          tickets[sourceTicketIndex],
          tickets[targetTicketIndex],
        ])) {
      return;
    }
    final updatedTickets = List<TicketData>.from(
      tickets.map(
        (ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items)),
      ),
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
      updatedTickets[targetTicketIndex].items[mergeIndex] = existing.mergedWith(
        moved,
      );
    } else {
      updatedTickets[targetTicketIndex].items.add(moved);
    }

    _commitAndPrune(updatedTickets, sourceTicketIndex, targetTicketIndex);
  }

  void _onCalculatorButton(String button) {
    final calcState = ref.read(calculatorProvider);
    String newDisplay = calcState.display;

    if (button == '⌫') {
      newDisplay = newDisplay.length > 1
          ? newDisplay.substring(0, newDisplay.length - 1)
          : '0';
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
    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ticketsCreate)) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarHelper.showToast(
        l10n.translate('no_permission'),
        kind: ToastKind.error,
      );
      return;
    }
    setState(() => _isProcessing = true);
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
    // Parts already paid by amount towards this ticket come off it; paying
    // the rest settles its lines and finishes those splits.
    final credit = _creditOf(ticket);
    final partsPaid = _partsOf(ticket).length;
    final due = ticketDueAfterCredit(ticket.total, credit);
    final double? changeDue = amountGiven == null
        ? null
        : (amountGiven - due - deliveryFee);

    // Require an active cash session so the ticket is linked to a Z-report.
    if (session == null) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarHelper.showToast(
          l10n.translate('no_active_session'),
          kind: ToastKind.warning,
        );
      }
      setState(() => _isProcessing = false);
      return;
    }

    // Guard: payment screen must always be opened for a saved order.
    final orderId = widget.order.orderId;
    if (orderId == null) {
      _logger.error(
        '_processPayment: orderId is null — order was not saved before payment',
      );
      setState(() => _isProcessing = false);
      return;
    }

    try {
      final ticketNumStr = await _mintTicketNum(orderId);
      final allTickets = ref.read(ticketsProvider);

      // Insert ticket + settle its rows atomically — a crash between the two
      // steps would leave an orphaned ticket with products still PENDING, or
      // a division half applied.
      final ticketId = (await ref
              .read(ticketSettlementServiceProvider)
              .createPaidTicket(
                num: ticketNumStr,
                orderId: orderId,
                paymentMethod: ticket.paymentMethod.value,
                amount: due,
                sessionId: session.id,
                // z_day = the active Z's opening day (all sessions in a Z share one
                // z_day). Stays constant even if the ticket is cut after midnight.
                zDay: ref.read(currentZDayProvider),
                lines: ClaimedQuantities(_claimsOf(ticket)),
                splitFromSettled: (settled) => _lineTicketSplit(
                  ticket,
                  allTickets,
                  settled,
                  ticketIndex: ticketIndex,
                  credit: credit,
                )?.encode(),
                completeKitchen:
                    ref.read(settingsProvider).paymentCompletesKitchen,
              ))
          .ticketId;

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
            .map(
              (line) =>
                  line.copyWith(item: line.item.copyWith(ticketId: ticketId)),
            )
            .toList();
        final currentTickets = ref.read(ticketsProvider);
        final updatedTickets = List<TicketData>.from(currentTickets);
        if (ticketIndex < updatedTickets.length) {
          updatedTickets[ticketIndex] = ticket.copyWith(
            isPaid: true,
            ticketId: ticketId,
            ticketNum: ticketNumStr,
            items: updatedItems,
            moneyGroups: const [],
          );
        }
        if (ticket.moneyGroups.isNotEmpty) {
          setState(() => _dropGroups(ticket.moneyGroups));
        }
        _setTickets(updatedTickets);
        _afterTicketPaid(ticketIndex, updatedTickets);

        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          SnackBarHelper.showToast(
            l10n
                .translate('ticket_paid_successfully')
                .replaceAll('{0}', ticketNumStr),
            kind: ToastKind.success,
          );
        }
      }

      // Print ticket — read the payload off local state now, print detached.
      // PrintingService queues the job behind anything a waiter is already
      // printing, so paying never waits on the printer. In _payAllTickets this
      // also means each ticket's paperwork queues in order while the next
      // ticket is already being settled.
      final prefs = ref.read(sharedPreferencesProvider);
      final businessName = prefs.getString('business_name');
      final storeAddress = prefs.getString('business_address');
      final storePhone = prefs.getString('business_phone');

      final itemsForPrint = ticket.items.map((line) {
        final item = line.item;
        return {
          'name': item.displayName,
          'quantity': item.quantity,
          'price': item.totalPrice,
          'components': item.components
              .map(
                (c) => {
                  'name': c.name,
                  'quantity': c.quantity,
                  'removalCharge': c.removalCharge,
                },
              )
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
            amount: due,
            splitPart: credit > 0
                ? SplitPartReceipt(
                    part: partsPaid + 1,
                    parts: null,
                    orderTotal: roundMoney(ticket.total),
                    remaining: 0,
                  )
                : null,
            deliveryFee: deliveryFee > 0 ? deliveryFee : null,
            // After split parts this ticket takes only the rest; the parts'
            // receipts already carried their share of the VAT.
            tvaAmount: credit > 0 ? _tvaShare(ticket, due) : ticket.totalTva,
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
            reference: widget.order.reference,
            tableName: widget.order.tableName,
            numberOfPersons: widget.order.numberOfPersons,
          );

          await ref.read(ticketRepositoryProvider).incrementPrintCount(ticketId);
        } catch (e) {
          _logger.error('Print failed: $e');
        }
      }());

      // Audit log: payment taken
      await ref
          .read(activityLogServiceProvider)
          .logPayment(
            due.toStringAsFixed(2),
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
        SnackBarHelper.showToast(
          l10n
              .translate('payment_failed')
              .replaceAll('{0}', errorText(e, l10n)),
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Take one split-by-amount part of the bill held by [ticket].
  ///
  /// The part is an ordinary ticket for the ticket's running plan's amount that claims no
  /// line — its `split` says which part it is. When it brings the bill to
  /// zero it is the closing part: it claims every remaining line, exactly as
  /// paying the ticket would, so everything that reads "paid" off the lines
  /// (table release, completion, the cloud) sees a settled order.
  Future<void> _processMoneyPart(int ticketIndex, TicketData ticket) async {
    final plan = _planOf(ticket);
    if (plan == null || _isProcessing) return;
    final l10n = AppLocalizations.of(context)!;
    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ticketsCreate)) {
      SnackBarHelper.showToast(
        l10n.translate('no_permission'),
        kind: ToastKind.error,
      );
      return;
    }
    final session = ref.read(currentSessionProvider);
    final orderId = widget.order.orderId;
    if (session == null || orderId == null) {
      SnackBarHelper.showToast(
        l10n.translate('no_active_session'),
        kind: ToastKind.warning,
      );
      return;
    }

    setState(() => _isProcessing = true);
    final database = ref.read(databaseProvider);
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);

    final due = ticketDueAfterCredit(ticket.total, _creditOf(ticket));
    final picked = plan.current(due);
    final amount = picked.amount;
    final remainingAfter = roundMoney(due - amount);
    final closing = remainingAfter <= 0.005;
    final deliveryFee = _deliveryFeeFor(ref.read(ticketsProvider));
    final tendered = ref.read(calculatorProvider).enteredAmount;
    final double? amountGiven = tendered > 0 ? tendered : null;
    final double? changeDue = amountGiven == null
        ? null
        : (amountGiven - amount - deliveryFee);

    // EQUAL keeps its announced count and the number of the part picked; a
    // custom-amount split only knows how many payers it has had so far.
    final part = plan.mode == SplitMode.equal && picked.part != null
        ? picked.part!
        : _partsOf(ticket).length + 1;
    final parts = plan.mode == SplitMode.equal ? plan.parts : part;

    try {
      // Which lines this part pays towards, so a reopened (or reloaded)
      // order puts it back under this ticket. The closing part also says
      // which splits it finishes.
      final split = SplitDetails(
        groupId: plan.groupId,
        mode: plan.mode,
        part: part,
        parts: parts,
        orderTotal: plan.mode == SplitMode.equal ? plan.base : due,
        payerLabel: '${l10n.translate('split_part')} $part',
        forLines: await _forLinesOf(ticket),
        closesGroups: closing ? ticket.moneyGroups : const [],
      );
      final ticketNumStr = await _mintTicketNum(orderId);
      final ticketId = (await ref
              .read(ticketSettlementServiceProvider)
              .createPaidTicket(
                num: ticketNumStr,
                orderId: orderId,
                paymentMethod: ticket.paymentMethod.value,
                amount: amount,
                splitDetails: split.encode(),
                sessionId: session.id,
                zDay: ref.read(currentZDayProvider),
                // Only the closing part settles the lines and the kitchen.
                lines: closing
                    ? ClaimedQuantities(_claimsOf(ticket))
                    : const NoLines(),
                completeKitchen: closing &&
                    ref.read(settingsProvider).paymentCompletesKitchen,
              ))
          .ticketId;

      await ref.read(orderRepositoryProvider).claimOrderForCurrentUser(orderId);

      final row = await (database.select(
        database.tickets,
      )..where((t) => t.id.equals(ticketId))).getSingle();

      if (mounted) {
        setState(() {
          if (closing) {
            _dropGroups(ticket.moneyGroups);
          } else {
            _groupParts = {
              ..._groupParts,
              plan.groupId: [...?_groupParts[plan.groupId], row],
            };
            final next = plan.afterPaying(picked.part);
            _plans = {..._plans}..remove(plan.groupId);
            if (next != null) _plans[plan.groupId] = next;
          }
        });
        if (closing) {
          final tickets = List<TicketData>.from(ref.read(ticketsProvider));
          if (ticketIndex < tickets.length) {
            tickets[ticketIndex] = ticket.copyWith(
              isPaid: true,
              ticketId: ticketId,
              ticketNum: ticketNumStr,
              items: [
                for (final line in ticket.items)
                  line.copyWith(item: line.item.copyWith(ticketId: ticketId)),
              ],
              moneyGroups: const [],
            );
          }
          _setTickets(tickets);
          _afterTicketPaid(ticketIndex, tickets);
        } else {
          _resetCalculatorFor(ticketIndex, ref.read(ticketsProvider));
        }
        SnackBarHelper.showToast(
          l10n
              .translate('ticket_paid_successfully')
              .replaceAll('{0}', ticketNumStr),
          kind: ToastKind.success,
        );
      }

      final prefs = ref.read(sharedPreferencesProvider);
      final itemsForPrint = ticket.items.map((line) {
        final item = line.item;
        return {
          'name': item.displayName,
          'quantity': item.quantity,
          'price': item.totalPrice,
          'components': item.components
              .map(
                (c) => {
                  'name': c.name,
                  'quantity': c.quantity,
                  'removalCharge': c.removalCharge,
                },
              )
              .toList(),
        };
      }).toList();
      unawaited(() async {
        try {
          await printingService.printPaymentDocuments(
            ticketId: ticketId,
            ticketNumber: ticketNumStr,
            amount: amount,
            deliveryFee: deliveryFee > 0 ? deliveryFee : null,
            amountGiven: amountGiven,
            changeDue: changeDue,
            paymentMethod: ticket.paymentMethod.value,
            createdAt: DateTime.now(),
            items: itemsForPrint,
            tvaAmount: _tvaShare(ticket, amount),
            splitPart: SplitPartReceipt(
              part: part,
              parts: plan.mode == SplitMode.equal ? plan.parts : null,
              // A custom part's `due` is only what was left before it — on
              // the second payer that is not the bill anymore.
              orderTotal: plan.mode == SplitMode.equal
                  ? plan.base
                  : roundMoney(ticket.total),
              remaining: closing ? 0 : remainingAfter,
            ),
            orderType: widget.order.type,
            hasTable: widget.order.tableId != null,
            orderCode: widget.order.orderCode,
            cashierName: currentUser?.firstName,
            waiterName: widget.order.waiterName,
            storeName: prefs.getString('business_name'),
            storeAddress: prefs.getString('business_address'),
            storePhone: prefs.getString('business_phone'),
            customerName: widget.order.customerName,
            customerPhone: widget.order.customerPhone,
            deliveryAddress: widget.order.deliveryAddress,
            reference: widget.order.reference,
            tableName: widget.order.tableName,
            numberOfPersons: widget.order.numberOfPersons,
          );
          await ref.read(ticketRepositoryProvider).incrementPrintCount(ticketId);
        } catch (e) {
          _logger.error('Print failed: $e');
        }
      }());

      await ref
          .read(activityLogServiceProvider)
          .logPayment(
            amount.toStringAsFixed(2),
            widget.order.orderCode ?? '#$orderId',
            userId: currentUser?.id,
            username: currentUser?.effectiveDisplayName,
          );

      if (closing) {
        await _checkAndCompleteOrder(orderId);
      } else {
        // A part on its own settles nothing, so nothing else pushes it.
        unawaited(_pushTicketsSoon(orderId));
      }
    } catch (e) {
      _logger.error('Split part payment failed: $e');
      if (mounted) {
        SnackBarHelper.showToast(
          l10n
              .translate('payment_failed')
              .replaceAll('{0}', errorText(e, l10n)),
          kind: ToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Push this order's tickets now when online; the periodic sync is the
  /// backstop either way.
  Future<void> _pushTicketsSoon(int orderId) async {
    if (!ref.read(lastKnownOnlineStatusProvider)) return;
    try {
      await ref
          .read(dataSyncServiceProvider)
          .syncTicketsForOrder(orderId, deadline: const Duration(seconds: 10));
    } catch (e) {
      _logger.warning('Split part push deferred: $e');
    }
  }

  /// Ask how to split [ticket]'s bill by amount, and set the pad up for the
  /// first part.
  ///
  /// The split belongs to that one ticket: on an order divided by articles
  /// each ticket can be shared out on its own. The ticket's lines lock while
  /// it runs — the parts are paid towards exactly those lines.
  Future<void> _openMoneySplitDialog(TicketData ticket) async {
    final l10n = AppLocalizations.of(context)!;
    final formatter = ref.read(currencyFormatterProvider);
    final due = ticketDueAfterCredit(ticket.total, _creditOf(ticket));
    if (due <= 0) return;

    final result = await showDialog<MoneySplitPlan>(
      context: context,
      builder: (_) => _MoneySplitDialog(
        due: due,
        maxParts: 8,
        formatter: formatter,
        l10n: l10n,
      ),
    );
    if (result == null || !mounted) return;
    final index = ref.read(ticketsProvider).indexOf(ticket);
    if (index == -1) return;
    final tickets = List<TicketData>.from(ref.read(ticketsProvider));
    tickets[index] = ticket.copyWith(
      moneyGroups: [...ticket.moneyGroups, result.groupId],
    );
    setState(() => _plans = {..._plans, result.groupId: result});
    _setTickets(tickets);
    _resetCalculatorFor(index, tickets);
  }

  /// Stop the split running on the selected ticket. With nothing paid yet
  /// the ticket goes back to normal (and unlocks); otherwise its paid parts
  /// stay as credit and the pad takes the rest.
  void _cancelMoneyPlan(int index) {
    final tickets = List<TicketData>.from(ref.read(ticketsProvider));
    if (index >= tickets.length) return;
    final ticket = tickets[index];
    final plan = _planOf(ticket);
    if (plan == null) return;
    final unpaidGroups = [
      for (final g in ticket.moneyGroups)
        if (g == plan.groupId && (_groupParts[g]?.isEmpty ?? true)) g,
    ];
    setState(() => _plans = {..._plans}..remove(plan.groupId));
    if (unpaidGroups.isNotEmpty) {
      tickets[index] = ticket.copyWith(
        moneyGroups: [
          for (final g in ticket.moneyGroups)
            if (!unpaidGroups.contains(g)) g,
        ],
      );
      _setTickets(tickets);
    }
    _resetCalculatorFor(index, tickets);
  }

  /// A ticket being shared out by amount keeps its lines: say so instead.
  bool _rejectIfMoneyLocked(Iterable<TicketData> tickets) {
    if (tickets.every((t) => t.isPaid || t.moneyGroups.isEmpty)) return false;
    SnackBarHelper.showToast(
      AppLocalizations.of(context)!.translate('split_ticket_locked'),
      kind: ToastKind.warning,
    );
    return true;
  }

  /// What [ticket] claims, summed per row: merging lets one row back several
  /// lines of the same ticket. The division work reaches the database only
  /// when the ticket is paid, so abandoning the screen leaves nothing
  /// half-cut behind.
  Map<int, double> _claimsOf(TicketData ticket) {
    final claims = <int, double>{};
    for (final line in ticket.items) {
      for (final source in line.sources) {
        claims[source.rowId] = (claims[source.rowId] ?? 0) + source.quantity;
      }
    }
    return claims;
  }

  /// The next ticket number on this order.
  ///
  /// Max + 1 over this till's tickets AND, when online, the server's: two
  /// tills taking parts of one bill would otherwise both mint 0002, and the
  /// server keys tickets by (order, number). Offline the server cannot be
  /// asked; the bulk push is then the first place a clash could show.
  /// Local cancelled tickets count too: [TicketSettlementService.nextTicketNum]
  /// does not filter them.
  Future<String> _mintTicketNum(int orderId) async {
    var serverNums = const <String>[];
    final code = widget.order.orderCode;
    if (code != null &&
        code.isNotEmpty &&
        ref.read(lastKnownOnlineStatusProvider)) {
      final view = await ref
          .read(apiServiceProvider)
          .fetchOrderSplit(code, timeout: const Duration(seconds: 2));
      // `usedTicketNumbers` includes cancelled tickets, which `tickets`
      // leaves out: re-using a cancelled number would upsert over that row
      // and un-cancel it. `tickets` is only the fallback for a server that
      // predates the field.
      final used = view?['usedTicketNumbers'];
      final tickets = view?['tickets'];
      if (used is List) {
        serverNums = [for (final n in used) '$n'];
      } else if (tickets is List) {
        serverNums = [
          for (final t in tickets)
            if (t is Map && t['ticketNumber'] != null) '${t['ticketNumber']}',
        ];
      }
    }
    return ref
        .read(ticketSettlementServiceProvider)
        .nextTicketNum(orderId, serverNums: serverNums);
  }

  /// The `split` for a ticket paid by lines, or null when the bill is not
  /// split at all — an undivided sale pushes exactly what it always did.
  ///
  /// After parts paid by amount, this ticket is the closing part of that
  /// split: an AMOUNT part with no lines (its lines go up as paid with the
  /// order). Otherwise, on a divided order, a PRODUCTS part naming the rows
  /// it settled.
  SplitDetails? _lineTicketSplit(
    TicketData ticket,
    List<TicketData> allTickets,
    Map<int, int> settledRow, {
    required int ticketIndex,
    required double credit,
  }) {
    final code = widget.order.orderCode ?? '${widget.order.orderId}';
    if (credit > 0) {
      final parts = _partsOf(ticket);
      final last = SplitDetails.decode(parts.last.splitDetails);
      final part = parts.length + 1;
      return SplitDetails(
        groupId: last?.groupId ?? 'A-$code',
        mode: SplitMode.amount,
        part: part,
        parts: part,
        orderTotal: last?.orderTotal ?? ticket.total,
        closesGroups: ticket.moneyGroups,
      );
    }
    if (allTickets.length < 2) return null;

    final lines = <SplitLine>[];
    for (final line in ticket.items) {
      final item = line.item;
      final unit = item.quantity > 0 ? item.totalPrice / item.quantity : 0.0;
      for (final source in line.sources) {
        lines.add(
          SplitLine(
            localLineId: settledRow[source.rowId],
            productId: item.productId,
            name: item.displayName,
            qty: source.quantity,
            unitPrice: roundMoney(unit),
            amount: roundMoney(unit * source.quantity),
          ),
        );
      }
    }
    return SplitDetails(
      groupId: 'P-$code',
      mode: SplitMode.products,
      part: ticketIndex + 1,
      parts: allTickets.length,
      orderTotal: allTickets.fold<double>(0, (s, t) => s + t.total),
      payerLabel: '${ticketIndex + 1}',
      lines: lines,
    );
  }

  /// Pay all unpaid tickets — reads fresh state before each payment to avoid stale-state bugs
  Future<void> _payAllTickets() async {
    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ticketsCreate)) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarHelper.showToast(
        l10n.translate('no_permission'),
        kind: ToastKind.error,
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
      SnackBarHelper.showToast(
        l10n.translate('all_tickets_paid_successfully'),
        kind: ToastKind.success,
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
        freeOnPayment: settings.autoClearTableAfterPaying,
      );

      if (completed) {
        _logger.info(
          'Order #$orderId marked as $paidStatus (all lines settled)',
        );
        // Before the sync below, so `takenBy` goes up with the completion
        // rather than needing a second push.
        await orderRepo.claimOrderForCurrentUser(orderId);

        // The division has done its job. Leaving the rows behind would have
        // them reconstructed against re-used row ids if this order is ever
        // reopened, and nothing else ever reads them again.
        try {
          final database = ref.read(databaseProvider);
          await (database.delete(
            database.ticketDraftSplits,
          )..where((t) => t.orderId.equals(orderId))).go();
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
  void _mergeItems(
    Map<String, dynamic> data,
    int targetTicketIndex,
    int targetItemIndex,
  ) {
    final sourceTicketIndex = data['ticketIndex'] as int;
    final sourceItemIndex = data['itemIndex'] as int;

    final tickets = ref.read(ticketsProvider);
    final updatedTickets = List<TicketData>.from(
      tickets.map(
        (ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items)),
      ),
    );
    if (targetTicketIndex >= updatedTickets.length ||
        sourceTicketIndex >= updatedTickets.length ||
        targetItemIndex >= updatedTickets[targetTicketIndex].items.length ||
        sourceItemIndex >= updatedTickets[sourceTicketIndex].items.length) {
      return;
    }

    if (sourceTicketIndex != targetTicketIndex &&
        _rejectIfMoneyLocked([
          tickets[sourceTicketIndex],
          tickets[targetTicketIndex],
        ])) {
      return;
    }

    final target = updatedTickets[targetTicketIndex].items[targetItemIndex];
    final source = updatedTickets[sourceTicketIndex].items[sourceItemIndex];
    if (!canCombineLines(target.item, source.item)) return;

    updatedTickets[targetTicketIndex].items[targetItemIndex] = target
        .mergedWith(source);
    // Remove the source last: on a same-ticket merge the target sits at an
    // index this shifts, and it has already been written.
    updatedTickets[sourceTicketIndex].items.removeAt(sourceItemIndex);

    _commitAndPrune(updatedTickets, sourceTicketIndex, targetTicketIndex);

    final mergedQty = target.item.quantity + source.item.quantity;
    SnackBarHelper.showToast(
      '${source.item.displayName} → ${formatQty(mergedQty)}x',
      kind: ToastKind.success,
      duration: const Duration(seconds: 1),
    );
  }

  /// Ask how many units of [line] to take onto another ticket. Only for
  /// whole quantities — a weighed line cannot be divided by counting.
  ///
  /// Purely a question: nothing changes until the dialog is confirmed.
  Future<void> _showCustomDivideDialog(
    TicketLine line,
    int ticketIndex,
    int itemIndex,
  ) async {
    final item = line.item;
    if (item.quantity < 2 ||
        item.quantity != item.quantity.truncateToDouble() ||
        _isProcessing) {
      return;
    }
    final take = await showDialog<int>(
      context: context,
      builder: (_) => _DivideQuantityDialog(
        item: item,
        formatter: ref.read(currencyFormatterProvider),
        l10n: AppLocalizations.of(context)!,
      ),
    );
    if (take == null || !mounted) return;
    _divideLine(line, take.toDouble(), ticketIndex, itemIndex);
  }

  /// Cut [takeQty] units off the line into a ticket of their own.
  ///
  /// Synchronous and state-only. Nothing reaches `order_products` here — the
  /// two halves simply divide the line's claim on the rows behind it, and the
  /// database is told about the arrangement when a ticket is paid.
  void _divideLine(
    TicketLine line,
    double takeQty,
    int ticketIndex,
    int itemIndex,
  ) {
    if (_isProcessing) return;
    if (takeQty <= 0 || takeQty >= line.item.quantity) return;

    final tickets = ref.read(ticketsProvider);
    if (ticketIndex < tickets.length &&
        _rejectIfMoneyLocked([tickets[ticketIndex]])) {
      return;
    }
    // An empty unpaid ticket is somewhere to put the second portion without
    // adding to the count, so the ceiling only bites when one has to be made.
    final emptyIdx = tickets.indexWhere((t) => !t.isPaid && t.items.isEmpty);
    if (emptyIdx == -1 && tickets.length >= _maxTickets) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarHelper.showToast(
        l10n.translate('max_tickets_reached').replaceAll('{0}', '$_maxTickets'),
        kind: ToastKind.warning,
      );
      return;
    }

    final updatedTickets = List<TicketData>.from(
      tickets.map(
        (ticket) => ticket.copyWith(items: List<TicketLine>.from(ticket.items)),
      ),
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
      updatedTickets.add(
        TicketData(
          items: [taken],
          paymentMethod: TransactionType.fromString(
            ref.read(settingsProvider).defaultPaymentMethod,
          ),
          discountPercentage: widget.order.discountPercentage,
        ),
      );
    }

    _setTickets(updatedTickets);
    _scrollTicketIntoView(
      emptyIdx != -1 ? emptyIdx : updatedTickets.length - 1,
    );

    SnackBarHelper.showToast(
      '${line.item.displayName}: '
      '${formatQty(kept.item.quantity)} + ${formatQty(taken.item.quantity)}',
      kind: ToastKind.info,
      duration: const Duration(seconds: 2),
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
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined, size: 18),
                const SizedBox(width: 8),
                Text(l10n.translate('print_this_ticket')),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'options',
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, size: 18),
                const SizedBox(width: 8),
                Text(l10n.translate('print_options')),
              ],
            ),
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
                Icon(
                  Icons.print_rounded,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
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
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
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
    SnackBarHelper.showToast(
      l10n.translate('no_permission'),
      kind: ToastKind.error,
    );
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
        SnackBarHelper.showToast(
          l10n.translate('print_failed'),
          kind: ToastKind.error,
        );
      }
    } catch (e) {
      _logger.error('Draft ticket print failed: $e');
      if (mounted) {
        SnackBarHelper.showToast(errorText(e, l10n), kind: ToastKind.error);
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
        SnackBarHelper.showToast(
          l10n
              .translate('draft_tickets_printed_count')
              .replaceAll('{0}', '$printed')
              .replaceAll('{1}', '${pending.length}'),
          kind: ToastKind.error,
        );
      }
    } catch (e) {
      _logger.error('Print all draft tickets failed: $e');
      if (mounted) {
        SnackBarHelper.showToast(errorText(e, l10n), kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _isPrintingDraft = false);
    }
  }

  Future<void> _printTicket(TicketData ticket) async {
    if (ticket.ticketId == null) return;
    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ticketsPrint)) {
      final l10n = AppLocalizations.of(context)!;
      SnackBarHelper.showToast(
        l10n.translate('no_permission'),
        kind: ToastKind.error,
      );
      return;
    }
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    try {
      final businessName = prefs.getString('business_name');
      final itemsForPrint = ticket.items
          .map(
            (line) => {
              'name': line.item.displayName,
              'quantity': line.item.quantity,
              'price': line.item.totalPrice,
              'components': line.item.components
                  .map(
                    (c) => {
                      'name': c.name,
                      'quantity': c.quantity,
                      'price': c.price,
                      'removalCharge': c.removalCharge,
                    },
                  )
                  .toList(),
            },
          )
          .toList();

      // A ticket closed by split-by-amount holds only its last share — the
      // earlier parts are rows of their own. Reprint what this row took.
      final database = ref.read(databaseProvider);
      final row = await (database.select(
        database.tickets,
      )..where((t) => t.id.equals(ticket.ticketId!))).getSingleOrNull();
      final total = roundMoney(ticket.total);
      final paid = row != null && row.amount < total - 0.005
          ? roundMoney(row.amount)
          : total;
      final split = paid < total ? SplitDetails.decode(row?.splitDetails) : null;

      await printingService.printTicketReceipt(
        ticketId: ticket.ticketId!,
        ticketNumber: ticket.ticketNum ?? ticket.ticketId.toString(),
        amount: paid,
        splitPart: paid < total
            ? SplitPartReceipt(
                part: split?.part ?? 1,
                parts: split != null && split.mode == SplitMode.equal
                    ? split.parts
                    : null,
                orderTotal: total,
                remaining: 0,
              )
            : null,
        // Reprint must not repeat the fee on a divided order: it was collected
        // once, on the ticket that settled first (the lowest ticket id).
        deliveryFee: _reprintDeliveryFee(ticket),
        tvaAmount: paid < total ? _tvaShare(ticket, paid) : ticket.totalTva,
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
        reference: widget.order.reference,
        tableName: widget.order.tableName,
        numberOfPersons: widget.order.numberOfPersons,
        orderType: widget.order.type,
        isReprint: true,
      );

      await ref.read(ticketRepositoryProvider).incrementPrintCount(ticket.ticketId!);
    } catch (e) {
      _logger.error('Reprint failed: $e');
      if (mounted) {
        SnackBarHelper.showToast('Print failed: $e', kind: ToastKind.error);
      }
    }
  }
}

/// How to split a bill by amount: N equal parts, or one part of a typed
/// amount. Pops the plan for the first part, or null.
class _MoneySplitDialog extends StatefulWidget {
  final double due;
  final int maxParts;
  final CurrencyFormatter formatter;
  final AppLocalizations l10n;

  const _MoneySplitDialog({
    required this.due,
    required this.maxParts,
    required this.formatter,
    required this.l10n,
  });

  @override
  State<_MoneySplitDialog> createState() => _MoneySplitDialogState();
}

class _MoneySplitDialogState extends State<_MoneySplitDialog> {
  SplitMode _mode = SplitMode.equal;
  int _parts = 2;
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _custom =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  bool get _valid => _mode == SplitMode.equal
      ? _parts >= 2
      : _custom > 0 && _custom < widget.due;

  void _confirm() {
    if (!_valid) return;
    Navigator.of(context).pop(
      MoneySplitPlan(
        groupId: const Uuid().v4(),
        mode: _mode,
        parts: _mode == SplitMode.equal ? _parts : 1,
        base: widget.due,
        customAmount: _mode == SplitMode.amount ? _custom : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final f = widget.formatter;
    final scheme = Theme.of(context).colorScheme;

    Widget shareTile(String label, double amount, {bool emphasis = false}) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: emphasis
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: emphasis
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  f.format(amount),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: emphasis
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );

    final List<Widget> body;
    if (_mode == SplitMode.equal) {
      body = [
        Text(
          l10n.translate('split_how_many_people'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var n = 2; n <= widget.maxParts; n++)
              SizedBox(
                width: 64,
                height: 56,
                child: n == _parts
                    ? FilledButton(
                        onPressed: () {},
                        style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text(
                          '$n',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: () => setState(() => _parts = n),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          '$n',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            // The first share; the last one absorbs the rounding cent.
            shareTile(
              '$_parts × ${l10n.translate('split_part')}',
              equalPartAmount(widget.due, _parts, 1),
              emphasis: true,
            ),
          ],
        ),
      ];
    } else {
      final custom = _custom.clamp(0, widget.due).toDouble();
      final tooHigh = _custom >= widget.due;
      body = [
        AdaptiveKeyboardTextField(
          controller: _amountController,
          autofocus: true,
          selectAllOnFocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
          ],
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            labelText: l10n.translate('split_this_part'),
            suffixText: f.symbol,
            border: const OutlineInputBorder(),
            errorText: tooHigh ? l10n.translate('split_amount_too_high') : null,
            errorMaxLines: 2,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _confirm(),
        ),
        const SizedBox(height: 8),
        // Common shares, so "half each" doesn't need mental arithmetic.
        Row(
          children: [
            for (final d in const [2, 3, 4])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: () => setState(
                      () => _amountController.text = roundMoney(
                        widget.due / d,
                      ).toStringAsFixed(2),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: FittedBox(
                      child: Text(
                        '1/$d · ${f.format(roundMoney(widget.due / d))}',
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            shareTile(
              l10n.translate('split_this_part'),
              roundMoney(custom),
              emphasis: true,
            ),
            const SizedBox(width: 8),
            shareTile(
              l10n.translate('split_after_this_part'),
              roundMoney(widget.due - custom),
            ),
          ],
        ),
      ];
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      title: Row(
        children: [
          Icon(Icons.groups_rounded, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('split_by_amount'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
          Text(
            f.format(widget.due),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<SplitMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: SplitMode.equal,
                    icon: const Icon(Icons.drag_handle_rounded),
                    label: Text(l10n.translate('split_equal_parts')),
                  ),
                  ButtonSegment(
                    value: SplitMode.amount,
                    icon: const Icon(Icons.edit_rounded),
                    label: Text(l10n.translate('split_custom_amount')),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
              const SizedBox(height: 14),
              ...body,
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton.icon(
          onPressed: _valid ? _confirm : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(l10n.translate('confirm')),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
        ),
      ],
    );
  }
}

/// How many units of a line to take off onto another ticket: one number,
/// keyed on the pad, nudged with − / +, or typed on a hardware keyboard.
///
/// Pops the quantity to take, or null when backed out of.
class _DivideQuantityDialog extends StatefulWidget {
  final OrderItem item;
  final CurrencyFormatter formatter;
  final AppLocalizations l10n;

  const _DivideQuantityDialog({
    required this.item,
    required this.formatter,
    required this.l10n,
  });

  @override
  State<_DivideQuantityDialog> createState() => _DivideQuantityDialogState();
}

class _DivideQuantityDialogState extends State<_DivideQuantityDialog> {
  late final int _max = widget.item.quantity.toInt() - 1;
  int _take = 1;

  /// The first key replaces the pre-filled 1 rather than appending to it —
  /// otherwise keying "3" would produce 13.
  bool _replaceOnKey = true;

  bool get _valid => _take >= 1 && _take <= _max;

  void _set(int value, {bool keyed = false}) {
    setState(() {
      _take = value;
      _replaceOnKey = !keyed;
    });
  }

  void _key(String key) {
    if (key == '⌫') {
      final text = _replaceOnKey ? '' : '$_take';
      final next = text.length > 1 ? text.substring(0, text.length - 1) : '';
      _set(int.tryParse(next) ?? 0, keyed: true);
      return;
    }
    if (key == 'C') {
      _set(0, keyed: true);
      return;
    }
    final text = (_replaceOnKey || _take == 0) ? key : '$_take$key';
    final value = int.tryParse(text) ?? 0;
    // A number past the line's quantity is a typo, not a request: keep the
    // last digit only, so the cashier can just key the right one.
    _set(value > _max ? (int.tryParse(key) ?? 0) : value, keyed: true);
  }

  void _confirm() {
    if (_valid) Navigator.of(context).pop(_take);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final char = event.character;
    if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
      _key(char);
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _key('⌫');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_take < _max) _set(_take + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (_take > 1) _set(_take - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = widget.l10n;
    final item = widget.item;
    final unit = item.quantity > 0 ? item.totalPrice / item.quantity : 0.0;
    final stays = item.quantity.toInt() - _take;

    Widget part(String label, int qty, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${qty < 0 ? 0 : qty}x',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              widget.formatter.format(unit * (qty < 0 ? 0 : qty)),
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );

    Widget stepButton(IconData icon, VoidCallback? onPressed) => SizedBox(
      width: 64,
      height: 64,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Icon(icon, size: 30),
      ),
    );

    const keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', '⌫'],
    ];

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        title: Row(
          children: [
            Icon(Icons.call_split_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${formatQty(item.quantity)}x ${item.displayName}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.translate('divide_how_many'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  stepButton(
                    Icons.remove_rounded,
                    _take > 1 ? () => _set(_take - 1) : null,
                  ),
                  Expanded(
                    child: Container(
                      height: 64,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _valid
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        _take == 0 ? '' : '$_take',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: _valid
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                  stepButton(
                    Icons.add_rounded,
                    _take < _max ? () => _set(_take + 1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  part(
                    l10n.translate('divide_stays'),
                    stays,
                    theme.colorScheme.secondary,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  part(
                    l10n.translate('divide_moves'),
                    _take,
                    theme.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final row in keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      for (final key in row)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: () => _key(key),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  elevation: 1,
                                  backgroundColor: key == '⌫' || key == 'C'
                                      ? theme.colorScheme.errorContainer
                                      : theme.colorScheme.secondaryContainer,
                                  foregroundColor: key == '⌫' || key == 'C'
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onSecondaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  key,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton.icon(
            onPressed: _valid ? _confirm : null,
            icon: const Icon(Icons.call_split_rounded, size: 18),
            label: Text(
              _valid
                  ? '${l10n.translate('divide_move_action')}: $_take'
                  : l10n.translate('divide_move_action'),
            ),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ],
      ),
    );
  }
}
