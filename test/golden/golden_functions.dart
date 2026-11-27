// Runs one golden case through the real Dart code. Every function here only
// translates JSON to the till's own types and back: no rule is re-written, so
// a fixture always says what the till does. Formats: test/golden/README.md.

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/domain/models/line_payment.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/models/order_money.dart';
import 'package:caisse212/domain/models/refund_policy.dart';
import 'package:caisse212/domain/models/split_bill.dart';
import 'package:caisse212/domain/models/table_occupancy.dart';
import 'package:caisse212/services/cash_report_sections.dart'
    show LineMoney, vatRateOf;
import 'package:caisse212/services/waiter_order_money.dart';
import 'package:caisse212/services/z_rules.dart';

typedef GoldenFn = Map<String, dynamic> Function(Map<String, dynamic> input);

/// `fn` name in a fixture → the code it runs.
final Map<String, GoldenFn> goldenFunctions = {
  // line_money.json
  'LineAmounts': _lineAmounts,
  'lineCountsInTotal': (i) => {
        'owed': lineIsOwed(i['state'] as String),
        'countsInTotal':
            lineCountsInTotal(i['state'] as String, paid: i['paid'] as bool),
      },
  'applyOrderDiscount': (i) => {
        'discount': orderDiscountAmount(_d(i['linesNet']), _d(i['percentage'])),
        'total': applyOrderDiscount(_d(i['linesNet']), _d(i['percentage'])),
      },
  'LineMoney': _lineMoney,
  'vatRateOf': (i) => {'rate': vatRateOf(_line(i, 0, 1))},

  // order_money.json
  'orderMoney': _orderMoney,

  // options.json
  'priceOptions': _priceOptions,
  'seedGroup': (i) {
    final seeded = seedGroup(_rule(i['rule'] as Map<String, dynamic>), [
      for (final s in i['seeds'] as List)
        ComponentSeed(
          componentId: s['componentId'] as int,
          isRequired: s['isRequired'] as bool? ?? false,
          minQuantity: s['minQuantity'] as int? ?? 0,
          defaultQuantity: s['defaultQuantity'] as int? ?? 0,
        ),
    ]);
    return {
      'seeded': {for (final e in seeded.entries) '${e.key}': e.value},
    };
  },
  'removals': _removals,
  'maxUnitsOf': (i) => {
        'max': maxUnitsOf(
          i['rule'] == null ? null : _rule(i['rule'] as Map<String, dynamic>),
          i['linkMaxQuantity'] as int?,
        ),
      },

  // z_rules.json
  'zDayKeyOf': (i) =>
      {'zDay': zDayKeyOf(_t(i['now'])!, i['startHour'] as int)},
  'ruleInstant': (i) => {
        'at': _fmt(ruleInstant(
            i['zDay'] as String, i['startHour'] as int, i['hhmm'] as String?)),
      },
  'ZSnapshot.fromServer': (i) {
    final s = ZSnapshot.fromServer(i['json'] as Map<String, dynamic>?);
    return {'snapshot': s == null ? null : _snapshotJson(s)};
  },
  'planZ': _planZ,
  'checkZOpen': (i) => {
        'block': checkZOpen(
          now: _t(i['now'])!,
          zDay: i['zDay'] as String,
          startHour: i['startHour'] as int,
          openMode: i['openMode'] as String?,
          cantOpenAfter: i['cantOpenAfter'] as String?,
          explicitOpen: i['explicitOpen'] as bool,
          hasOpenPermission: i['hasOpenPermission'] as bool,
          hasOverride: i['hasOverride'] as bool,
        )?.name,
      },
  'checkZClose': (i) => {
        'block': checkZClose(
          now: _t(i['now'])!,
          zDay: i['zDay'] as String,
          startHour: i['startHour'] as int,
          earliestCloseTime: i['earliestCloseTime'] as String?,
          hasClosePermission: i['hasClosePermission'] as bool,
          hasOverride: i['hasOverride'] as bool,
        )?.name,
      },
  'zAutoCloseDue': (i) => {
        'due': zAutoCloseDue(
          now: _t(i['now'])!,
          zDay: i['zDay'] as String,
          startHour: i['startHour'] as int,
          closeMode: i['closeMode'] as String?,
          autoCloseAfter: i['autoCloseAfter'] as String?,
        ),
      },
  'zClosesWithSession': (i) => {
        'closes': zClosesWithSession(
          closeMode: i['closeMode'] as String?,
          otherOpenSessions: i['otherOpenSessions'] as int,
          tooEarly: i['tooEarly'] as bool? ?? false,
        ),
        'printSessionX': printSessionXWithZ(i['sessionsInZ'] as int? ?? 1),
      },
  'zOpenWarnings': (i) {
    final w = zOpenWarnings(
      now: _t(i['now'])!,
      startedAt: _t(i['startedAt'])!,
      zDay: '',
      startHour: 0,
      maxOpenHours: i['maxOpenHours'] as int?,
      cutoff: i['cutoff'] as String?,
    );
    return {
      'warnings': [for (final x in w) x.name]..sort(),
      'cutoffAt': _fmt(nextCutoffAfter(_t(i['startedAt'])!, i['cutoff'] as String?)),
    };
  },

  // refund_policy.json
  'RefundPolicy.fromJson': (i) =>
      RefundPolicy.fromJson(i['json'] as Map<String, dynamic>).toJson(),
  'refundPolicyIssues': _refundIssues,
  'refundMethodsForPayments': (i) => {
        'methods': refundMethodsForPayments(
            [for (final m in i['methods'] as List) m as String?]).toList()
          ..sort(),
      },

  // tables.json
  'settlementState': (i) => {
        'paid': isLinePaid(i['state'] as String, i['ticketId'] as int?),
        'state': settlementState(i['state'] as String, i['ticketId'] as int?),
      },
  'isOrderSettled': (i) => {'settled': isOrderSettled(_states(i))},
  'tableReleaseReason': (i) => {
        'reason': tableReleaseReason(
          orderExists: i['orderExists'] as bool,
          orderStatus: i['orderStatus'] as String,
          lineStates: _states(i),
          freeOnPayment: i['freeOnPayment'] as bool,
        )?.name,
      },
  'orderBlocksTable': (i) => {
        'blocks': orderBlocksTable(
          orderStatus: i['orderStatus'] as String,
          lineStates: _states(i),
        ),
      },

  // splits.json
  'roundMoney': (i) => {'rounded': roundMoney(_d(i['value']))},
  'equalPartAmount': (i) {
    final total = _d(i['total']);
    final parts = i['parts'] as int;
    final amounts = [
      for (var p = 1; p <= (parts < 1 ? 1 : parts); p++)
        equalPartAmount(total, parts, p),
    ];
    return {
      'amounts': amounts,
      'sum': roundMoney(amounts.fold(0.0, (s, a) => s + a)),
    };
  },
  'nextTicketNumber': (i) => {
        'number': nextTicketNumber(
          [for (final n in i['local'] as List) n as String],
          [for (final n in i['server'] as List? ?? const []) n as String],
        ),
      },
};

