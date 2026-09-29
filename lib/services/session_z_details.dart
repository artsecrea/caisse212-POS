import 'cash_report_sections.dart';
import 'session_service.dart' show SessionSummary;

/// The `details` a closed session carries to the server (Z contract v3).
///
/// The server builds a Z by SUMMING its sessions' details generically:
/// numbers add, objects merge by key, arrays of objects merge on their first
/// identity field (`method`, `rate`, `key`, …). So this holds ADDITIVE figures
/// only — totals and counts, never averages or ratios — and no drawer
/// BALANCES: opening float, expected and counted cash would be double-counted
/// whenever cash carries over from one session to the next. Those travel in
/// the session's own money fields (moneyAtStart, moneyEntered,
/// moneyCarriedOver, moneyAtEnd, countedCash).
Map<String, dynamic> buildSessionDetails(
  SessionSummary summary, {
  CashReportSections? sections,
  double? variance,
}) {
  final b = summary.breakdown;
  final byMethod = <Map<String, dynamic>>[
    for (final e in {
      'CASH': b.cash,
      'CARD': b.card,
      'MOBILE': b.mobile,
      'OTHER': b.other,
    }.entries)
      if (e.value != 0) {'method': e.key, 'amount': _r(e.value)},
  ];

  final details = <String, dynamic>{
    'ticketCount': summary.ticketCount,
    'payments': {
      'total': _r(b.totalPaid),
      'count': b.paidCount,
      'byMethod': byMethod,
      'cancelled': {'count': b.cancelledCount, 'amount': _r(b.cancelled)},
    },
    'refunds': {
      'total': _r(summary.refundsTotal),
      'cash': _r(summary.refundsCash),
    },
    'cash': {
      'cashSales': _r(b.cash),
      'payIns': _r(summary.cashPaidIn),
      'payOuts': _r(summary.cashPaidOut),
      'cashRefunds': _r(summary.refundsCash),
      if (variance != null) 'variance': _r(variance),
    },
  };

  final s = sections;
  if (s == null) return details;

  details['sales'] = {
    'ordersCount': s.indicators.ticketCount,
    'gross': _r(s.general.grossSales),
    'discounts': _r(s.general.discounts),
    'netHt': _r(s.vatTotalHt),
    'tva': _r(s.vatTotalVat),
    'ttc': _r(s.indicators.netSales),
    'covers': s.indicators.covers,
  };
  (details['cash'] as Map<String, dynamic>)['deliveryFees'] =
      _r(s.cash.cashDeliveryFees);
  // Rates in percent (20 = 20%); line prices are TTC, so this is the tax
  // inside them, not on top.
  details['tvaBreakdown'] = [
    for (final v in s.vatBands)
      {
        'rate': v.rate,
        'baseHt': _r(v.baseHt),
        'tva': _r(v.vat),
        'ttc': _r(v.ttc),
      },
  ];
  details['byOrderType'] = [
    for (final e in s.salesByType.entries) {'key': e.key, 'ttc': _r(e.value)},
  ];
  details['cancelledOrders'] = {
    'count': s.indicators.cancelledTicketCount,
    'amount': _r(s.general.cancelledTickets),
  };
  details['voids'] = {
    'count': s.removedItems.lineCount,
    'quantity': s.removedItems.quantity,
    'amount': _r(s.removedItems.amount),
  };
  // No local ids on these rows: `key` (the name) is the merge identity.
  details['categories'] = [
    for (final c in s.families)
      {'key': c.name, 'quantity': c.quantity, 'ttc': _r(c.amount)},
  ];
  details['products'] = [
    for (final p in s.topArticles)
      {'key': p.name, 'quantity': p.quantity, 'ttc': _r(p.amount)},
  ];
  return details;
}

double _r(double v) => (v * 100).roundToDouble() / 100;
