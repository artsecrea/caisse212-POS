import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/unpaid_orders_service.dart';
import '../../providers/z_day_provider.dart';
import '../../domain/models/order_models.dart';
import '../../services/daily_summary_service.dart';
import '../../utils/button_styles.dart';
import '../../services/data_sync_service.dart';
import '../../services/printing_service.dart';
import '../../services/notification_params.dart';
import '../../services/session_service.dart';
import '../../services/z_actions.dart';
import '../../data/database/tables/activity_log_table.dart';
import '../../services/activity_log_service.dart';
import '../../services/permission_service.dart';
import '../../utils/admin_auth.dart' show showAdminCredentialDialog;
import 'report_documents.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import './adaptive_text_field.dart';

/// Result returned to the caller when the user confirms session close.
class CloseSessionResult {
  /// `true` if the session was actually closed; `false` if the user cancelled.
  final bool closed;

  /// `true` if the Z-report print attempt succeeded (false if printer offline,
  /// no printer configured, etc.). Only meaningful when [closed] is true.
  final bool zPrinted;

  const CloseSessionResult({required this.closed, required this.zPrinted});

  static const cancelled = CloseSessionResult(closed: false, zPrinted: false);
}

/// Cashier's choice on the unpaid-orders gate at session close.
class _UnpaidAction {
  /// Settle all unpaid orders as cash before closing.
  final bool pay;
  /// Print a receipt per settled order.
  final bool printReceipts;
  const _UnpaidAction({required this.pay, this.printReceipts = false});
}

