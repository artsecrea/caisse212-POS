import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/services/day_service.dart';
import '../providers/database_providers.dart';
import 'z_actions.dart';

/// [DayService] on this till's own database: the standalone till, which
/// owns its Z counter. The Z orchestration itself is in `z_actions.dart`.
class LocalDayService implements DayService {
  LocalDayService(this._ref);

  final Ref _ref;

  @override
  Future<void> refreshConfig() => refreshZConfig(_ref.read);

  @override
  Future<Z> ensureForSession({required User user, bool superAdmin = false}) =>
      ensureZForSession(_ref.read, user: user, superAdmin: superAdmin);

  @override
  Future<Z> openManually({
    required int userId,
    required bool hasOpenPermission,
    required bool hasOverride,
  }) =>
      openZManually(
        _ref.read,
        userId: userId,
        hasOpenPermission: hasOpenPermission,
        hasOverride: hasOverride,
      );

  @override
  Future<ZRuleViolation?> closeBlock(
    Z z, {
    required bool hasClosePermission,
    required bool hasOverride,
  }) =>
      zCloseBlock(
        _ref.read,
        z,
        hasClosePermission: hasClosePermission,
        hasOverride: hasOverride,
      );

  @override
  Future<bool> autoCloseDue(Z z) async => zAutoCloseDueFor(_ref.read, z);

  @override
  Future<bool> closesWithSession(Z z, int sessionId) =>
      zClosesWithSessionFor(_ref.read, z, sessionId);

  @override
  Future<void> close(Z z, {required String closeMode, int? endedBy}) =>
      closeZNow(_ref.read, z, closeMode: closeMode, endedBy: endedBy);

  @override
  Future<ZReport?> report(int zId, {required bool isX}) =>
      zReportFor(_ref.read, zId, isX: isX);
}

/// The Z actions for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final dayServiceProvider = Provider<DayService>((ref) => LocalDayService(ref));

/// Print the X or Z report of [zId]. [reprint] stamps DUPLICATA — any Z
/// printed again after its close. False when nothing printed.
Future<bool> printZReport(
  WidgetRef ref,
  int zId, {
  required bool isX,
  bool reprint = false,
}) async {
  final z = await ref.read(dayServiceProvider).report(zId, isX: isX);
  if (z == null) return false;
  return ref.read(printingServiceProvider).printDailySummaryReport(
        report: z.report,
        reportType: isX ? 'X' : 'Z',
        zLabel: z.zLabel,
        isReprint: reprint && !isX,
      );
}
