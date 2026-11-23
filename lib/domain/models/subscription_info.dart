/// The shop's subscription as the till last heard it from the server, and when
/// to say something about it.
///
/// Kept as arithmetic on dates so it can be checked without a clock, a server,
/// or a screen — same shape as `session_expiry.dart`.
library;

/// How far ahead of the end date the login screen starts warning.
const kSubscriptionNoticeWindow = Duration(days: 14);

/// What the login screen should say about the subscription.
enum SubscriptionLevel {
  /// Nothing: plenty of time left, or the server never told us an end date.
  none,

  /// Inside the last two weeks.
  ending,

  /// Past the end date, or the server says it has lapsed. Locks sign-in on
  /// the login screen until a check shows it renewed; an open shift carries on.
  expired,
}

class SubscriptionInfo {
  /// When the paid period runs out. null = the server sent no end date
  /// (unlimited / not managed), which never warns.
  final DateTime? endsAt;

  /// Server status, upper-cased: ACTIVE, TRIAL, PAST_DUE, EXPIRED, CANCELED…
  final String? status;

  final String? planName;

  /// Who to call to renew, shown under the warning when present.
  final String? contact;

  const SubscriptionInfo({this.endsAt, this.status, this.planName, this.contact});

  /// Lenient on purpose: an unreadable date is "no end date" (silence), never
  /// an exception that would fail the login or sync carrying it.
  factory SubscriptionInfo.fromJson(Map<dynamic, dynamic> json) {
    return SubscriptionInfo(
      endsAt: parseSubscriptionEnd(
          json['endsAt'] ?? json['endDate'] ?? json['expiresAt']),
      status: _str(json['status'])?.toUpperCase(),
      planName: _str(json['planName'] ?? json['plan']),
      contact: _str(json['contact'] ?? json['renewContact']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (endsAt != null) 'endsAt': endsAt!.toUtc().toIso8601String(),
        if (status != null) 'status': status,
        if (planName != null) 'planName': planName,
        if (contact != null) 'contact': contact,
      };

  static String? _str(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}

/// ISO instant → that instant. Bare date (`2026-10-20`) → the END of that local
/// day: "valid until the 20th" must not start warning "expired" on the morning
/// of the 20th.
DateTime? parseSubscriptionEnd(dynamic raw) {
  if (raw == null) return null;
  final s = raw.toString().trim();
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
    return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
  }
  return parsed.toLocal();
}

SubscriptionLevel subscriptionLevel(SubscriptionInfo? info, DateTime now) {
  if (info == null) return SubscriptionLevel.none;
  if (info.status == 'EXPIRED') return SubscriptionLevel.expired;
  final end = info.endsAt;
  if (end == null) return SubscriptionLevel.none;
  if (!end.isAfter(now)) return SubscriptionLevel.expired;
  if (end.difference(now) <= kSubscriptionNoticeWindow) {
    return SubscriptionLevel.ending;
  }
  return SubscriptionLevel.none;
}

/// Calendar days from today to the end date: 0 = ends today, 1 = tomorrow.
///
/// Calendar days rather than 24h blocks because the banner speaks in dates
/// ("ends tomorrow"), and something ending at 23:59 tonight read at 10:00 is
/// "today", not "in 1 day". Compared as UTC dates so a DST change in between
/// cannot shave a day off.
int subscriptionDaysLeft(DateTime endsAt, DateTime now) {
  final end = DateTime.utc(endsAt.year, endsAt.month, endsAt.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = end.difference(today).inDays;
  return days < 0 ? 0 : days;
}

/// Whether the daily `GET /pos/subscription` should run now.
///
/// Only while there is something to warn about: outside the window the
/// subscription still refreshes for free on every login, token refresh and
/// catalogue sync, so a dedicated call would be pure noise. Inside it, at most
/// once per calendar day — a renewal paid this morning clears the banner by the
/// next time the till is opened.
bool subscriptionCheckDue(
    SubscriptionInfo? info, DateTime? lastCheckedAt, DateTime now) {
  if (subscriptionLevel(info, now) == SubscriptionLevel.none) return false;
  if (lastCheckedAt == null) return true;
  final last = DateTime(lastCheckedAt.year, lastCheckedAt.month, lastCheckedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  return today.isAfter(last);
}
