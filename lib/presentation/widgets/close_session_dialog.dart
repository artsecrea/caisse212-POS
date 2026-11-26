import 'dart:math' as math;
import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';
import '../../providers/database_providers.dart';
import '../../providers/floor_repository.dart';
import '../../providers/order_provider.dart';
import '../../services/local_floor_service.dart';
import '../../services/local_payment_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/unpaid_orders_service.dart';
import '../../domain/models/order_models.dart';
import '../../services/daily_summary_service.dart';
import '../../utils/button_styles.dart';
import '../../services/printing_service.dart';
import '../../services/pos_notifications.dart' show notifySessionClosed;
import '../../services/session_service.dart';
import '../../services/z_actions.dart';
import '../../services/z_rules.dart' show ZRuleBlock, printSessionXWithZ;
import '../../services/z_service.dart';
import '../../data/database/app_database.dart' as db;
import '../../data/database/tables/activity_log_table.dart';
import '../../services/activity_log_service.dart';
import '../../services/permission_service.dart';
import '../../utils/admin_auth.dart'
    show showAdminCredentialDialog, userHasPermission;
import 'blocking_progress.dart';
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

  /// `true` if the session's Z was closed along with it.
  final bool zClosed;

  const CloseSessionResult({
    required this.closed,
    required this.zPrinted,
    this.zClosed = false,
  });

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
///
/// [allowContinue] false drops "end anyway": the admin requires the orders
/// paid before the Z closes. [canPay] false drops "pay all": there is no
/// open session left to receive the cash.
Future<_UnpaidAction?> _promptUnpaidOrders(
  BuildContext context,
  WidgetRef ref,
  List<OrderFullDetails> unpaid, {
  bool forZ = false,
  bool allowContinue = true,
  bool canPay = true,
}) async {
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
  final waiterIds = grouped.keys.whereType<int>().toList();
  final nameById = <int, String>{};
  if (waiterIds.isNotEmpty) {
    final waiterRows =
        await ref.read(floorRepositoryProvider).waitersByIds(waiterIds);
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
                .translate(forZ ? 'unpaid_orders_z_prompt' : 'unpaid_orders_prompt')
                .replaceAll('{0}', unpaid.length.toString())
                .replaceAll('{1}', fmt.format(total))),
            if (!allowContinue || !canPay) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: Theme.of(ctx).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.translate(!canPay
                          ? 'unpaid_orders_no_session'
                          : 'unpaid_orders_must_pay'),
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
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
            if (canPay) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: printReceipts,
                onChanged: (v) => setLocal(() => printReceipts = v ?? false),
                title: Text(l10n.translate('print_receipts')),
              ),
            ],
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
              if (canPay) ...[
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
              ],
              if (allowContinue) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: AppButtonStyles.outlinedButtonStyle(isLarge: true),
                    onPressed: () =>
                        Navigator.pop(ctx, const _UnpaidAction(pay: false)),
                    child: Text(l10n.translate(
                        forZ ? 'continue_without_paying' : 'proceed_and_end')),
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
  final progress =
      BlockingProgress.show(context, l10n.translate('settling_orders'));
  try {
    final printing = printReceipts ? ref.read(printingServiceProvider) : null;
    final cashier = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name');
    final businessAddress = prefs.getString('business_address');
    final businessPhone = prefs.getString('business_phone');

    for (final (i, o) in unpaid.indexed) {
      progress.message =
          '${l10n.translate('settling_orders')} ${i + 1}/${unpaid.length}';
      final due = o.total - o.totalPaid;
      final res = await ref
          .read(paymentServiceProvider)
          .settleAsCash(o.order.id, due, sessionId: sessionId);
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
            amount: due,
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
            reference: o.order.reference,
            tableName: o.tableName,
            numberOfPersons: o.order.persons,
          );
          await ref.read(paymentServiceProvider).recordPrint(res.ticketId);
        } catch (_) {/* print non-fatal — payment already committed */}
      }
    }
    progress.close();
    return true;
  } catch (e) {
    progress.close();
    if (context.mounted) {
      SnackBarHelper.error(
        context,
        l10n.translate('settle_failed').replaceAll('{0}', e.toString()),
      );
    }
    return false;
  }
}

