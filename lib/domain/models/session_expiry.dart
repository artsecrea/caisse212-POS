/// When to warn that the till's sign-in is about to run out.
///
/// The terminal holds a long-lived credential that eventually expires. When it
/// does, the app locks itself until a manager signs in again — which is fine
/// if somebody saw it coming, and a disaster at the till on a Saturday night
/// if nobody did. This decides how much notice to give.
///
/// Kept as arithmetic on a date so it can be checked without a clock, a
/// server, or a screen.
library;

/// How loudly to say something about the session running out.
enum SessionExpiryLevel {
  /// Nothing to say: plenty of time left, or no expiry known.
  none,

  /// Worth mentioning, dismissible. Someone should plan to sign in.
  notice,

  /// The app blocks on this itself; the notice steps aside rather than
  /// duplicating the message.
  blocked,
}

/// The point at which a notice starts appearing.
const kSessionNoticeWindow = Duration(days: 7);

/// The point at which the app stops asking and starts insisting. Must match
/// the lead `ApiService.isReauthDue` uses, or the notice and the blocking gate
/// disagree about which one is in charge.
const kSessionBlockWindow = Duration(days: 1);

/// Which notice, if any, applies at [now] for a session dying at [expiresAt].
///
/// A null expiry means the terminal never recorded one — an old install, or a
/// credential the server issued without a readable expiry. Silence is right
/// there: a warning nobody can act on, shown forever, teaches people to ignore
/// warnings.
SessionExpiryLevel sessionExpiryLevel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return SessionExpiryLevel.none;
  final left = expiresAt.difference(now);
  if (left <= kSessionBlockWindow) return SessionExpiryLevel.blocked;
  if (left <= kSessionNoticeWindow) return SessionExpiryLevel.notice;
  return SessionExpiryLevel.none;
}

/// Whole days to quote in the warning, rounded UP.
///
/// Six and a half days is "7 days", not "6": the number is a deadline someone
/// plans around, and quoting it short makes the app look wrong on the last
/// day. Never returns less than 1 — a notice saying "0 days" reads as broken,
/// and by then the blocking gate has taken over anyway.
int sessionDaysLeft(DateTime expiresAt, DateTime now) {
  // Minutes, not hours: `inHours` truncates, so six days and a quarter of an
  // hour would round DOWN to six — quoting the deadline short, which is the
  // one direction this must never go.
  final minutes = expiresAt.difference(now).inMinutes;
  if (minutes <= 0) return 1;
  final days = (minutes / (24 * 60)).ceil();
  return days < 1 ? 1 : days;
}