/// Prompts about the session's still-unpaid orders. Returns null if the cashier
/// cancels the whole close; otherwise a [_UnpaidAction] describing whether to
/// pay them all as cash and whether to print receipts.
Future<_UnpaidAction?> _promptUnpaidOrders(
  BuildContext context,
  WidgetRef ref,
  List<OrderFullDetails> unpaid,
) async {
  final l10n = AppLocalizations.of(context)!;
  final fmt = ref.read(currencyFormatterProvider);
  final total = unpaid.fold<double>(0, (s, o) => s + (o.total - o.totalPaid));
  bool printReceipts = false;

  // Per-waiter "owed" breakdown: group the unpaid dues by the order's waiter so
  // the cashier sees what they owe each waiter before settling. Orders with no
  // waiter (direct POS sales) fall under a "Direct" bucket.
  final grouped = <int?, ({int count, double amount})>{};
  for (final o in unpaid) {
    final due = o.total - o.totalPaid;
    final wid = o.order.waiterId;
    final cur = grouped[wid] ?? (count: 0, amount: 0.0);
    grouped[wid] = (count: cur.count + 1, amount: cur.amount + due);
  }
  final db = ref.read(databaseProvider);
  final waiterIds = grouped.keys.whereType<int>().toList();
  final nameById = <int, String>{};
  if (waiterIds.isNotEmpty) {
    final waiterRows =
        await (db.select(db.waiters)..where((w) => w.id.isIn(waiterIds))).get();
    for (final w in waiterRows) {
      nameById[w.id] = '${w.firstName} ${w.lastName ?? ''}'.trim();
    }
  }
  final waiterEntries = grouped.entries.where((e) => e.key != null).toList()
    ..sort((a, b) => b.value.amount.compareTo(a.value.amount));
  final breakdown = <({String label, int count, double amount})>[
    for (final e in waiterEntries)
      (
        label: nameById[e.key] ?? 'Waiter #${e.key}',
        count: e.value.count,
        amount: e.value.amount,
      ),
    if (grouped.containsKey(null))
      (
        label: l10n.translate('no_waiter_direct'),
        count: grouped[null]!.count,
        amount: grouped[null]!.amount,
      ),
  ];
  // Only surface the per-waiter section when at least one waiter is owed.
  final showWaiterBreakdown = waiterEntries.isNotEmpty;

  if (!context.mounted) return null;
  return showDialog<_UnpaidAction>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(l10n.translate('unpaid_orders')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(l10n
                .translate('unpaid_orders_prompt')
                .replaceAll('{0}', unpaid.length.toString())
                .replaceAll('{1}', fmt.format(total))),
            if (showWaiterBreakdown) ...[
              const SizedBox(height: 14),
              Text(
                l10n.translate('owed_to_waiters'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              ...breakdown.map((row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.person_outline, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(row.label)),
                        Text(
                          '${row.count} · ${fmt.format(row.amount)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  )),
              const Divider(height: 20),
            ],
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: printReceipts,
              onChanged: (v) => setLocal(() => printReceipts = v ?? false),
              title: Text(l10n.translate('print_receipts')),
            ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // Full-width, large touch targets stacked vertically (POS screens).
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: AppButtonStyles.elevatedButtonStyle(
                    isLarge: true,
                    backgroundColor: Theme.of(ctx).colorScheme.primary,
                    foregroundColor: Theme.of(ctx).colorScheme.onPrimary,
                  ),
                  onPressed: () => Navigator.pop(ctx,
                      _UnpaidAction(pay: true, printReceipts: printReceipts)),
                  child: Text(l10n.translate('pay_all_cash')),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: AppButtonStyles.outlinedButtonStyle(isLarge: true),
                  onPressed: () =>
                      Navigator.pop(ctx, const _UnpaidAction(pay: false)),
                  child: Text(l10n.translate('proceed_and_end')),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: AppButtonStyles.textButtonStyle(isLarge: true),
                  onPressed: () => Navigator.pop(ctx), // null = cancel the close
                  child: Text(l10n.translate('cancel')),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Settles every unpaid order as cash via [OrderRepository.settleOrderAsCash],
/// optionally printing a receipt per order. Returns false (and shows an error)
/// if any settlement throws, so the caller can abort the close.
Future<bool> _settleUnpaidAsCash(
  BuildContext context,
  WidgetRef ref,
  List<OrderFullDetails> unpaid,
  int sessionId,
  bool printReceipts,
) async {
  final l10n = AppLocalizations.of(context)!;
  final repo = ref.read(orderRepositoryProvider);
  final paidStatus = ref.read(settingsProvider).paidOrderDefaultStatus;
  try {
    final printing = printReceipts ? ref.read(printingServiceProvider) : null;
    final database = ref.read(databaseProvider);
    final cashier = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name');
    final businessAddress = prefs.getString('business_address');
    final businessPhone = prefs.getString('business_phone');

    for (final o in unpaid) {
      final due = o.total - o.totalPaid;
      final res = await repo.settleOrderAsCash(
        o.order.id,
        due,
        sessionId: sessionId,
        paidStatus: paidStatus,
      );
      if (res != null && printing != null) {
        try {
          final itemsForPrint = o.items
              .map((item) => {
                    'name': item.displayName,
                    'quantity': item.quantity,
                    'price': item.totalPrice,
                    'components': item.components
                        .map((c) => {'name': c.name, 'quantity': c.quantity})
                        .toList(),
                  })
              .toList();
          await printing.printPaymentDocuments(
            ticketId: res.ticketId,
            ticketNumber: res.ticketNum,
            amount: res.due,
            deliveryFee: PrintingService.feeForThisTicket(
              o.order.deliveryFee,
              anythingAlreadyPaid: o.totalPaid > 0,
            ),
            paymentMethod: 'CASH',
            createdAt: DateTime.now(),
            items: itemsForPrint,
            orderType: o.order.type,
            hasTable: o.order.tableId != null,
            orderCode: o.order.code,
            cashierName: cashier?.firstName,
            storeName: businessName,
            storeAddress: businessAddress,
            storePhone: businessPhone,
            customerName: o.customerName,
            customerPhone: o.customerPhone,
            deliveryAddress: o.order.address,
            tableName: o.tableName,
            numberOfPersons: o.order.persons,
          );
          await database.customStatement(
            'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
            [res.ticketId],
          );
        } catch (_) {/* print non-fatal — payment already committed */}
      }
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.error(
        context,
        l10n.translate('settle_failed').replaceAll('{0}', e.toString()),
      );
    }
    return false;
  }
}

/// Two-step session close: shows the cashier the expected cash from tickets,
/// lets them type the physical count and optional notes, and on confirm:
///   1. persists `countedCash` + `variance` + `countNotes` via
///      [SessionService.endSession];
///   2. fires a session-scoped daily summary print (Z-report) via
///      [PrintingService.printDailySummaryReport].
///
/// Returns the outcome so the caller can decide its follow-up navigation
/// (logout, snackbar, etc.). The dialog is non-dismissible: the user must
/// either Cancel or Confirm.
Future<CloseSessionResult> showCloseSessionDialog({
  required BuildContext context,
  required WidgetRef ref,
  required int sessionId,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final sessionService = SessionService(ref.read(databaseProvider));
  final dailySummary = DailySummaryService(ref.read(databaseProvider));

  // Unpaid-orders gate: if this session still has unpaid orders, let the
  // cashier settle them all as cash now (so the cash is captured in THIS
  // Z-report) or proceed and end anyway. Runs BEFORE the summary is computed
  // so the expected-cash figure reflects any just-settled orders.
  // When the cashier ends with unpaid orders still open, their tables stay
  // occupied; otherwise (no unpaid, or paid all) the session's tables are freed
  // at close so the floor starts empty next session.
  bool freeTablesAtClose = true;
  {
    final repo = ref.read(orderRepositoryProvider);
    final unpaidRes = await repo.getPaginatedOrdersWithFullDetails(
      page: 0,
      pageSize: 500,
      sessionId: sessionId,
      unpaidOnly: true,
    );
    final unpaid = unpaidRes.orders
        .where((o) => (o.total - o.totalPaid) > 0.005)
        .toList();
    if (unpaid.isNotEmpty && context.mounted) {
      final action = await _promptUnpaidOrders(context, ref, unpaid);
      if (action == null) return CloseSessionResult.cancelled; // user cancelled
      if (action.pay) {
        final ok = await _settleUnpaidAsCash(
            context, ref, unpaid, sessionId, action.printReceipts);
        if (!ok) return CloseSessionResult.cancelled; // settle failed → abort close
      } else {
        // Ending with unpaid orders open → leave their tables occupied.
        freeTablesAtClose = false;
      }
    }
  }

  final summary = await sessionService.getSessionSummary(sessionId);
  final expected = summary.expectedCashAtEnd;
  final currencyFmt = ref.read(currencyFormatterProvider);

  // Pre-fill with the expected figure so a confirm without edits still
  // records a Z-report with variance = 0. Leaving the field blank previously
  // stored null and skipped the on-screen + printed Z block.
  final countedCtrl =
      TextEditingController(text: expected.toStringAsFixed(2));
  final notesCtrl = TextEditingController();
  bool busy = false;
  // With Z tracking on, the shift stays open after this session closes, so the
  // only valid print is an X (snapshot). Offer it as a checkbox (remembered in
  // prefs) right inside this dialog instead of a second follow-up dialog.
  final zTracking = ref.read(settingsProvider).zTrackingEnabled;
  bool printX = ref.read(settingsProvider).printXOnSessionClose;
  // Z-tracking OFF only: append a compact whole-day rollup after the
  // per-session Z, covering every session of the closing session's z-day.
  bool printZDay = ref.read(settingsProvider).printZDayTotalOnClose;
  // Extra tickets, each printed separately with its own cut. The same set the
  // Z dialog offers — a manager closing a till wants the same papers whether
  // they reach them from here or from there — so the choice, the UI and the
  // printing are shared. See [ReportDocumentsPicker]. Ticks are remembered.
  final documents = ReportDocuments.fromSettings(ref.read(settingsProvider));
  final staffChoices =
      await StaffChoices.load(ref.read(databaseProvider), l10n);
  if (!context.mounted) return CloseSessionResult.cancelled;
  // Close the whole business day along with this session. Deliberately NOT
  // persisted — ending the trading day must be a fresh decision every time.
  bool closeDay = false;
  final dayLock = zTracking && ref.read(settingsProvider).zDayLockEnabled;

  final result = await showDialog<CloseSessionResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        double? counted() {
          final t = countedCtrl.text.trim().replaceAll(',', '.');
          if (t.isEmpty) return null;
          return double.tryParse(t);
        }

        Future<void> doConfirm() async {
          if (busy) return;
          final c = counted();

          // A session that does not balance — a short or over drawer, or
          // orders still unpaid on the floor — can be made a supervised
          // moment. Off by default: the discrepancy simply prints on the X,
          // which is what every till has always done.
          //
          // Asked BEFORE `busy` is set and before anything is written: a
          // refused sign-off has to leave the dialog exactly as it was, with
          // the cashier's count and notes still in front of them.
          if (closeNeedsSignOff(
            featureEnabled:
                ref.read(settingsProvider).requireAdminToCloseUnbalanced,
            countedCash: c,
            expectedCash: expected,
            hasUnpaidOrders: !freeTablesAtClose,
          )) {
            final permitted = ref
                .read(permissionServiceProvider)
                .hasPermission(Permissions.sessionsCloseUnbalanced);
            if (!permitted) {
              final elevation = await showAdminCredentialDialog(
                ctx,
                ref,
                title: l10n.translate('close_needs_signoff'),
                description: l10n.translate('close_needs_signoff_hint'),
                permission: Permissions.sessionsCloseUnbalanced,
              );
              if (elevation == null) return;
              // Who accepted the shortfall is the whole point of asking, so it
              // goes in the audit trail rather than only into the moment.
              try {
                await ref.read(activityLogServiceProvider).log(
                  ActivityAction.sessionEnd,
                  'audit_close_signed_off',
                  [
                    '$sessionId',
                    elevation.adminUsername,
                  ],
                  userId: elevation.adminId,
                  username: elevation.adminUsername,
                );
              } catch (e) {
                Logger.instance.error('Close sign-off audit failed: $e');
              }
            }
          }

          setLocal(() => busy = true);
          final notes = notesCtrl.text.trim();
          try {
            // 1. Close the session locally.
            await sessionService.endSession(
              sessionId: sessionId,
              countedCash: c,
              countNotes: notes.isEmpty ? null : notes,
            );

            // 1b. Free the tables used this session so the floor starts empty
            //     next session. Covers orders paid earlier in the shift too
            //     (independent of the per-payment "auto-clear table" setting).
            //     Skipped when ending with unpaid orders still open.
            if (freeTablesAtClose) {
              try {
                await ref
                    .read(orderRepositoryProvider)
                    .clearTablesForSession(sessionId);
                ref.invalidate(areaTablesProvider);
              } catch (_) {}
            }

            // 2. Print the per-session Z-report — but only when Z (shift)
            //    tracking is OFF. With Z tracking, the shift owns reporting: the
            //    caller offers an X (snapshot) print on session close and the Z
            //    report prints at shift close, so we skip the per-session print.
            bool printed = false;
            DailySummaryReport? zReport;
            final zTracking = ref.read(settingsProvider).zTrackingEnabled;
            // What the floor still owes as this shift ends — the figure the
            // outgoing cashier is handing over, which is by definition not in
            // the takings. Read once, before any printing, so both tickets
            // quote the same position.
            UnpaidOrdersSummary? outstanding;
            try {
              outstanding =
                  await UnpaidOrdersService(ref.read(databaseProvider))
                      .summary();
            } catch (_) {}
            try {
              zReport = await dailySummary.generateSessionReport(sessionId);
              if (!zTracking) {
                printed = await ref
                    .read(printingServiceProvider)
                    .printDailySummaryReport(
                        report: zReport, outstanding: outstanding);
              }

              // Optional day-summary (z-day) total — the whole-day rollup of
              // every session sharing this session's opening day. Offered on
              // close regardless of Z tracking; prints right after the per-
              // session Z (or on its own when Z tracking owns the reporting).
              if (printZDay) {
                final s = zReport.sessions.firstOrNull;
                if (s != null) {
                  final zDay = DateTime(
                      s.startedAt.year, s.startedAt.month, s.startedAt.day);
                  final dayReport =
                      await dailySummary.generateZDayReport(zDay);
                  final ok = await ref
                      .read(printingServiceProvider)
                      .printZDayTotal(report: dayReport);
                  printed = printed || ok;
                }
              }
            } catch (_) {}

            // 2b. With Z tracking, print an X for THIS session only if the
            //     cashier ticked the box. The X here is a per-session snapshot;
            //     the whole-shift totals print as the Z report at shift close.
            if (zTracking && printX && zReport != null) {
              try {
                printed = await ref
                    .read(printingServiceProvider)
                    .printDailySummaryReport(
                        report: zReport,
                        reportType: 'X',
                        outstanding: outstanding);
              } catch (_) {}
            }

            // 2c. Close the whole business day. Runs AFTER endSession above:
            //     ZService.closeZ auto-ends any still-open session WITHOUT a
            //     cash count, so closing the Z first would silently discard
            //     the count and variance the cashier just typed.
            int? closedZId;
            if (zTracking && closeDay) {
              try {
                final z = ref.read(currentZProvider) ??
                    await ref.read(zServiceProvider).getOpenZ();
                closedZId = z?.id;
                final user = ref.read(currentUserProvider);
                await closeBusinessDay(
                  ref,
                  endedBy: user?.id,
                  endedByName: user == null
                      ? null
                      : '${user.firstName} ${user.lastName}'.trim(),
                );
                // The Z report is the day's legal document — always printed.
                if (closedZId != null) {
                  final ok = await printZReport(ref, closedZId, isX: false);
                  printed = printed || ok;
                }
              } catch (_) {/* the day close itself already committed */}
            }

            // 2d. Extra tickets. Scope follows the action: closing the day
            //     covers the whole Z, otherwise just this session. Each prints
            //     as its own ticket with its own cut, and each failure is
            //     isolated so one bad ticket can't block the rest.
            // Scope follows the action: closing the day covers the whole Z,
            // otherwise just this session.
            final scopeSessionIds = closedZId != null
                ? [
                    for (final s in await ref
                        .read(zServiceProvider)
                        .sessionsForZ(closedZId))
                      s.id
                  ]
                : <int>[sessionId];
            final scopeLabel =
                zReport?.sessions.firstOrNull?.sessionCode ?? '#$sessionId';
            final run = await printReportDocuments(
              ref: ref,
              documents: documents,
              sessionIds: scopeSessionIds,
              scopeLabel: scopeLabel,
              l10n: l10n,
            );
            printed = printed || run.printed > 0;

            // 3. Push session + orders + tickets to the server so the
            //    email-report payload reflects freshly synced data.
            //    Best-effort: network errors are swallowed; the spinner
            //    stays visible while this runs. If offline, the session
            //    stays isSynced=false and syncSessionsBulk picks it up later.
            try {
              final syncService = DataSyncService(
                ref.read(databaseProvider),
                ref.read(apiServiceProvider),
              );
              // Zs go FIRST: sessions reference their Z by code, so a session
              // pushed before its Z lands on the server orphaned.
              await syncService.syncZsBulk();
              await syncService.syncSingleSession(sessionId);
              await syncService.syncOrdersBulk();
              await syncService.syncTicketsBulk();
              // After orders + tickets, so each refund's order (and its server
              // line ids) already exist — and before the email report, whose
              // refundsTotal should reflect what the server now knows.
              await syncService.syncRefundsBulk();
            } catch (_) {}

            // 4. Send the email report (awaited — after sync so the server
            //    already has the session/orders/tickets it references).
            await _sendEmailReport(ref, dailySummary, sessionId);

            // 5. Fire-and-forget notification so admin devices get the Z summary.
            final sessionReport = zReport?.sessions.firstOrNull;
            if (sessionReport != null) {
              unawaited(_sendClosedNotification(ref, sessionReport, sessionId));
            }

            if (ctx.mounted) {
              Navigator.of(ctx).pop(
                CloseSessionResult(closed: true, zPrinted: printed),
              );
            }
          } catch (e) {
            setLocal(() => busy = false);
            if (ctx.mounted) {
              SnackBarHelper.failure(ctx, e);
            }
          }
        }

        final cs = Theme.of(ctx).colorScheme;
        final c = counted();
        final variance = c == null ? null : c - expected;
        // Variance semantics:
        //   |variance| ~ 0  → on-target  → success token
        //   variance  < 0   → short      → error token
        //   variance  > 0   → over       → warning token
        // No variance yet → muted onSurfaceVariant.
        final varianceColor = variance == null
            ? cs.onSurfaceVariant
            : (variance.abs() < 0.005
                ? cs.tertiary
                : (variance < 0 ? cs.error : cs.secondary));

        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.point_of_sale, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.translate('close_session_title'))),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (zTracking) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: printX,
                      onChanged: busy
                          ? null
                          : (v) {
                              setLocal(() => printX = v ?? false);
                              ref
                                  .read(settingsProvider.notifier)
                                  .setPrintXOnSessionClose(v ?? false);
                            },
                      title: Text(l10n.translate('print_x_report')),
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Day-summary (z-day) total — always offered on close, whether
                  // or not Z tracking is on. Prints the whole-day rollup of every
                  // session sharing this session's opening day.
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: printZDay,
                    onChanged: busy
                        ? null
                        : (v) {
                            setLocal(() => printZDay = v ?? false);
                            ref
                                .read(settingsProvider.notifier)
                                .setPrintZDayTotalOnClose(v ?? false);
                          },
                    title: Text(l10n.translate('print_z_day_total')),
                    subtitle: Text(l10n.translate('print_z_day_total_subtitle')),
                  ),
                  // Extra tickets — each prints separately, and the choice is
                  // remembered so a shop that always wants them ticks once.
                  ReportDocumentsPicker(
                    documents: documents,
                    staff: staffChoices,
                    enabled: !busy,
                    onChanged: (persist) => setLocal(
                        () => persist(ref.read(settingsProvider.notifier))),
                  ),
                  // Day close — the fiscal gesture. Never remembered: ending
                  // the trading day must be a deliberate choice every time.
                  if (zTracking) ...[
                    const Divider(height: 16),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: closeDay,
                      onChanged:
                          busy ? null : (v) => setLocal(() => closeDay = v ?? false),
                      title: Text(
                        l10n.translate('close_the_day'),
                        style: TextStyle(
                            color: cs.error, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(dayLock
                          ? l10n.translate('day_close_warning')
                          : l10n.translate('close_the_day_subtitle')),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.translate('expected_cash'),
                            style: TextStyle(
                                fontSize: 13,
                                color: cs.onPrimaryContainer
                                    .withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          currencyFmt.format(expected),
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: cs.onPrimaryContainer),
                        ),
                        // Refunds are not transactions, so they are invisible in
                        // the ticket totals this figure is built from. Shown
                        // explicitly, otherwise the expected cash looks wrong to
                        // a cashier who handed money back an hour ago.
                        if (summary.refundsCash > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.undo,
                                  size: 14,
                                  color: cs.onPrimaryContainer
                                      .withValues(alpha: 0.8)),
                              const SizedBox(width: 6),
                              Text(
                                '${l10n.translate('refunds_cash_out')}: '
                                '-${currencyFmt.format(summary.refundsCash)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onPrimaryContainer
                                        .withValues(alpha: 0.9)),
                              ),
                            ],
                          ),
                        ],
                        // A non-cash refund changes revenue but not the drawer,
                        // so it is a memo line only — never subtracted above.
                        if (summary.refundsTotal - summary.refundsCash > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${l10n.translate('refunds_non_cash')}: '
                            '${currencyFmt.format(summary.refundsTotal - summary.refundsCash)}',
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onPrimaryContainer
                                    .withValues(alpha: 0.7)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AdaptiveKeyboardTextField(
                    controller: countedCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.translate('counted_cash'),
                      prefixIcon: const Icon(Icons.payments_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  if (variance != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          '${l10n.translate('variance')}:',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${variance >= 0 ? '+' : ''}${currencyFmt.format(variance)}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: varianceColor),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  AdaptiveKeyboardTextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: l10n.translate('count_notes'),
                      hintText: l10n.translate('count_notes_hint'),
                      prefixIcon: const Icon(Icons.notes),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () =>
                      Navigator.of(ctx).pop(CloseSessionResult.cancelled),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: busy ? null : doConfirm,
              icon: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.onError),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(closeDay
                  ? l10n.translate('close_session_and_day')
                  : zTracking
                      ? l10n.translate('close_session')
                      : l10n.translate('end_session_and_print_z')),
              style: ElevatedButton.styleFrom(
                backgroundColor: cs.error,
                foregroundColor: cs.onError,
              ),
            ),
          ],
        );
      });
    },
  );

  countedCtrl.dispose();
  notesCtrl.dispose();
  return result ?? CloseSessionResult.cancelled;
}