double _d(Object? v) => (v as num?)?.toDouble() ?? 0.0;

List<String> _states(Map<String, dynamic> i) =>
    [for (final s in i['lineStates'] as List) s as String];

/// Shop wall-clock time, `yyyy-MM-ddTHH:mm:ss`, no offset.
DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String);

String? _fmt(DateTime? t) {
  if (t == null) return null;
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(t.year, 4)}-${p(t.month)}-${p(t.day)}T'
      '${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}

Map<String, dynamic> _lineAmounts(Map<String, dynamic> i) {
  final a = LineAmounts(
    unitPrice: _d(i['unitPrice']),
    quantity: _d(i['quantity']),
    componentsPerUnit: _d(i['componentsPerUnit']),
    manualDiscount: _d(i['manualDiscount']),
    unitDiscount: _d(i['unitDiscount']),
    unitTva: _d(i['unitTva']),
  );
  return {
    'net': a.net,
    'gross': a.gross,
    'lineDiscount': a.lineDiscount,
    'tva': a.tva,
    'unitSubtotalHt': a.unitSubtotalHt,
  };
}

Map<String, dynamic> _lineMoney(Map<String, dynamic> i) {
  final m = LineMoney.of(
    _line(i['line'] as Map<String, dynamic>, 0, 1),
    componentsPerUnit: _d(i['componentsPerUnit']),
    orderDiscountPercentage: _d(i['orderDiscountPercentage']),
  );
  return {'gross': m.gross, 'discount': m.discount, 'net': m.net};
}

final _epoch = DateTime(2026, 1, 1);

