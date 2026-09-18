/// One physical unit that two terminals both sold.
///
/// Two tills go offline, both sell the same boxed unit, both come back. The
/// server gives the unit to whoever reached it first and drops the serial
/// links from the losing order — the order itself still saves. This is what
/// comes back to the loser.
///
/// It is not an error, and it is not something syncing can put right: a
/// customer is already walking out with a box and a receipt naming a serial
/// that now belongs to someone else's order. All the POS can do is stop
/// claiming the unit, keep a record of what was handed over, and make sure a
/// person is told.
class SerialConflictReport {
  /// The losing order — ours.
  final String orderCode;
  final int productId;

  /// The serial id our line sent, which maps straight onto the local
  /// `order_products.serial_id`.
  final int serialId;

  /// The number printed on the box and on the customer's receipt.
  final String? serialNumber;

  /// The order that kept the unit. Null when the unit was unavailable for a
  /// reason that is not another sale — a reception that was never validated,
  /// for instance.
  final String? winningOrderCode;

  /// The server's own words, shared by every entry of one conflicted order.
  final String? reason;

  const SerialConflictReport({
    required this.orderCode,
    required this.productId,
    required this.serialId,
    this.serialNumber,
    this.winningOrderCode,
    this.reason,
  });

  factory SerialConflictReport.fromJson(Map<String, dynamic> json) => SerialConflictReport(
        orderCode: (json['orderCode'] ?? '').toString(),
        productId: (json['productId'] as num?)?.toInt() ?? 0,
        serialId: (json['serialId'] as num?)?.toInt() ?? 0,
        serialNumber: json['serialNumber'] as String?,
        winningOrderCode: json['winningOrderCode'] as String?,
        reason: json['reason'] as String?,
      );

  /// Parse the `serialConflicts` array off a sync response.
  ///
  /// Tolerant on purpose: this runs immediately after a sync the server has
  /// already accepted, and a surprise in this array must never turn a
  /// successful sync into a failed one — that would strand the batch and
  /// re-send it forever, which is the exact failure this feature removed.
  static List<SerialConflictReport> listFrom(dynamic body) {
    if (body is! Map) return const [];
    final raw = body['serialConflicts'];
    if (raw is! List) return const [];
    final out = <SerialConflictReport>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        final conflict =
            SerialConflictReport.fromJson(Map<String, dynamic>.from(entry));
        // A conflict we cannot tie back to a line is not actionable.
        if (conflict.orderCode.isEmpty || conflict.serialId == 0) continue;
        out.add(conflict);
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// What gets left on the order line, so the paperwork handed over is still
  /// recoverable after the link is gone.
  String get historyNote {
    final unit = serialNumber ?? '#$serialId';
    return winningOrderCode == null
        ? 'Serial $unit could not be claimed'
        : 'Serial $unit went with order $winningOrderCode';
  }

  @override
  String toString() =>
      'SerialConflictReport($orderCode, serial $serialId, won by $winningOrderCode)';
}
