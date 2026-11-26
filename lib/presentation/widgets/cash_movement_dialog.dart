import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../services/local_cash_session_service.dart';
import '../../services/cash_movement_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import './adaptive_text_field.dart';

/// Record cash entering or leaving the drawer for a reason that is not a sale,
/// and review what has already been recorded this session.
///
/// This is the missing half of cash reconciliation: opening float + cash sales
/// alone cannot predict the till, so every payout used to land as unexplained
/// variance on the Z report.
Future<bool> showCashMovementDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final session = ref.read(currentSessionProvider);

  if (session == null) {
    SnackBarHelper.error(context, l10n.translate('no_open_session_for_cash'));
    return false;
  }

  final service = ref.read(cashSessionServiceProvider);
  final fmt = ref.read(currencyFormatterProvider);
  final amountCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  final refCtrl = TextEditingController();
  var direction = CashMovementService.directionOut;
  var busy = false;

  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final cs = Theme.of(ctx).colorScheme;
      final isOut = direction == CashMovementService.directionOut;

      Future<void> submit() async {
        final amount =
            double.tryParse(amountCtrl.text.trim().replaceAll(',', '.'));
        if (amount == null || amount <= 0) {
          SnackBarHelper.error(ctx, l10n.translate('enter_valid_amount'));
          return;
        }
        if (reasonCtrl.text.trim().isEmpty) {
          SnackBarHelper.error(ctx, l10n.translate('reason_required'));
          return;
        }
        setLocal(() => busy = true);
        try {
          await service.recordMovement(
            direction: direction,
            amount: amount,
            reason: reasonCtrl.text,
            reference: refCtrl.text,
            sessionId: session.id,
            zDay: ref.read(currentZDayProvider),
            createdBy: ref.read(currentUserProvider)?.id,
          );
          amountCtrl.clear();
          reasonCtrl.clear();
          refCtrl.clear();
          setLocal(() => busy = false);
          if (ctx.mounted) {
            SnackBarHelper.success(ctx, l10n.translate('cash_movement_saved'));
          }
        } catch (e) {
          setLocal(() => busy = false);
          if (ctx.mounted) SnackBarHelper.failure(ctx, e);
        }
      }

      return AlertDialog(
        title: Row(children: [
          Icon(Icons.account_balance_wallet, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.translate('cash_movements'))),
        ]),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.translate('cash_movements_hint'),
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: CashMovementService.directionOut,
                      icon: const Icon(Icons.arrow_upward),
                      label: Text(l10n.translate('cash_out')),
                    ),
                    ButtonSegment(
                      value: CashMovementService.directionIn,
                      icon: const Icon(Icons.arrow_downward),
                      label: Text(l10n.translate('cash_in')),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: busy
                      ? null
                      : (s) => setLocal(() => direction = s.first),
                ),
                const SizedBox(height: 12),
                AdaptiveKeyboardTextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l10n.translate('amount'),
                    prefixIcon: Icon(isOut ? Icons.remove : Icons.add,
                        color: isOut ? cs.error : cs.tertiary),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                AdaptiveKeyboardTextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('reason'),
                    hintText: l10n.translate('cash_reason_hint'),
                    prefixIcon: const Icon(Icons.notes),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                AdaptiveKeyboardTextField(
                  controller: refCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('reference_optional'),
                    prefixIcon: const Icon(Icons.receipt_long),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: busy ? null : submit,
                    icon: const Icon(Icons.save),
                    label: Text(l10n.translate('record_movement')),
                  ),
                ),
                const Divider(height: 26),

                // What has already been recorded this session, with a running
                // net — the cashier needs to see it to trust their count.
                FutureBuilder<List<dynamic>>(
                  future: service.movementsOf(session.id),
                  builder: (ctx, snap) {
                    final rows = snap.data ?? const [];
                    if (rows.isEmpty) {
                      return Text(l10n.translate('no_cash_movements'),
                          style: TextStyle(color: cs.onSurfaceVariant));
                    }
                    var net = 0.0;
                    for (final r in rows) {
                      net += r.direction == CashMovementService.directionIn
                          ? r.amount as double
                          : -(r.amount as double);
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...rows.map((r) {
                          final rIn =
                              r.direction == CashMovementService.directionIn;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              rIn ? Icons.arrow_downward : Icons.arrow_upward,
                              color: rIn ? cs.tertiary : cs.error,
                              size: 18,
                            ),
                            title: Text(r.reason as String,
                                style: const TextStyle(fontSize: 14)),
                            subtitle: r.reference == null
                                ? null
                                : Text(r.reference as String),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${rIn ? '+' : '−'}${fmt.format(r.amount as double)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: rIn ? cs.tertiary : cs.error,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  tooltip: l10n.translate('delete'),
                                  onPressed: busy
                                      ? null
                                      : () async {
                                          await service
                                              .deleteMovement(r.id as int);
                                          setLocal(() {});
                                        },
                                ),
                              ],
                            ),
                          );
                        }),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(l10n.translate('net_effect_on_drawer'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${net >= 0 ? '+' : '−'}${fmt.format(net.abs())}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: net >= 0 ? cs.tertiary : cs.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('close')),
          ),
        ],
      );
    }),
  );

  amountCtrl.dispose();
  reasonCtrl.dispose();
  refCtrl.dispose();
  return changed ?? false;
}
