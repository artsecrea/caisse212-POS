import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/unpaid_orders_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import '../../domain/models/z_day_option.dart';

/// Which trading day absorbs the cash when stale orders are settled in bulk.
enum SettleTarget {
  /// Each order settles into the session it already belongs to, on that
  /// session's Z-day. The books stay as they were: the money is recorded on
  /// the day it was taken, and a Z already printed for that day no longer
  /// matches it.
  ownSession,

  /// Everything lands on the session open right now. The cleanest story for a
  /// shop clearing a backlog: one day absorbs it, and that day's Z says so.
  currentDay,

  /// A day the admin picks — for a backlog that belongs to a specific day
  /// that has since been reconciled.
  chosenDay,
}

/// Settle every stale unpaid order in one pass, and decide where the money
/// lands.
///
/// Unpaid orders accumulate: a table nobody closed, a parked takeaway, an
/// order left behind by a shift that ended. Each one holds a table, shows up
/// on every outstanding report, and blocks nothing — so nobody deals with it,
/// and a month later there are forty. This is the broom.
///
/// The orders keep their cashier (`takenBy`) throughout. That is the point of
/// "with their cashiers": an admin tidying the books must not quietly make
/// last week's takings their own. Only the accounting DAY is the admin's
/// choice, and the three options are the three honest answers.
///
/// Admin-gated by the caller.
Future<void> showSettleUnpaidDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final sessionService = ref.read(sessionServiceProvider);

  final entries = await ref.read(unpaidOrdersServiceProvider).unpaidOrders();
  if (!context.mounted) return;
  if (entries.isEmpty) {
    SnackBarHelper.error(context, l10n.translate('nothing_outstanding'));
    return;
  }

  final days = await ref.read(zServiceProvider).zDayOptions();
  final session = ref.read(currentSessionProvider);
  if (!context.mounted) return;

  final selected = {for (final e in entries) e.order.id};
  var target = SettleTarget.currentDay;
  var chosenDay = days.isEmpty ? null : days.first;
  var printReceipts = false;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final scheme = Theme.of(ctx).colorScheme;
        final currency = ref.read(currencyFormatterProvider);
        final chosen = [
          for (final e in entries)
            if (selected.contains(e.order.id)) e,
        ];
        final total = chosen.fold(0.0, (s, e) => s + e.due);
        // Nowhere to put today's money if no session is open.
        final canUseToday = session != null && session.status == 'active';
        if (target == SettleTarget.currentDay && !canUseToday) {
          target = SettleTarget.ownSession;
        }

        Widget option(SettleTarget value, String title, String subtitle,
                {bool enabled = true}) =>
            RadioListTile<SettleTarget>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: value,
              // ignore: deprecated_member_use
              groupValue: target,
              // ignore: deprecated_member_use
              onChanged:
                  enabled ? (v) => setLocal(() => target = v ?? target) : null,
              title: Text(
                title,
                style: TextStyle(
                  color:
                      enabled ? null : scheme.onSurface.withValues(alpha: 0.38),
                ),
              ),
              subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
            );

        return AlertDialog(
          title: Text(l10n.translate('settle_unpaid_orders')),
          content: SizedBox(
            width: 620,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.translate('settle_unpaid_hint'),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                option(
                  SettleTarget.currentDay,
                  l10n.translate('settle_into_today'),
                  l10n.translate('settle_into_today_hint'),
                  enabled: canUseToday,
                ),
                option(
                  SettleTarget.ownSession,
                  l10n.translate('settle_into_own'),
                  l10n.translate('settle_into_own_hint'),
                ),
                option(
                  SettleTarget.chosenDay,
                  l10n.translate('settle_into_day'),
                  l10n.translate('settle_into_day_hint'),
                  enabled: days.isNotEmpty,
                ),
                if (target == SettleTarget.chosenDay)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
                    child: DropdownButtonFormField<ZDayOption>(
                      initialValue: chosenDay,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.translate('z_day'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final d in days)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (v) => setLocal(() => chosenDay = v),
                    ),
                  ),
                const Divider(height: 16),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setLocal(() {
                        if (selected.length == entries.length) {
                          selected.clear();
                        } else {
                          selected
                            ..clear()
                            ..addAll([for (final e in entries) e.order.id]);
                        }
                      }),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text(l10n.translate('select_all')),
                    ),
                    const Spacer(),
                    Text(
                      '${chosen.length} / ${entries.length}   ·   '
                      '${currency.format(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected.contains(e.order.id),
                        onChanged: (v) => setLocal(() => v == true
                            ? selected.add(e.order.id)
                            : selected.remove(e.order.id)),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(e.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text(currency.format(e.due),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        subtitle: Text(
                          '${e.order.code}   ·   '
                          '${e.holderName ?? l10n.translate('unassigned')}'
                          '${e.sessionCode == null ? '' : '   ·   ${e.sessionCode}'}',
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: printReceipts,
                  onChanged: (v) =>
                      setLocal(() => printReceipts = v ?? false),
                  title: Text(l10n.translate('print_receipts')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: chosen.isEmpty ||
                      (target == SettleTarget.chosenDay && chosenDay == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.price_check_rounded, size: 18),
              label: Text(l10n.translate('settle_as_cash')),
            ),
          ],
        );
      },
    ),
  );
  if (go != true || !context.mounted) return;

  final repo = ref.read(orderRepositoryProvider);
  final paidStatus = ref.read(settingsProvider).paidOrderDefaultStatus;
  final toSettle = [
    for (final e in entries)
      if (selected.contains(e.order.id)) e,
  ];

  /// Which session records each order's ticket, given the chosen target.
  ///
  /// For a chosen day, a session belonging to the order's own cashier wins —
  /// keeping the takings under the person who rang them up, which is what
  /// "with their cashiers" asks for. Failing that, the day's first session:
  /// the day has to absorb it somewhere, and an unattributed ticket on the
  /// right day beats a ticket on the wrong one.
  Future<int?> sessionFor(UnpaidOrderEntry e) async {
    switch (target) {
      case SettleTarget.ownSession:
        return e.sessionId;
      case SettleTarget.currentDay:
        return session?.id ?? e.sessionId;
      case SettleTarget.chosenDay:
        final ids = chosenDay?.sessionIds ?? const <int>[];
        if (ids.isEmpty) return e.sessionId;
        final rows =
            await sessionService.getSessionsByIds(ids, oldestFirst: true);
        final own = rows.where((s) => s.cashierId == e.holderId);
        return own.isNotEmpty ? own.first.id : rows.first.id;
    }
  }

  DateTime? zDayFor() {
    switch (target) {
      case SettleTarget.ownSession:
        // Null = let the session's own day decide, which is the whole point.
        return null;
      case SettleTarget.currentDay:
        return ref.read(currentZDayProvider);
      case SettleTarget.chosenDay:
        return chosenDay?.day;
    }
  }

  var settled = 0;
  var failed = 0;
  final zDay = zDayFor();
  final printing = printReceipts ? ref.read(printingServiceProvider) : null;
  final cashier = ref.read(currentUserProvider);

  for (final e in toSettle) {
    try {
      final res = await repo.settleOrderAsCash(
        e.order.id,
        e.due,
        sessionId: await sessionFor(e),
        paidStatus: paidStatus,
        zDayOverride: zDay,
      );
      settled++;

      if (res != null && printing != null) {
        // Non-fatal, and deliberately after the count: the payment is already
        // committed, and a dead printer must not make a settled order look
        // unsettled. The store identity is left to the printing service,
        // which resolves it from settings.
        try {
          final lines = await repo.getOrderById(e.order.id);
          await printing.printPaymentDocuments(
            ticketId: res.ticketId,
            ticketNumber: res.ticketNum,
            amount: res.due,
            paymentMethod: 'CASH',
            createdAt: DateTime.now(),
            items: [
              for (final item in lines?.items ?? const [])
                {
                  'name': item.displayName,
                  'quantity': item.quantity,
                  'price': item.totalPrice,
                  'components': [
                    for (final c in item.components)
                      {'name': c.name, 'quantity': c.quantity},
                  ],
                },
            ],
            orderType: e.order.type,
            hasTable: e.isTable,
            orderCode: e.order.code,
            cashierName: cashier?.firstName,
            tableName: e.tableName,
            numberOfPersons: e.order.persons,
          );
        } catch (err) {
          Logger.instance
              .error('Settle receipt failed for #${e.order.id}: $err');
        }
      }
    } catch (err) {
      // One stubborn order must not strand the other thirty-nine.
      failed++;
      Logger.instance.error('Bulk settle failed for #${e.order.id}: $err');
    }
  }

  try {
    await repo.reconcileTableOccupancy(
        freeOnPayment: ref.read(settingsProvider).autoClearTableAfterPaying);
  } catch (_) {}
  ref.invalidate(areaTablesProvider);

  if (!context.mounted) return;
  if (failed == 0) {
    SnackBarHelper.success(
      context,
      l10n.translate('orders_settled').replaceAll('{0}', '$settled'),
    );
  } else {
    SnackBarHelper.error(
      context,
      l10n
          .translate('orders_settled_partial')
          .replaceAll('{0}', '$settled')
          .replaceAll('{1}', '${settled + failed}'),
    );
  }
}