/// An `order_products` row from a fixture line. Only the money fields and
/// the paid marker matter; the rest are fixed placeholders.
OrderProduct _line(Map<String, dynamic> l, int id, int orderId) => OrderProduct(
      id: id,
      orderId: orderId,
      productId: 1,
      ticketId: l['ticketId'] as int?,
      quantity: _d(l['quantity'] ?? 1),
      unitaryPrice: _d(l['unitPrice']),
      unitaryDiscount: _d(l['unitDiscount']),
      unitaryTva: _d(l['unitTva']),
      manualDiscount: _d(l['manualDiscount']),
      state: l['state'] as String? ?? 'PENDING',
      kdsPrintedQuantity: 0,
      orderTicketPrintedQuantity: 0,
      updatedAt: _epoch,
      canceledQuantity: 0,
    );

/// One order, priced twice: by the waiter API's [WaiterOrderMoney] and by the
/// till's cart ([CurrentOrder]). The two must agree; the golden test checks
/// that as well as the expected values.
Map<String, dynamic> _orderMoney(Map<String, dynamic> i) {
  final lines = [for (final l in i['lines'] as List) l as Map<String, dynamic>];
  final pct = _d(i['discountPercentage']);

  final order = Order(
    id: 1,
    code: 'GOLDEN',
    status: 'COMPLETED',
    type: 'TAKEAWAY',
    priority: 0,
    persons: 1,
    date: _epoch,
    discountPercentage: pct,
    discountReason: i['discountReason'] as String?,
    createdAt: _epoch,
    updatedAt: _epoch,
    isSynced: false,
    tagsSynced: true,
  );
  final rows = [for (var n = 0; n < lines.length; n++) _line(lines[n], n + 1, 1)];
  final comps = <int, List<OrderProductComponent>>{
    for (var n = 0; n < lines.length; n++)
      n + 1: [
        for (final c in lines[n]['components'] as List? ?? const [])
          OrderProductComponent(
            id: 0,
            componentId: c['componentId'] as int? ?? 1,
            orderProductId: n + 1,
            quantity: c['quantity'] as int,
            price: _d(c['price']),
            isSpecial: false,
            removalCharge: c['removalCharge'] as bool? ?? false,
            createdAt: _epoch,
            updatedAt: _epoch,
          ),
      ],
  };
  final waiter =
      WaiterOrderMoney.of(order, rows, comps, credit: _d(i['credit']));

  final cart = CurrentOrder(
    discountPercentage: pct,
    items: [
      for (var n = 0; n < lines.length; n++)
        OrderItem(
          productId: 1,
          productName: 'P',
          finalPrice: rows[n].unitaryPrice,
          quantity: rows[n].quantity,
          discount: rows[n].unitaryDiscount,
          manualDiscount: rows[n].manualDiscount,
          tva: rows[n].unitaryTva,
          state: rows[n].state,
          ticketId: rows[n].ticketId,
          components: [
            for (final c in comps[n + 1]!)
              OrderItemComponent(
                componentId: c.componentId,
                name: 'C',
                quantity: c.quantity,
                price: c.price,
                removalCharge: c.removalCharge,
              ),
          ],
        ),
    ],
  );

  return {
    'waiterApi': waiter.toJson(),
    'till': {
      'subtotalHt': cart.subtotal,
      'tax': cart.tax,
      'totalBeforeDiscount': cart.totalBeforeDiscount,
      'discountAmount': cart.discountAmount,
      'totalDiscount': cart.totalDiscount,
      'total': cart.total,
      'unpaidLines': [
        for (var n = 0; n < cart.items.length; n++)
          if (cart.unpaidItems.contains(cart.items[n])) n,
      ],
    },
  };
}

ComponentGroupRule _rule(Map<String, dynamic> r) => ComponentGroupRule(
      groupId: r['groupId'] as int?,
      name: r['name'] as String? ?? 'G${r['groupId']}',
      selectionType: parseSelectionType(r['selectionType'] as String?),
      minSelection: r['minSelection'] as int? ?? 0,
      maxSelection: r['maxSelection'] as int?,
      freeQuantity: r['freeQuantity'] as int? ?? 0,
      visibleWhenComponentIds: [
        for (final v in r['visibleWhenComponentIds'] as List? ?? const [])
          v as int,
      ],
    );

/// Fixture maps are keyed by component id as a string (JSON keys). In
/// `groupOf`, a null group is the ungrouped bucket.
Map<int, T> _byId<T>(Object? m, T Function(Object? v) f) => {
      for (final e in (m as Map<String, dynamic>? ?? const {}).entries)
        int.parse(e.key): f(e.value),
    };

