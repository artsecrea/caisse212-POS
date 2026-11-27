import '../../data/database/app_database.dart' show User, Z;
import '../../services/daily_summary_service.dart' show DailySummaryReport;
import '../../services/z_rules.dart' show ZRuleBlock;

/// A Z rule refused an open or a close.
class ZRuleViolation implements Exception {
  final ZRuleBlock block;

  /// The `HH:mm` limit that applied, for the message.
  final String? limit;

  const ZRuleViolation(this.block, {this.limit});

  @override
  String toString() => 'ZRuleViolation($block, $limit)';
}

/// An X or Z report, with the Z's display name when the Z is known.
typedef ZReport = ({DailySummaryReport report, String? zLabel});

/// The trading day — the Z — as a till sees it. An interface because the Z
/// is shared by every till of the business: standalone, this till owns the
/// counter (`LocalDayService`); linked to a hub, the hub does.
abstract interface class DayService {
  /// Refresh the business-day definition and this terminal's Z rules.
  /// Best-effort and bounded: offline, the cached copies stand.
  Future<void> refreshConfig();

  /// The Z the next session of [user] belongs to: the open one, one to
  /// adopt after a reinstall, or a new one — which must pass the open
  /// rules. Throws [ZRuleViolation] when a new Z may not open by itself.
  /// [superAdmin] (a master-password sign-in) holds every Z permission.
  Future<Z> ensureForSession({required User user, bool superAdmin = false});

  /// A person deliberately opens the Z. Returns the open Z — the existing
  /// one when a Z is already open. Throws [ZRuleViolation].
  Future<Z> openManually({
    required int userId,
    required bool hasOpenPermission,
    required bool hasOverride,
  });

  /// Why [z] may not be closed now by someone with these permissions; null
  /// when it may. Sessions still open do not block: the close ends them.
  Future<ZRuleViolation?> closeBlock(
    Z z, {
    required bool hasClosePermission,
    required bool hasOverride,
  });

  /// Whether a session closing now should ask to close [z]
  /// (AUTO_AFTER_HOUR).
  Future<bool> autoCloseDue(Z z);

  /// BY_SESSION: whether closing [sessionId] closes [z] with it.
  Future<bool> closesWithSession(Z z, int sessionId);

  /// Close [z] with [closeMode] — the rules are the caller's to check, with
  /// [closeBlock] — ending its open sessions. Nothing prints.
  Future<void> close(Z z, {required String closeMode, int? endedBy});

  /// The X (a snapshot of the Z so far, [isX]) or the Z report of [zId],
  /// summed over its sessions; null when it has none.
  Future<ZReport?> report(int zId, {required bool isX});
}
