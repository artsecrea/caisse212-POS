import 'dart:convert';

/// Split bill — how one order's bill is divided between payers.
///
/// Every payer gets an ordinary ticket; the `split` object on that ticket
/// (stored verbatim in `tickets.split_details`, contract in the backend's
/// docs/pos-split-bill.md, V201) only DESCRIBES the division. The ticket's
/// `amount` stays the money of record, so a build that ignores `split` still
/// totals the order, the Z and the session correctly.
///
/// Wire rules the push and pull must keep:
///  * omitted / null  → the server keeps whatever it has,
///  * `{}`            → the server clears it,
///  * an object       → replaces it.
enum SplitMode {
  /// Each payer takes order lines (or a slice of one).
  products('PRODUCTS'),

  /// The cashier typed what this payer pays.
  amount('AMOUNT'),

  /// The bill divided into N equal parts.
  equal('EQUAL');

  const SplitMode(this.wire);
  final String wire;

  static SplitMode? fromWire(Object? raw) {
    for (final m in values) {
      if (m.wire == raw) return m;
    }
    return null;
  }

  /// Money-only parts: they pay towards the bill without claiming any line.
  bool get isMoney => this != SplitMode.products;
}

/// One line a PRODUCTS part paid for.
class SplitLine {
  /// Server id of the (slice) order line; null until the server has
  /// assigned one — the push fills it in from [localLineId].
  final int? orderProductId;

  /// Local `order_products.id` of the row this part settled. Ours, not the
  /// server's: it is how the push finds [orderProductId] once known.
  final int? localLineId;
  final int productId;
  final String name;
  final double qty;
  final double unitPrice;
  final double amount;

  const SplitLine({
    this.orderProductId,
    this.localLineId,
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
    if (orderProductId != null) 'orderProductId': orderProductId,
    if (localLineId != null) 'localLineId': localLineId,
    'productId': productId,
    'name': name,
    'qty': qty,
    'unitPrice': unitPrice,
    'amount': amount,
  };
}

/// One line a money part (AMOUNT / EQUAL) pays *towards* without settling it.
///
/// Rides the `split` JSON as `forLines`, which the server stores and serves
/// back verbatim but never reads — unlike `lines`, which it counts as claimed
/// quantity. It is how a till reopening the order puts the part back under
/// the ticket it was paid against when the order is divided by articles too.
/// [lineUid] is the cross-till identity; [localLineId] only means something
/// on the till that wrote it.
class SplitForLine {
  final int? localLineId;
  final String? lineUid;
  final double qty;

  const SplitForLine({this.localLineId, this.lineUid, required this.qty});

  Map<String, dynamic> toJson() => {
    if (localLineId != null) 'localLineId': localLineId,
    if (lineUid != null) 'lineUid': lineUid,
    'qty': qty,
  };

  static SplitForLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final qty = (raw['qty'] as num?)?.toDouble() ?? 0;
    if (qty <= 0) return null;
    return SplitForLine(
      localLineId: (raw['localLineId'] as num?)?.toInt(),
      lineUid: raw['lineUid'] as String?,
      qty: qty,
    );
  }
}

/// The `split` object carried by one ticket.
class SplitDetails {
  final String groupId;
  final SplitMode mode;

  /// 1-based position of this part, and how many parts the split has.
  /// For PRODUCTS and AMOUNT [parts] is how many payers are known so far.
  final int part;
  final int parts;
  final String? payerLabel;

  /// What the parts were cut from: the bill still owed when the split was
  /// started. Every EQUAL part is computed from this one figure.
  final double orderTotal;
  final List<SplitLine> lines;

  /// Money parts: the lines this part pays towards. Empty on parts written
  /// before tickets could be split by amount one at a time, which therefore
  /// count against the whole unpaid order.
  final List<SplitForLine> forLines;

  /// Money groups this ticket finishes. A group listed here (by any live
  /// ticket) is settled, and its parts are no longer credit.
  final List<String> closesGroups;

  const SplitDetails({
    required this.groupId,
    required this.mode,
    required this.part,
    required this.parts,
    required this.orderTotal,
    this.payerLabel,
    this.lines = const [],
    this.forLines = const [],
    this.closesGroups = const [],
  });

