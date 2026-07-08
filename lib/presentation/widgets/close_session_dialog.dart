import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_service.dart';
import '../../services/daily_summary_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/printing_service.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

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
          setLocal(() => busy = true);
          final c = counted();
          final notes = notesCtrl.text.trim();
          try {
            // 1. Close the session locally.
            await sessionService.endSession(
              sessionId: sessionId,
              countedCash: c,
              countNotes: notes.isEmpty ? null : notes,
            );

            // 2. Print Z-report (swallow errors — session already closed).
            bool printed = false;
            DailySummaryReport? zReport;
            try {
              zReport = await dailySummary.generateSessionReport(sessionId);
              printed = await ref
                  .read(printingServiceProvider)
                  .printDailySummaryReport(report: zReport);
            } catch (_) {}

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
              await syncService.syncSingleSession(sessionId);
              await syncService.syncOrdersBulk();
              await syncService.syncTicketsBulk();
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
              SnackBarHelper.error(ctx, '$e');
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  OnscreenKeyboardTextField(
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
                  OnscreenKeyboardTextField(
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
              label: Text(l10n.translate('end_session_and_print_z')),
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
    final durationMinutes =
        closedAt.difference(s.startedAt).inMinutes.toString();
    final moneyAtEnd =
        (s.startingBalance + s.paidByCash).toStringAsFixed(2);

    final params = <String, String>{
      'v': '1',
      'terminalName': posName,
      'cashierName': s.cashierName ?? 'Cashier #${s.cashierId}',
      'cashierId': s.cashierId.toString(),
      'sessionCode': s.sessionCode,
      'openedAt': s.startedAt.toIso8601String(),
      'closedAt': closedAt.toIso8601String(),
      'durationMinutes': durationMinutes,
      'currency': currency,
      'totalAmount': s.totalPaid.toStringAsFixed(2),
      'totalCash': s.paidByCash.toStringAsFixed(2),
      'totalCard': s.paidByCard.toStringAsFixed(2),
      'totalPhone': s.paidByPhone.toStringAsFixed(2),
      'totalOther': s.paidByOther.toStringAsFixed(2),
      'ordersCount': s.totalOrders.toString(),
      'ticketsCount': s.totalTickets.toString(),
      'unpaidAmount': s.unpaidAmount.toStringAsFixed(2),
      'cancelledAmount': s.cancelledAmount.toStringAsFixed(2),
      'moneyAtStart': s.startingBalance.toStringAsFixed(2),
      'moneyAtEnd': moneyAtEnd,
      if (s.countedCash != null)
        'countedCash': s.countedCash!.toStringAsFixed(2),
      if (s.variance != null) 'variance': s.variance!.toStringAsFixed(2),
      if (s.countNotes != null && s.countNotes!.isNotEmpty)
        'countNotes': s.countNotes!,
    };

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
    final payload = await dailySummary.buildEmailReportPayload(
      sessionId,
      currency: currency,
    );
    final sessionCode = (payload['session'] as Map)['code'] as String;
    await ref.read(apiServiceProvider).sendSessionEmailReport(sessionCode, payload);
  } catch (e) {
    Logger.instance.warning('email-report: failed for session $sessionId: $e');
  }
}
