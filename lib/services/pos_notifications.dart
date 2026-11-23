import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import 'daily_summary_service.dart';
import 'session_service.dart';
import 'z_service.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import 'notification_params.dart';

/// `ref.read` of either a provider [Ref] or a [WidgetRef] — the order
/// repository and the LAN server hold the first, the screens the second.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Admin notifications for money taken off after the fact: discounts
/// (remises) and cancellations. All go through the outbox, so a till offline
/// at the moment still reports them later. Fire-and-forget: none of these can
/// fail the action that triggered it.

void _send(ProviderReader read, String type, Map<String, String> params,
    {String? refId}) {
  unawaited(read(notificationOutboxProvider).send(type, params, refId: refId));
}

String _terminal(ProviderReader read) =>
    read(apiServiceProvider).getPosName() ?? '';

String _currency(ProviderReader read) => read(settingsProvider).currency;

/// A remise just saved on [orderCode]: the order-level percentage when it
/// changed from [previousPercent], and every line whose per-unit manual
/// discount grew past what [previousLineDiscount] recorded (keyed
/// `productId:variantId|-1`). A new order passes empty previous values.
void notifyDiscounts(
  ProviderReader read, {
  required String orderCode,
  required CurrentOrder order,
  double previousPercent = 0,
  Map<String, double> previousLineDiscount = const {},
}) {
  try {
    final actor = read(currentUserProvider);
    final now = DateTime.now();
    final pct = order.discountPercentage;
    if (pct > 0 && (pct - previousPercent).abs() > 0.0001) {
      _send(
        read,
        'POS_DISCOUNT_APPLIED',
        NotificationParams.discountApplied(
          terminalName: _terminal(read),
          scope: 'ORDER',
          orderCode: orderCode,
          amount: order.discountAmount,
          percent: pct,
          totalBefore: order.totalBeforeDiscount,
          totalAfter: order.total,
          reason: order.discountReason,
          cashierName: actor?.effectiveDisplayName,
          cashierId: actor?.id,
          at: now,
          currency: _currency(read),
        ),
        refId: orderCode,
      );
    }
    for (final item in order.items) {
      if (item.ticketId != null || item.manualDiscount <= 0) continue;
      final key = '${item.productId}:${item.variantId ?? -1}';
      final before = previousLineDiscount[key] ?? 0;
      if (item.manualDiscount <= before + 0.0001) continue;
      _send(
        read,
        'POS_DISCOUNT_APPLIED',
        NotificationParams.discountApplied(
          terminalName: _terminal(read),
          scope: 'LINE',
          orderCode: orderCode,
          amount: item.manualDiscount * item.quantity,
          productName: item.displayName,
          quantity: item.quantity,
          totalBefore:
              (item.finalPrice + item.componentTotal) * item.quantity,
          totalAfter: item.totalPrice,
          cashierName: actor?.effectiveDisplayName,
          cashierId: actor?.id,
          at: now,
          currency: _currency(read),
        ),
        refId: orderCode,
      );
    }
  } catch (_) {/* never fail a save over a notification */}
}

/// Lines taken off a saved order — one notification per product removed.
void notifyRemovedItems(
    ProviderReader read, List<RemovedOrderItemsCompanion> rows) {
  try {
    final now = DateTime.now();
    for (final r in rows) {
      final variant = r.variantName.present ? r.variantName.value : null;
      final name = variant == null
          ? r.productName.value
          : '${r.productName.value} ($variant)';
      _send(
        read,
        'POS_CANCELLATION',
        NotificationParams.cancellation(
          terminalName: _terminal(read),
          kind: 'LINE',
          orderCode: r.orderCode.present ? (r.orderCode.value ?? '') : '',
          amount: r.amount.present ? r.amount.value : 0,
          productName: name,
          quantity: r.quantity.value,
          afterKitchen:
              r.wasSentToKitchen.present && r.wasSentToKitchen.value,
          cashierName: r.removedByName.present ? r.removedByName.value : null,
          cashierId: r.removedBy.present ? r.removedBy.value : null,
          at: now,
          currency: _currency(read),
        ),
        refId: r.orderCode.present ? r.orderCode.value : null,
      );
    }
  } catch (_) {}
}

/// A whole order voided — or [deleted] outright, which takes it off the
/// books just the same.
void notifyOrderCancelled(
  ProviderReader read, {
  required String orderCode,
  required double amount,
  String? reason,
  String? byName,
  int? byId,
  bool afterKitchen = false,
  bool deleted = false,
}) {
  try {
    _send(
      read,
      'POS_CANCELLATION',
      NotificationParams.cancellation(
        terminalName: _terminal(read),
        kind: 'ORDER',
        orderCode: orderCode,
        amount: amount,
        afterKitchen: afterKitchen,
        deleted: deleted,
        reason: reason,
        cashierName: byName,
        cashierId: byId,
        at: DateTime.now(),
        currency: _currency(read),
      ),
      refId: orderCode,
    );
  } catch (_) {}
}