/// POSTs a POS_SESSION_CLOSED notification from the Z-report data.
/// Never throws — best-effort only.
Future<void> _sendClosedNotification(
  WidgetRef ref,
  SessionSummaryReport s,
  int sessionId,
) async {
  try {
    final currency = ref.read(settingsProvider).currency;
    final posName = ref.read(apiServiceProvider).getPosName() ?? '';
    final closedAt = s.endedAt ?? DateTime.now();

    final params = NotificationParams.sessionClosed(
      terminalName: posName,
      report: s,
      closedAt: closedAt,
      // The same expected-cash definition the close dialog and the printed Z
      // use, so Expected / Counted / Variance agree on the mobile card.
      expectedCash: s.expectedCash,
      currency: currency,
    );

    await ref.read(apiServiceProvider).postNotification(
      type: 'POS_SESSION_CLOSED',
      params: params,
      refId: sessionId.toString(),
      clientRequestId: const Uuid().v4(),
    );
  } catch (e) {
    Logger.instance.warning('session-closed notification failed: $e');
  }
}

/// Builds and POSTs the session email-report payload.
/// Never throws — failures are logged so the dialog close is never blocked.
Future<void> _sendEmailReport(
  WidgetRef ref,
  DailySummaryService dailySummary,
  int sessionId,
) async {
  try {
    final currency = ref.read(settingsProvider).currency;
    final zNumber = ref.read(zDayStateProvider).zNumber;

    // The server's idempotency key is (tenant, sessionCode, clientRequestId).
    // Minting a fresh uuid per attempt would make a retry — or a second close
    // of the same session from Sessions Management — look like a new request
    // and send a duplicate email. So it is generated once per session and kept
    // in prefs until the server accepts it.
    final prefs = ref.read(sharedPreferencesProvider);
    final ridKey = 'email_report_rid_$sessionId';
    var rid = prefs.getString(ridKey);
    if (rid == null) {
      rid = const Uuid().v4();
      await prefs.setString(ridKey, rid);
    }

    final payload = await dailySummary.buildEmailReportPayload(
      sessionId,
      currency: currency,
      zNumber: zNumber == 0 ? null : zNumber,
      clientRequestId: rid,
    );
    final sessionCode = (payload['session'] as Map)['code'] as String;
    await ref.read(apiServiceProvider).sendSessionEmailReport(sessionCode, payload);
    // Accepted (any of the five terminal statuses) — the key has done its job.
    await prefs.remove(ridKey);
  } catch (e) {
    // Key deliberately left in prefs so the next attempt reuses it.
    Logger.instance.warning('email-report: failed for session $sessionId: $e');
  }
}