/// Outcome of [runUnpaidOrdersGate].
enum UnpaidGateResult {
  /// Nothing was unpaid.
  none,

  /// Every unpaid order was settled as cash.
  settled,

  /// The person chose to go on with orders still unpaid.
  leftUnpaid,

  /// The close must not go ahead.
  cancelled,
}

/// The unpaid-orders question, over the orders of [sessionIds].
///
/// Settled cash goes to [cashSessionId], which must still be open so its
/// count and totals include it; null hides "pay all" (nothing can take the
/// cash). [forZ] words it as the day close, where the admin's
/// `allowZCloseWithUnpaid` decides whether going on unpaid is offered at all.
Future<UnpaidGateResult> runUnpaidOrdersGate(
  BuildContext context,
  WidgetRef ref, {
  required List<int> sessionIds,
  required int? cashSessionId,
  bool forZ = false,
}) async {
  final repo = ref.read(orderRepositoryProvider);
  final unpaid = <OrderFullDetails>[];
  if (sessionIds.isNotEmpty) {
    final res = await BlockingProgress.run(
      context,
      AppLocalizations.of(context)!.translate('checking_unpaid_orders'),
      (_) => repo.getPaginatedOrdersWithFullDetails(
        page: 0,
        pageSize: 500,
        sessionIds: sessionIds,
        unpaidOnly: true,
      ),
    );
    unpaid.addAll(res.orders.where((o) => (o.total - o.totalPaid) > 0.005));
  }
  if (unpaid.isEmpty) return UnpaidGateResult.none;
  if (!context.mounted) return UnpaidGateResult.cancelled;

  final allowContinue =
      !forZ || ref.read(settingsProvider).allowZCloseWithUnpaid;
  final action = await _promptUnpaidOrders(
    context,
    ref,
    unpaid,
    forZ: forZ,
    allowContinue: allowContinue,
    canPay: cashSessionId != null,
  );
  if (action == null) return UnpaidGateResult.cancelled;
  if (!action.pay) {
    if (forZ) {
      try {
        final me = ref.read(currentUserProvider);
        await ref.read(activityLogServiceProvider).log(
          ActivityAction.zClosed,
          'audit_z_close_unpaid',
          ['${unpaid.length}'],
          userId: me?.id,
          username: me?.effectiveDisplayName,
        );
      } catch (_) {}
    }
    return UnpaidGateResult.leftUnpaid;
  }
  if (!context.mounted) return UnpaidGateResult.cancelled;
  final ok = await _settleUnpaidAsCash(
      context, ref, unpaid, cashSessionId!, action.printReceipts);
  return ok ? UnpaidGateResult.settled : UnpaidGateResult.cancelled;
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
  /// Start with "close the Z" ticked — the top bar's "Close Z" entry, which
  /// is this same close with the day's Z on top.
  bool closeZ = false,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final sessionService = ref.read(sessionServiceProvider);
  final dailySummary = ref.read(dailySummaryServiceProvider);

  // Everything up to the dialog reads the day off disk — on a long history
  // that is seconds, and the button must not look dead meanwhile. Each step
  // that can prompt closes the overlay first.
  var preparing =
      BlockingProgress.show(context, l10n.translate('close_preparing'));

  final zService = ref.read(zServiceProvider);
  final (sessionZ, openZ, closesZWithSession, sessionsInZ) = await () async {
    try {
      // The Z this session belongs to. Null only on a legacy session opened
      // before Z tracking, which keeps the old per-session Z print.
      final session = await sessionService.getSessionById(sessionId);
      final sessionZ = session?.zId == null
          ? null
          : await zService.getById(session!.zId!);
      final openZ =
          sessionZ != null && sessionZ.status == 'open' ? sessionZ : null;
      // Closing the Z is never remembered: ending the trading day must be a
      // deliberate choice every time.
      // BY_SESSION: this close takes the Z with it, behind the scenes — the
      // cashier sees a plain session close.
      final closesZWithSession =
          openZ != null && await zClosesWithSessionFor(ref, openZ, sessionId);
      final sessionsInZ = closesZWithSession
          ? (await zService.sessionsForZ(openZ.id)).length
          : 0;
      return (sessionZ, openZ, closesZWithSession, sessionsInZ);
    } finally {
      preparing.close();
    }
  }();

  // Unpaid-orders gate, BEFORE the summary is computed so the expected-cash
  // figure reflects any just-settled orders. A close that takes the Z with it
  // asks about the whole Z's unpaid orders (the admin may require them paid);
  // a plain session close asks about this session's, if the admin wants that.
  // Ending with unpaid orders open leaves their tables occupied; otherwise the
  // session's tables are freed at close so the floor starts empty next time.
  bool freeTablesAtClose = true;
  final settings = ref.read(settingsProvider);
  final closesZUpFront = openZ != null && (closeZ || closesZWithSession);
  // Whether the Z's unpaid orders were already dealt with — ticking "close
  // the Z" later in the dialog asks only if not.
  bool zUnpaidChecked = false;
  {
    UnpaidGateResult gate = UnpaidGateResult.none;
    if (closesZUpFront && settings.unpaidPromptOnZClose) {
      zUnpaidChecked = true;
      final zSessions = await zService.sessionsForZ(openZ.id);
      if (!context.mounted) return CloseSessionResult.cancelled;
      gate = await runUnpaidOrdersGate(
        context,
        ref,
        sessionIds: [for (final s in zSessions) s.id],
        cashSessionId: sessionId,
        forZ: true,
      );
    } else if (settings.unpaidPromptOnSessionClose && context.mounted) {
      gate = await runUnpaidOrdersGate(
        context,
        ref,
        sessionIds: [sessionId],
        cashSessionId: sessionId,
      );
    }
    if (gate == UnpaidGateResult.cancelled) return CloseSessionResult.cancelled;
    if (gate == UnpaidGateResult.leftUnpaid) freeTablesAtClose = false;
  }

  if (!context.mounted) return CloseSessionResult.cancelled;
  preparing =
      BlockingProgress.show(context, l10n.translate('close_preparing'));
  SessionSummary summary;
  final StaffChoices staffChoices;
  try {
    summary = await sessionService.getSessionSummary(sessionId);
    staffChoices = await StaffChoices.load(ref.read(floorRepositoryProvider),
        ref.read(userRepositoryProvider), l10n);
  } finally {
    preparing.close();
  }
  var expected = summary.expectedCashAtEnd;
  final currencyFmt = ref.read(currencyFormatterProvider);

  // Pre-fill with the expected figure so a confirm without edits still
  // records a Z-report with variance = 0. Leaving the field blank previously
  // stored null and skipped the on-screen + printed Z block.
  final countedCtrl =
      TextEditingController(text: expected.toStringAsFixed(2));
  final notesCtrl = TextEditingController();
  bool busy = false;
  // The Z stays open after a session closes (unless it is closed with it), so
  // the only session-level print is an X. Offered as a checkbox, remembered.
  bool printX = ref.read(settingsProvider).printXOnSessionClose;
  // Extra tickets, each printed separately with its own cut. The same set the
  // Z dialog offers — a manager closing a till wants the same papers whether
  // they reach them from here or from there — so the choice, the UI and the
  // printing are shared. See [ReportDocumentsPicker]. Ticks are remembered.
  final documents = ReportDocuments.fromSettings(ref.read(settingsProvider));
  if (!context.mounted) return CloseSessionResult.cancelled;

  bool closeTheZ = closeZ && openZ != null && !closesZWithSession;

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

          // Closing the Z with the session is checked first, so a refusal
          // leaves the dialog exactly as it was.
          int? zClosedBy = ref.read(currentUserProvider)?.id;
          if (closeTheZ && openZ != null) {
            final by = await _authorizeZClose(ctx, ref, openZ);
            if (by == null) return;
            zClosedBy = by;
          }

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
          // Printing, sync and the email report can take a while (longer
          // offline, waiting on timeouts). Closed around the one prompt
          // below, and before this dialog pops — both share the root
          // navigator.
          if (!ctx.mounted) return;
          var progress = BlockingProgress.show(
              ctx, l10n.translate('closing_session_progress'));
          try {
            // 1. Close the session locally.
            await sessionService.endSession(
              sessionId: sessionId,
              countedCash: c,
              countNotes: notes.isEmpty ? null : notes,
            );
            // Every person-made close leaves a SESSION_END, so one missing
            // from the log points at a close nobody asked for.
            try {
              final me = ref.read(currentUserProvider);
              await ref.read(activityLogServiceProvider).logSessionEnd(
                    userId: me?.id,
                    username: me?.effectiveDisplayName,
                  );
            } catch (_) {}

            // 1b. Free the tables used this session so the floor starts empty
            //     next session. Covers orders paid earlier in the shift too
            //     (independent of the per-payment "auto-clear table" setting).
            //     Skipped when ending with unpaid orders still open.
            if (freeTablesAtClose) {
              try {
                await ref
                    .read(floorServiceProvider)
                    .freeTablesForSession(sessionId);
                ref.invalidate(areaTablesProvider);
              } catch (_) {}
            }

            // 2. Print. A session close prints at most an X — the Z report is
            //    the Z's, and prints only when the Z closes. A legacy session
            //    with no Z gets its X too (a Z would be printed before its
            //    day is closed).
            progress.message = l10n.translate('printing_reports_progress');
            bool printed = false;
            DailySummaryReport? zReport;
            // What the floor still owes as this shift ends — the figure the
            // outgoing cashier is handing over, which is by definition not in
            // the takings. Read once, before any printing, so both tickets
            // quote the same position.
            UnpaidOrdersSummary? outstanding;
            try {
              outstanding =
                  await ref.read(unpaidOrdersServiceProvider).summary();
            } catch (_) {}
            try {
              zReport = await dailySummary.generateSessionReport(sessionId);
              if (sessionZ == null) {
                printed = await ref
                    .read(printingServiceProvider)
                    .printDailySummaryReport(
                        report: zReport,
                        reportType: 'X',
                        outstanding: outstanding);
              } else if (closesZWithSession
                  ? printSessionXWithZ(sessionsInZ)
                  : printX) {
                printed = await ref
                    .read(printingServiceProvider)
                    .printDailySummaryReport(
                        report: zReport,
                        reportType: 'X',
                        outstanding: outstanding);
              }
            } catch (_) {}

            // 2b. AUTO_AFTER_HOUR: past the terminal's auto-close time, ASK
            //     whether to close the Z — never silently. A "No" is not
            //     remembered; the next session close asks again.
            //     BY_SESSION closes it without asking.
            var closeMode = ZService.closeManual;
            if (closesZWithSession) {
              closeTheZ = true;
              closeMode = ZService.closeAuto;
            } else if (!closeTheZ &&
                openZ != null &&
                zAutoCloseDueFor(ref, openZ)) {
              progress.close();
              var yes = await _askCloseDay(ctx, l10n);
              // The session is already counted and ended, so its unpaid
              // orders can only be acknowledged here, not settled.
              if (yes &&
                  ctx.mounted &&
                  ref.read(settingsProvider).unpaidPromptOnZClose) {
                final zSessions = await zService.sessionsForZ(openZ.id);
                final gate = !ctx.mounted
                    ? UnpaidGateResult.cancelled
                    : await runUnpaidOrdersGate(
                        ctx,
                        ref,
                        sessionIds: [for (final s in zSessions) s.id],
                        cashSessionId: null,
                        forZ: true,
                      );
                yes = gate != UnpaidGateResult.cancelled;
              }
              if (yes && ctx.mounted) {
                final by = await _authorizeZClose(ctx, ref, openZ);
                if (by != null) {
                  closeTheZ = true;
                  closeMode = ZService.closeAuto;
                  zClosedBy = by;
                }
              }
              if (!ctx.mounted) return;
              progress = BlockingProgress.show(
                  ctx, l10n.translate('printing_reports_progress'));
            }

            // 2c. Close the Z. After endSession above, so the Z's last
            //     session is this one, closed with its count — the session
            //     the server marks as closing the Z.
            int? closedZId;
            if (closeTheZ && openZ != null) {
              progress.message = l10n.translate('closing_z_progress');
              try {
                await closeZNow(ref, openZ,
                    closeMode: closeMode, endedBy: zClosedBy);
                closedZId = openZ.id;
                // The Z report is the day's legal document — always printed.
                final ok = await printZReport(ref, openZ.id, isX: false);
                printed = printed || ok;
              } catch (e) {
                Logger.instance.error('Z close failed: $e');
              }
            }

            // 2d. Extra tickets. Scope follows the action: closing the day
            //     covers the whole Z, otherwise just this session. Each prints
            //     as its own ticket with its own cut, and each failure is
            //     isolated so one bad ticket can't block the rest.
            // Scope follows the action: closing the day covers the whole Z,
            // otherwise just this session.
            final scopeSessionIds = closedZId != null
                ? [for (final s in await zService.sessionsForZ(closedZId)) s.id]
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
            progress.message = l10n.translate('syncing_with_server_progress');
            try {
              final syncService = ref.read(dataSyncServiceFactoryProvider)(
                  ref.read(apiServiceProvider));
              // The session carries its Z label, and — if it closed the Z —
              // the close fields. There is no separate Z push.
              await syncService.syncSessionsBulk();
              await syncService.syncCashMovementsBulk();
              await syncService.syncOrdersBulk();
              await syncService.syncTicketsBulk();
              // After orders + tickets, so each refund's order (and its server
              // line ids) already exist — and before the email report, whose
              // refundsTotal should reflect what the server now knows.
              await syncService.syncRefundsBulk();
            } catch (_) {}

            // 4. Send the email report (awaited — after sync so the server
            //    already has the session/orders/tickets it references).
            progress.message = l10n.translate('sending_report_progress');
            await _sendEmailReport(ref, dailySummary, sessionId);

            // 5. Fire-and-forget notification so admin devices get the Z summary.
            final closedReport = zReport;
            if (closedReport != null && closedReport.sessions.isNotEmpty) {
              unawaited(notifySessionClosed(ref.read, sessionId,
                  report: closedReport));
            }

            progress.close();
            if (ctx.mounted) {
              Navigator.of(ctx).pop(
                CloseSessionResult(
                    closed: true,
                    zPrinted: printed,
                    zClosed: closedZId != null),
              );
            }
          } catch (e) {
            progress.close();
            setLocal(() => busy = false);
            if (ctx.mounted) {
              SnackBarHelper.failure(ctx, e);
            }
          } finally {
            progress.close();
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

        Widget panel(String title, IconData icon, List<Widget> children) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          );
        }

        Widget line(String label, String value,
            {bool strong = false, Color? color}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          color: strong ? cs.onSurface : cs.onSurfaceVariant,
                          fontWeight: strong ? FontWeight.w700 : null)),
                ),
                Text(value,
                    style: TextStyle(
                        fontSize: strong ? 16 : 14,
                        fontWeight: strong ? FontWeight.bold : FontWeight.w600,
                        color: color)),
              ],
            ),
          );
        }

        String money(double v) => currencyFmt.format(v);

        // What was sold, by method — context for the count, not part of it.
        final summaryPanel = panel(l10n.translate('summary'),
            Icons.receipt_long_outlined, [
          line(l10n.translate('tickets'), '${summary.ticketCount}'),
          line(l10n.translate('total_sales'), money(summary.totalPaid),
              strong: true),
          const Divider(height: 16),
          line(l10n.translate('cash'), money(summary.totalCash)),
          line(l10n.translate('card'), money(summary.totalCard)),
          if (summary.totalMobile > 0)
            line(l10n.translate('mobile'), money(summary.totalMobile)),
          if (summary.totalOther > 0)
            line(l10n.translate('other'), money(summary.totalOther)),
          // A non-cash refund changes revenue but not the drawer, so it is a
          // memo line here — never part of the expected cash.
          if (summary.refundsTotal - summary.refundsCash > 0)
            line(l10n.translate('refunds_non_cash'),
                money(summary.refundsTotal - summary.refundsCash)),
        ]);

        // The drawer reconciliation, laid out as the sum it is so a cashier
        // can see why the expected figure is what it is.
        final cashPanel = panel(l10n.translate('cash'), Icons.payments_outlined, [
          line(l10n.translate('starting_balance'),
              money(summary.session.moneyAtStart)),
          line(l10n.translate('cash_sales'), '+${money(summary.totalCash)}'),
          if (summary.cashPaidIn > 0)
            line(l10n.translate('cash_paid_in'),
                '+${money(summary.cashPaidIn)}'),
          if (summary.cashPaidOut > 0)
            line(l10n.translate('cash_paid_out'),
                '-${money(summary.cashPaidOut)}'),
          // Refunds are not transactions, so they are invisible in the ticket
          // totals. Shown explicitly, otherwise the expected cash looks wrong
          // to a cashier who handed money back an hour ago.
          if (summary.refundsCash > 0)
            line(l10n.translate('refunds_cash_out'),
                '-${money(summary.refundsCash)}'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.translate('expected_cash'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer)),
                ),
                Text(
                  money(expected),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AdaptiveKeyboardTextField(
            controller: countedCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: l10n.translate('counted_cash'),
              prefixIcon: const Icon(Icons.payments_outlined),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setLocal(() {}),
          ),
          if (variance != null) ...[
            const SizedBox(height: 8),
            line(
              l10n.translate('variance'),
              '${variance >= 0 ? '+' : ''}${money(variance)}',
              strong: true,
              color: varianceColor,
            ),
          ],
          const SizedBox(height: 10),
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
        ]);

        final printPanel = panel(l10n.translate('printing'), Icons.print_outlined, [
          if (sessionZ != null && !closesZWithSession)
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
          // Extra tickets — each prints separately, and the choice is
          // remembered so a shop that always wants them ticks once.
          ReportDocumentsPicker(
            documents: documents,
            staff: staffChoices,
            enabled: !busy,
            onChanged: (persist) => setLocal(
                () => persist(ref.read(settingsProvider.notifier))),
          ),
        ]);

        // Close the Z with this session — the day-close gesture. Full width and
        // tinted so ending the trading day never reads as just another option.
        final zStrip = openZ != null && !closesZWithSession
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: closeTheZ
                      ? cs.errorContainer.withValues(alpha: 0.5)
                      : null,
                  border: Border.all(
                      color: closeTheZ ? cs.error : cs.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: closeTheZ,
                  onChanged: busy
                      ? null
                      : (v) async {
                          final tick = v ?? false;
                          // Ticked here rather than up front: the Z's unpaid
                          // orders are asked about now, and anything settled
                          // moves the expected cash.
                          if (tick &&
                              !zUnpaidChecked &&
                              ref.read(settingsProvider).unpaidPromptOnZClose) {
                            final zSessions =
                                await zService.sessionsForZ(openZ.id);
                            if (!ctx.mounted) return;
                            final gate = await runUnpaidOrdersGate(
                              ctx,
                              ref,
                              sessionIds: [for (final s in zSessions) s.id],
                              cashSessionId: sessionId,
                              forZ: true,
                            );
                            if (gate == UnpaidGateResult.cancelled) return;
                            zUnpaidChecked = true;
                            if (gate == UnpaidGateResult.leftUnpaid) {
                              freeTablesAtClose = false;
                            }
                            if (gate == UnpaidGateResult.settled) {
                              final before = expected;
                              summary = await sessionService
                                  .getSessionSummary(sessionId);
                              expected = summary.expectedCashAtEnd;
                              // An untouched pre-fill follows the new figure;
                              // a typed count is the cashier's and stays.
                              if (countedCtrl.text ==
                                  before.toStringAsFixed(2)) {
                                countedCtrl.text = expected.toStringAsFixed(2);
                              }
                            }
                          }
                          setLocal(() => closeTheZ = tick);
                        },
                  title: Text(
                    '${l10n.translate('close_z')} · ${ZService.displayName(openZ)}',
                    style:
                        TextStyle(color: cs.error, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(l10n.translate('close_the_day_subtitle')),
                ),
              )
            : null;

        final screen = MediaQuery.sizeOf(ctx);
        // Three panels side by side on a till screen; stacked on a phone.
        final wide = screen.width >= 900;
        const gap = SizedBox(width: 16, height: 16);

        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.point_of_sale, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.translate('close_session_title'))),
            ],
          ),
          content: SizedBox(
            width: wide ? math.min(1100.0, screen.width - 96) : 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: summaryPanel),
                        gap,
                        Expanded(flex: 5, child: cashPanel),
                        gap,
                        Expanded(flex: 5, child: printPanel),
                      ],
                    )
                  else ...[
                    cashPanel,
                    gap,
                    summaryPanel,
                    gap,
                    printPanel,
                  ],
                  if (zStrip != null) ...[gap, zStrip],
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
              label: Text(closeTheZ
                  ? l10n.translate('close_session_and_day')
                  : l10n.translate('close_session')),
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

