/// One trading day that has something to report on, with what it holds.
///
/// Built from cash sessions rather than from the `zs` table on purpose: a shop
/// that never switched Z tracking on has no Z rows at all, and its days are
/// exactly as reportable. When a Z does exist for the day its code and number
/// ride along for the ticket header.
class ZDayOption {
  final DateTime day;
  final List<int> sessionIds;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;

  const ZDayOption({
    required this.day,
    required this.sessionIds,
    required this.sessionCodes,
    this.zCode,
    this.zNumber,
  });

  String get label {
    final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    if (zNumber != null) return '$d  ·  Z$zNumber';
    if (zCode != null) return '$d  ·  $zCode';
    return d;
  }
}
