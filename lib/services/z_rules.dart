/// Pure Z (day close) rules for the v3 contract — no database, no Riverpod,
/// so every decision the till makes about a Z can be unit-tested directly.
///
/// Contract: `bms/docs/POS_Z_CONTRACT.md` (v3). A Z is a label
/// (terminal, zDay, zSeq) carried on cash sessions; the POS owns the counter.
library;

/// `yyyy-MM-dd` of the business day containing [localNow], where the day
/// starts at [startHour]. With start 5, 02:00 belongs to the previous day.
String zDayKeyOf(DateTime localNow, int startHour) {
  final shifted = localNow.subtract(Duration(hours: startHour));
  return formatZDay(DateTime(shifted.year, shifted.month, shifted.day));
}

String formatZDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Midnight of a `yyyy-MM-dd` key — the shape stored in `z_day` columns.
DateTime? parseZDay(String? key) {
  if (key == null || key.length < 10) return null;
  final d = DateTime.tryParse(key.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Minutes since midnight of a strict `HH:mm`, or null for null / malformed.
int? parseHhmm(String? hhmm) {
  if (hhmm == null) return null;
  final m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(hhmm.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// The instant a business-day-relative `HH:mm` rule refers to, for [zDay].
///
/// Mirrors the server exactly: dayStart = zDay at startHour, and
/// rule = dayStart + ((ruleMinutes − startHour×60) mod 1440). With start 05:00,
/// "23:00" is that same night and "02:00" is the next calendar morning.
DateTime? ruleInstant(String zDay, int startHour, String? hhmm) {
  final minutes = parseHhmm(hhmm);
  final day = parseZDay(zDay);
  if (minutes == null || day == null) return null;
  final dayStart = DateTime(day.year, day.month, day.day, startHour);
  final offset = ((minutes - startHour * 60) % 1440 + 1440) % 1440;
  return dayStart.add(Duration(minutes: offset));
}

/// A Z's identity. Ordered by day, then sequence.
class ZLabel implements Comparable<ZLabel> {
  final String zDay;
  final int zSeq;

  const ZLabel(this.zDay, this.zSeq);

  @override
  int compareTo(ZLabel other) {
    final byDay = zDay.compareTo(other.zDay);
    return byDay != 0 ? byDay : zSeq.compareTo(other.zSeq);
  }

  @override
  bool operator ==(Object other) =>
      other is ZLabel && other.zDay == zDay && other.zSeq == zSeq;

  @override
  int get hashCode => Object.hash(zDay, zSeq);

  @override
  String toString() => '$zDay#$zSeq';
}

/// A Z as either side last saw it.
class ZSnapshot {
  final ZLabel label;
  final bool closed;

  const ZSnapshot(this.label, {required this.closed});

  /// `GET /api/pos/z/current` → the terminal's latest Z, or null when the
  /// terminal never had a session (zDay / zSeq null).
  static ZSnapshot? fromServer(Map<String, dynamic>? json) {
    if (json == null) return null;
    final day = json['zDay']?.toString();
    final seq = json['zSeq'];
    if (day == null || day.isEmpty || seq == null) return null;
    final n = seq is num ? seq.toInt() : int.tryParse('$seq');
    if (n == null || n < 1) return null;
    return ZSnapshot(ZLabel(day.substring(0, 10), n),
        closed: json['closed'] == true);
  }
}

enum ZPlanAction {
  /// The open Z is today's — keep using it.
  continueOpen,

  /// Adopt a Z the server has open for today that this till has no row for
  /// (reinstall). Continue it under the server's label.
  adoptServer,

  /// Open a new Z with [ZPlan.next].
  openNew,
}

/// What to do before the next session opens.
class ZPlan {
  final ZPlanAction action;

  /// The Z to continue / adopt / open.
  final ZLabel next;

  /// A local open Z from an earlier business day that must be closed FORCED
  /// first. Never relabelled: a Z that outlives its day is closed, not moved.
  final bool closeStaleFirst;

  /// The local open Z matches a label the server already has CLOSED — close
  /// it locally (no push; the server already knows) before opening [next].
  final bool closeLocalAsServerClosed;

  const ZPlan(
    this.action,
    this.next, {
    this.closeStaleFirst = false,
    this.closeLocalAsServerClosed = false,
  });

  @override
  String toString() =>
      'ZPlan($action, $next, stale=$closeStaleFirst, serverClosed=$closeLocalAsServerClosed)';
}

/// Decide which Z the next session belongs to.
///
/// [localOpen] is this till's open Z, [localLatest] its newest Z of any
/// status, [server] what `/pos/z/current` answered (null offline, or when the
/// terminal never had a session). Offline, the till resumes from its own
/// sessions and never guesses a blind `(today, 1)`: that label may already be
/// closed on the server, and new sessions would land in a closed Z.
ZPlan planZ({
  required String currentZDay,
  ZLabel? localOpen,
  ZSnapshot? localLatest,
  ZSnapshot? server,
}) {
  // Highest sequence already used today, by either side.
  int maxSeqToday() {
    var max = 0;
    for (final s in [localLatest, server]) {
      if (s != null && s.label.zDay == currentZDay && s.label.zSeq > max) {
        max = s.label.zSeq;
      }
    }
    if (localOpen != null &&
        localOpen.zDay == currentZDay &&
        localOpen.zSeq > max) {
      max = localOpen.zSeq;
    }
    return max;
  }

  if (localOpen != null) {
    if (localOpen.zDay.compareTo(currentZDay) < 0) {
      return ZPlan(ZPlanAction.openNew, ZLabel(currentZDay, maxSeqToday() + 1),
          closeStaleFirst: true);
    }
    final serverClosedIt =
        server != null && server.closed && server.label == localOpen;
    if (serverClosedIt) {
      return ZPlan(ZPlanAction.openNew, ZLabel(currentZDay, maxSeqToday() + 1),
          closeLocalAsServerClosed: true);
    }
    return ZPlan(ZPlanAction.continueOpen, localOpen);
  }

  // No local open Z. A server Z still open for today that is ahead of what
  // this till knows is a reinstall mid-day: carry on under its label.
  if (server != null &&
      !server.closed &&
      server.label.zDay == currentZDay &&
      (localLatest == null || server.label.compareTo(localLatest.label) > 0)) {
    return ZPlan(ZPlanAction.adoptServer, server.label);
  }

  return ZPlan(ZPlanAction.openNew, ZLabel(currentZDay, maxSeqToday() + 1));
}

/// Why a Z may not be opened or closed right now, or null when it may.
enum ZRuleBlock {
  /// `zOpenMode: MANUAL` — someone holding `pos:z:open` must open it.
  manualOpenRequired,

  /// At or after `zCantOpenAfter` without `pos:z:override`.
  tooLateToOpen,

  /// Before `zEarliestCloseTime` without `pos:z:override`.
  tooEarlyToClose,

  /// Closing needs `pos:z:close`.
  noClosePermission,
}

/// Whether a Z for [zDay] may be opened at [now].
///
/// [explicitOpen] is true when a user is deliberately opening the Z (the
/// "Open Z" button), false when it would open by itself with a session.
ZRuleBlock? checkZOpen({
  required DateTime now,
  required String zDay,
  required int startHour,
  required String? openMode,
  required String? cantOpenAfter,
  required bool explicitOpen,
  required bool hasOpenPermission,
  required bool hasOverride,
}) {
  final manual = (openMode ?? 'AUTO').toUpperCase() == 'MANUAL';
  if (manual && !(explicitOpen && hasOpenPermission)) {
    return ZRuleBlock.manualOpenRequired;
  }
  final limit = ruleInstant(zDay, startHour, cantOpenAfter);
  if (limit != null && !now.isBefore(limit) && !hasOverride) {
    return ZRuleBlock.tooLateToOpen;
  }
  return null;
}

/// Whether the Z for [zDay] may be closed (MANUAL or AUTO — not FORCED, which
/// is the stale-day sweep and obeys no rule) at [now]. Sessions still open do
/// not block: closing the Z ends them.
ZRuleBlock? checkZClose({
  required DateTime now,
  required String zDay,
  required int startHour,
  required String? earliestCloseTime,
  required bool hasClosePermission,
  required bool hasOverride,
}) {
  if (!hasClosePermission) return ZRuleBlock.noClosePermission;
  final earliest = ruleInstant(zDay, startHour, earliestCloseTime);
  if (earliest != null && now.isBefore(earliest) && !hasOverride) {
    return ZRuleBlock.tooEarlyToClose;
  }
  return null;
}

/// `zCloseMode: AUTO_AFTER_HOUR` and a session is closing at or after
/// `zAutoCloseAfter`: the till must ASK "Clôturer la journée (Z) ?". A "No" is
/// not remembered — it is asked again at every later session close.
bool zAutoCloseDue({
  required DateTime now,
  required String zDay,
  required int startHour,
  required String? closeMode,
  required String? autoCloseAfter,
}) {
  if ((closeMode ?? 'MANUAL').toUpperCase() != 'AUTO_AFTER_HOUR') return false;
  final at = ruleInstant(zDay, startHour, autoCloseAfter);
  return at != null && !now.isBefore(at);
}