/// Who may close [z] now: the current user, or an administrator who signs in
/// when the rules need someone else (`pos:z:close`, or `pos:z:override` before
/// the earliest-close time). Returns the closing user id, or null (refused —
/// the reason has been shown).
Future<int?> _authorizeZClose(
  BuildContext context,
  WidgetRef ref,
  db.Z z,
) async {
  final l10n = AppLocalizations.of(context)!;
  final perms = ref.read(permissionServiceProvider);
  final me = ref.read(currentUserProvider)?.id;
  final block = await zCloseBlock(
    ref,
    z,
    hasClosePermission: perms.hasPermission(Permissions.zClose),
    hasOverride: perms.hasPermission(Permissions.zOverride),
  );
  if (block == null) return me;
  if (!context.mounted) return null;
  final needs = switch (block.block) {
    ZRuleBlock.noClosePermission => Permissions.zClose,
    ZRuleBlock.tooEarlyToClose => Permissions.zOverride,
    _ => null,
  };
  if (needs == null) {
    SnackBarHelper.error(context, block.message(l10n));
    return null;
  }
  final elevation = await showAdminCredentialDialog(
    context,
    ref,
    title: l10n.translate('close_z'),
    description: block.message(l10n),
    permission: needs,
  );
  if (elevation == null) return null;
  // The signer must clear every rule, not just the one that stopped us.
  final signer =
      await ref.read(userRepositoryProvider).getUserById(elevation.adminId);
  if (signer == null) return null;
  final again = await zCloseBlock(
    ref,
    z,
    hasClosePermission: userHasPermission(signer, Permissions.zClose),
    hasOverride: userHasPermission(signer, Permissions.zOverride),
  );
  if (again != null) {
    if (context.mounted) SnackBarHelper.error(context, again.message(l10n));
    return null;
  }
  return elevation.adminId;
}

/// "Clôturer la journée (Z) ?" — asked when a session closes past the
/// terminal's auto-close time.
Future<bool> _askCloseDay(BuildContext context, AppLocalizations l10n) async {
  final yes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.translate('z_close_day_prompt')),
      content: Text(l10n.translate('z_close_day_prompt_body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.translate('no')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.translate('close_z')),
        ),
      ],
    ),
  );
  return yes == true;
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
    final session =
        await ref.read(sessionServiceProvider).getSessionById(sessionId);
    final z = session?.zId == null
        ? null
        : await ref.read(zServiceProvider).getById(session!.zId!);

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
      zNumber: z?.zSeq,
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