  Map<String, dynamic> toJson() => {
    'v': 1,
    'groupId': groupId,
    'mode': mode.wire,
    'part': part,
    'parts': parts,
    if (payerLabel != null) 'payerLabel': payerLabel,
    'orderTotal': roundMoney(orderTotal),
    if (lines.isNotEmpty) 'lines': [for (final l in lines) l.toJson()],
    if (forLines.isNotEmpty) 'forLines': [for (final l in forLines) l.toJson()],
    if (closesGroups.isNotEmpty) 'closesGroups': closesGroups,
  };

  String encode() => jsonEncode(toJson());

  /// Lenient: anything unreadable is "not a split", never an error — a
  /// payment must not fail over its description.
  static SplitDetails? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final mode = SplitMode.fromWire(m['mode']);
      if (mode == null) return null;
      return SplitDetails(
        groupId: (m['groupId'] ?? '').toString(),
        mode: mode,
        part: (m['part'] as num?)?.toInt() ?? 1,
        parts: (m['parts'] as num?)?.toInt() ?? 1,
        payerLabel: m['payerLabel'] as String?,
        orderTotal: (m['orderTotal'] as num?)?.toDouble() ?? 0,
        forLines: [
          if (m['forLines'] is List)
            for (final l in m['forLines'] as List)
              if (SplitForLine.fromJson(l) case final line?) line,
        ],
        closesGroups: [
          if (m['closesGroups'] is List)
            for (final g in m['closesGroups'] as List)
              if (g != null) g.toString(),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

double roundMoney(double v) => (v * 100).roundToDouble() / 100;

/// What EQUAL part [part] of [parts] pays out of [total]. Every part but the
/// last is the rounded share; the last takes the rounding remainder so the
/// parts always add up to the bill exactly (100 / 3 → 33.33 + 33.33 + 33.34).
double equalPartAmount(double total, int parts, int part) {
  if (parts <= 1) return roundMoney(total);
  final share = roundMoney(total / parts);
  if (part < parts) return share;
  return roundMoney(total - share * (parts - 1));
}

/// The stored `split` JSON with every line's `orderProductId` filled in from
/// [serverIdByLocal] where it was missing. Returns the input unchanged when
/// nothing was missing or nothing could be resolved, and null for null.
///
/// Push-time on purpose: a slice row cut at payment has no server id yet,
/// and only gets one after the order push comes back.
String? resolveSplitServerIds(String? raw, Map<int, int> serverIdByLocal) {
  if (raw == null || raw.isEmpty) return raw;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['lines'] is! List) return raw;
    var changed = false;
    final lines = [
      for (final l in m['lines'] as List)
        if (l is Map)
          () {
            final line = Map<String, dynamic>.from(l);
            final local = (line['localLineId'] as num?)?.toInt();
            if (line['orderProductId'] == null &&
                local != null &&
                serverIdByLocal[local] != null) {
              line['orderProductId'] = serverIdByLocal[local];
              changed = true;
            }
            return line;
          }(),
    ];
    if (!changed) return raw;
    return jsonEncode({...Map<String, dynamic>.from(m), 'lines': lines});
  } catch (_) {
    return raw;
  }
}

/// Whether the stored `split` still names a line by local id only.
bool splitHasUnresolvedLines(String? raw) {
  if (raw == null || raw.isEmpty) return false;
  try {
    final m = jsonDecode(raw);
    if (m is! Map || m['lines'] is! List) return false;
    return (m['lines'] as List).any(
      (l) =>
          l is Map && l['orderProductId'] == null && l['localLineId'] != null,
    );
  } catch (_) {
    return false;
  }
}

/// The ticket's next number on this order: one past the highest seen,
/// locally or on the server, zero-padded to the historic four digits.
String nextTicketNumber(
  Iterable<String> localNums, [
  Iterable<String> serverNums = const [],
]) {
  var max = 0;
  for (final n in [...localNums, ...serverNums]) {
    final v = int.tryParse(n.trim()) ?? 0;
    if (v > max) max = v;
  }
  return (max + 1).toString().padLeft(4, '0');
}

/// What a split-bill receipt adds under its total.
class SplitPartReceipt {
  /// 1-based part and part count; [parts] null prints "Partial payment".
  final int part;
  final int? parts;

  /// The bill the parts are cut from, and what is still owed after this one.
  final double orderTotal;
  final double remaining;

  const SplitPartReceipt({
    required this.part,
    required this.parts,
    required this.orderTotal,
    required this.remaining,
  });
}
