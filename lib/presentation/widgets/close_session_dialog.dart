import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../services/daily_summary_service.dart';
import '../../services/printing_service.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

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
            await sessionService.endSession(
              sessionId: sessionId,
              countedCash: c,
              countNotes: notes.isEmpty ? null : notes,
            );

            // Z-report — same calc pipeline as the daily summary.
            bool printed = false;
            try {
              final report =
                  await dailySummary.generateSessionReport(sessionId);
              final ok = await ref
                  .read(printingServiceProvider)
                  .printDailySummaryReport(report: report);
              printed = ok;
            } catch (_) {
              // Swallow print errors — the session is already closed; the
              // cashier can reprint later from the daily summary screen.
            }

            if (ctx.mounted) {
              Navigator.of(ctx).pop(
                CloseSessionResult(closed: true, zPrinted: printed),
              );
            }
          } catch (e) {
            setLocal(() => busy = false);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  content: Text('$e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }

        final c = counted();
        final variance = c == null ? null : c - expected;
        final varianceColor = variance == null
            ? Colors.grey
            : (variance.abs() < 0.005
                ? Colors.green
                : (variance < 0 ? Colors.red : Colors.orange));

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.point_of_sale, color: Colors.blue),
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
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.translate('expected_cash'),
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          currencyFmt.format(expected),
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue),
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
                              color: Colors.grey[700],
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
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: Text(l10n.translate('end_session_and_print_z')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
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