Future<String?> _userName(AppDatabase database, int userId) async {
  final u = await (database.select(database.users)
        ..where((u) => u.id.equals(userId)))
      .getSingleOrNull();
  if (u == null) return null;
  final dn = u.displayName;
  return (dn != null && dn.isNotEmpty)
      ? dn
      : '${u.firstName} ${u.lastName}'.trim();
}

/// `POS_SESSION_PAUSED` ([pausedAt] null) or `POS_SESSION_RESUMED` (with the
/// moment it was paused) for [sessionId]. Call only on a real change — the
/// SessionService pause / resume return values say so.
Future<void> notifySessionPauseChange(
  ProviderReader read,
  int sessionId, {
  DateTime? pausedAt,
}) async {
  try {
    final database = read(databaseProvider);
    final session = await SessionService(database).getSessionById(sessionId);
    if (session == null) return;
    final cashier = await _userName(database, session.cashierId) ??
        'Cashier #${session.cashierId}';
    final actor = read(currentUserProvider);
    _send(
      read,
      pausedAt == null ? 'POS_SESSION_PAUSED' : 'POS_SESSION_RESUMED',
      NotificationParams.sessionPauseChange(
        terminalName: _terminal(read),
        sessionCode: session.code,
        cashierName: cashier,
        cashierId: session.cashierId,
        byName: actor != null && actor.id != session.cashierId
            ? actor.effectiveDisplayName
            : null,
        at: DateTime.now(),
        pausedAt: pausedAt,
      ),
      refId: sessionId.toString(),
    );
  } catch (e) {
    Logger.instance.warning('session pause notification failed: $e');
  }
}

/// `POS_SESSION_CLOSED` for [sessionId], after it ended. [report] is the
/// session's report when the caller already built one (the close dialog
/// printed it); otherwise it is built here.
Future<void> notifySessionClosed(
  ProviderReader read,
  int sessionId, {
  DailySummaryReport? report,
}) async {
  try {
    final database = read(databaseProvider);
    final r = report ??
        await DailySummaryService(database).generateSessionReport(sessionId);
    if (r.sessions.isEmpty) return;
    final s = r.sessions.first;
    final session = await SessionService(database).getSessionById(sessionId);
    final z = session?.zId == null
        ? null
        : await ZService(database).getById(session!.zId!);
    _send(
      read,
      'POS_SESSION_CLOSED',
      NotificationParams.sessionClosed(
        terminalName: _terminal(read),
        report: s,
        closedAt: s.endedAt ?? DateTime.now(),
        // The same expected-cash definition the close dialog and the printed
        // Z use, so Expected / Counted / Variance agree on the mobile card.
        expectedCash: s.expectedCash,
        currency: _currency(read),
        sections: r.sections,
        zDay: z == null ? null : ZService.labelOf(z).zDay,
        zSeq: z?.zSeq,
        autoClosed: session?.autoClosed ?? false,
      ),
      refId: sessionId.toString(),
    );
  } catch (e) {
    Logger.instance.warning('session-closed notification failed: $e');
  }
}

/// `POS_Z_CLOSED` for [zId], summed from its sessions. Call after the close.
Future<void> notifyZClosed(ProviderReader read, int zId) async {
  try {
    final database = read(databaseProvider);
    final zService = ZService(database);
    final z = await zService.getById(zId);
    if (z == null) return;
    final sessions = await zService.sessionsForZ(zId);
    if (sessions.isEmpty) return;
    final openedAt = sessions
        .map((s) => s.startedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final closedAt = z.endedAt ?? DateTime.now();
    final report = await DailySummaryService(database).generateReport(
      startDate: openedAt,
      endDate: closedAt,
      sessionIds: sessions.map((s) => s.id).toList(),
    );
    final closedBy =
        z.endedBy == null ? null : await _userName(database, z.endedBy!);
    final label = ZService.labelOf(z);
    _send(
      read,
      'POS_Z_CLOSED',
      NotificationParams.zClosed(
        terminalName: _terminal(read),
        zDay: label.zDay,
        zSeq: label.zSeq,
        closeMode: z.closeMode ?? ZService.closeManual,
        closedByName: closedBy,
        openedAt: openedAt,
        closedAt: closedAt,
        report: report,
        currency: _currency(read),
        autoClosedSessions: sessions.where((s) => s.autoClosed).length,
        overridden: sessions.any((s) => s.zOverride),
      ),
      refId: '${label.zDay}#${label.zSeq}',
    );
  } catch (_) {}
}

/// Money handed back through the refund flow.
void notifyRefund(
  ProviderReader read, {
  required String orderCode,
  required double amount,
  String? method,
  String? reason,
}) {
  try {
    final actor = read(currentUserProvider);
    _send(
      read,
      'POS_CANCELLATION',
      {
        ...NotificationParams.cancellation(
          terminalName: _terminal(read),
          kind: 'REFUND',
          orderCode: orderCode,
          amount: amount,
          reason: reason,
          cashierName: actor?.effectiveDisplayName,
          cashierId: actor?.id,
          at: DateTime.now(),
          currency: _currency(read),
        ),
        if (method != null && method.isNotEmpty) 'method': method,
      },
      refId: orderCode,
    );
  } catch (_) {}
}
