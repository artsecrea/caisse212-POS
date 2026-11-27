import '../../data/database/app_database.dart' show CashSession, Z;
import '../models/z_day_option.dart';

/// What the screens read about the Zs. An interface because, linked to a
/// hub, a till shows the hub's Zs: standalone, it reads its own database
/// (`ZService`).
abstract interface class ZQueries {
  /// The open Z as it changes: for screens that show it before the current
  /// Z is known (the login screen).
  Stream<Z?> watchOpenZ();

  Future<Z?> getOpenZ();

  Future<Z?> getById(int zId);

  /// Most recent Zs (open + closed), newest first — for the history list.
  Future<List<Z>> recentZs({int limit = 25});

  /// All sessions that belong to [zId], oldest first.
  Future<List<CashSession>> sessionsForZ(int zId);

  /// Sessions of [zId] still active or paused, other than [except].
  Future<List<CashSession>> openSessionsOf(int zId, {int? except});

  /// Every CLOSED business day that has at least one cash session, newest
  /// first.
  ///
  /// A Z is only printable once the day is over on paper: a day still holding
  /// an open or paused session, or a Z that has not been closed, is left out —
  /// its figures are not final, and a Z printed from them would be a legal
  /// document that later disagrees with the real one. Its X is always there.
  ///
  /// Days are business days: a session belongs to its Z's zDay, and a legacy
  /// session with no Z to the day it opened.
  ///
  /// Capped because this feeds a dropdown, not an archive browser; a shop
  /// wanting an older day has the sessions screen. The cap is generous enough
  /// to cover a quarter of trading.
  Future<List<ZDayOption>> zDayOptions({int limitDays = 120});

  /// True while the till is still trading: a Z is open, or a cash session is
  /// active or paused. The Z report is the closing document, so it is not
  /// printable until then — mid-shift figures are the X report's job.
  Future<bool> reportBlockedByOpenShift();
}