Map<String, dynamic> _priceOptions(Map<String, dynamic> i) {
  final rules = <int?, ComponentGroupRule>{
    for (final r in i['rules'] as List? ?? const [])
      (r as Map<String, dynamic>)['groupId'] as int?: _rule(r),
  };
  final result = priceOptions(
    picked: _byId(i['picked'], (v) => v as int),
    catalogue: _byId(i['catalogue'], _d),
    groupOf: _byId(i['groupOf'], (v) => v as int?),
    rules: rules,
    maxEach: _byId(i['maxEach'], (v) => v as int?),
  );
  final lines = [
    for (final l in result.lines)
      {'componentId': l.componentId, 'quantity': l.quantity, 'unitPrice': l.unitPrice},
  ]..sort((a, b) {
      final byId = (a['componentId'] as int).compareTo(b['componentId'] as int);
      return byId != 0
          ? byId
          : (a['unitPrice'] as double).compareTo(b['unitPrice'] as double);
    });
  return {
    'ok': result.isOk,
    'problem': result.problem?.name,
    'componentId': result.componentId,
    'groupId': result.group?.groupId,
    'lines': lines,
    'optionTotalPerParentUnit': optionTotalPerParentUnit(result.lines),
  };
}

Map<String, dynamic> _removals(Map<String, dynamic> i) {
  final candidates = [
    for (final c in i['candidates'] as List)
      RemovalCandidate(
        componentId: c['componentId'] as int,
        defaultQuantity: c['defaultQuantity'] as int,
        selectedQuantity: c['selectedQuantity'] as int,
        unitPrice: _d(c['unitPrice']),
        chargeOnRemoval: c['chargeOnRemoval'] as bool? ?? false,
      ),
  ];
  return {
    'rows': [
      for (final c in candidates)
        for (final r in removalRowsFor(c))
          {
            'componentId': r.componentId,
            'quantity': r.quantity,
            'price': r.price,
            'removalCharge': r.removalCharge,
          },
    ],
    'needsExplicitRow': [
      for (final c in candidates)
        if (c.needsExplicitRow) c.componentId,
    ],
    'chargePerParentUnit': removalChargePerParentUnit(candidates),
  };
}

ZLabel? _label(Object? v) {
  if (v == null) return null;
  final m = v as Map<String, dynamic>;
  return ZLabel(m['zDay'] as String, m['zSeq'] as int);
}

ZSnapshot? _snapshot(Object? v) {
  if (v == null) return null;
  return ZSnapshot(_label(v)!, closed: (v as Map)['closed'] as bool);
}

Map<String, dynamic> _snapshotJson(ZSnapshot s) =>
    {'zDay': s.label.zDay, 'zSeq': s.label.zSeq, 'closed': s.closed};

Map<String, dynamic> _planZ(Map<String, dynamic> i) {
  final plan = planZ(
    currentZDay: i['currentZDay'] as String,
    localOpen: _label(i['localOpen']),
    localLatest: _snapshot(i['localLatest']),
    server: _snapshot(i['server']),
  );
  return {
    'action': plan.action.name,
    'next': {'zDay': plan.next.zDay, 'zSeq': plan.next.zSeq},
    'closeLocalAsServerClosed': plan.closeLocalAsServerClosed,
  };
}

Map<String, dynamic> _refundIssues(Map<String, dynamic> i) {
  final policy = RefundPolicy.fromJson(i['policy'] as Map<String, dynamic>);
  final a = i['attempt'] as Map<String, dynamic>;
  final issues = refundPolicyIssues(
    policy,
    RefundAttempt(
      saleZDay: parseZDay(a['saleZDay'] as String?),
      currentZDay: parseZDay(a['currentZDay'] as String?),
      saleZClosed: a['saleZClosed'] as bool? ?? false,
      total: _d(a['total']),
      method: a['method'] as String,
      paidMethods: {for (final m in a['paidMethods'] as List? ?? const []) m as String},
      includesNonRefundable: a['includesNonRefundable'] as bool? ?? false,
      isFullRefund: a['isFullRefund'] as bool? ?? true,
    ),
  );
  final held = {for (final p in i['held'] as List? ?? const []) p as String};
  return {
    'issues': [
      for (final x in issues) {'flag': x.flag.wire, 'permission': x.permission},
    ],
    'permissionsNeeded': permissionsNeeded(issues).toList()..sort(),
    'unapproved': [
      for (final x in unapprovedIssues(issues, held.contains)) x.flag.wire,
    ],
  };
}
