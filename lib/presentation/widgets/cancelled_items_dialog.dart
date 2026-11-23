import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/models/order_models.dart';
import '../../providers/order_cancellations_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

/// The "Cancelled" line under the order panel's tax row: how much was taken
/// off this order, recorded and not yet saved. Hidden when nothing was.
/// Tapping it lists every cancelled item.
class CancelledSummaryRow extends ConsumerWidget {
  const CancelledSummaryRow({super.key, required this.order});

  final CurrentOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderId = order.orderId;
    if (orderId == null) return const SizedBox.shrink();
    final recorded =
        ref.watch(orderCancellationsProvider(orderId)).valueOrNull ?? const [];
    final saved =
        ref.watch(savedOrderLinesProvider(orderId)).valueOrNull ?? const [];
    final pending = pendingCancellations(order, saved);
    if (recorded.isEmpty && pending.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);
    final color = Theme.of(context).colorScheme.error;
    final total = recorded.fold<double>(0, (s, r) => s + r.amount) +
        pending.fold<double>(0, (s, p) => s + p.amount);
    final count = recorded.length + pending.length;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => CancelledItemsDialog(order: order),
        ),
        child: Row(
          children: [
            Icon(Icons.remove_shopping_cart_outlined, size: 13, color: color),
            const SizedBox(width: 3),
            Text(
              '${l10n.translate('cancelled_items')} ($count):',
              style: TextStyle(fontSize: 12, color: color),
            ),
            const SizedBox(width: 2),
            Icon(Icons.info_outline, size: 12, color: color),
            const Spacer(),
            Text(
              money.format(total),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
                decoration: TextDecoration.lineThrough,
                decorationColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The other way to show the same list as [CancelledItemsDialog]: every
/// cancelled item as a struck-through row under the order's live lines
/// (setting `showCancelledItemsAsRows`). Display only — the rows cannot be
/// edited, and tapping one opens the dialog with who and when.
class CancelledItemRows extends ConsumerWidget {
  const CancelledItemRows({super.key, required this.order});

  final CurrentOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderId = order.orderId;
    if (orderId == null) return const SizedBox.shrink();
    final recorded =
        ref.watch(orderCancellationsProvider(orderId)).valueOrNull ?? const [];
    final saved =
        ref.watch(savedOrderLinesProvider(orderId)).valueOrNull ?? const [];
    final pending = pendingCancellations(order, saved);
    if (recorded.isEmpty && pending.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.error;

    Widget row(String label, double amount, String? note) => InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => CancelledItemsDialog(order: order),
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.errorContainer.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.block, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: color,
                        ),
                      ),
                      if (note != null)
                        Text(note,
                            style: TextStyle(fontSize: 11, color: color)),
                    ],
                  ),
                ),
                Text(
                  money.format(amount),
                  style: TextStyle(
                    color: color,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: color,
                  ),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
          child: Text(
            l10n.translate('cancelled_items'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        for (final p in pending)
          row('${_qty(p.quantity)}× ${p.name}', p.amount,
              l10n.translate('cancelled_not_saved')),
        for (final r in recorded)
          row(
            '${_qty(r.quantity)}× ${r.productName}'
            '${r.variantName == null ? '' : ' (${r.variantName})'}',
            r.amount,
            r.removedByName?.isNotEmpty == true ? r.removedByName : null,
          ),
      ],
    );
  }
}

String _qty(double q) =>
    q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(3);

/// Every item cancelled on [order]: the unsaved ones first, then what is
/// recorded, newest first, with who, when and whether the kitchen had it.
class CancelledItemsDialog extends ConsumerWidget {
  const CancelledItemsDialog({super.key, required this.order});

  final CurrentOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);
    final orderId = order.orderId!;
    final recorded =
        ref.watch(orderCancellationsProvider(orderId)).valueOrNull ?? const [];
    final saved =
        ref.watch(savedOrderLinesProvider(orderId)).valueOrNull ?? const [];
    final pending = pendingCancellations(order, saved);
    final scheme = Theme.of(context).colorScheme;
    final total = recorded.fold<double>(0, (s, r) => s + r.amount) +
        pending.fold<double>(0, (s, p) => s + p.amount);

    String qty(double q) =>
        q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(3);
    String time(DateTime t) {
      final l = t.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
    }

    Widget kitchenChip(bool sent) => sent
        ? Tooltip(
            message: l10n.translate('already_sent_to_kitchen'),
            child: Icon(Icons.soup_kitchen_outlined,
                size: 16, color: scheme.tertiary),
          )
        : const SizedBox.shrink();

    final tiles = <Widget>[
      for (final p in pending)
        ListTile(
          dense: true,
          leading: Icon(Icons.edit_note, color: scheme.secondary),
          title: Text('${qty(p.quantity)}× ${p.name}'),
          subtitle: Text(l10n.translate('cancelled_not_saved')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            kitchenChip(p.wasSentToKitchen),
            const SizedBox(width: 8),
            Text(money.format(p.amount)),
          ]),
        ),
      for (final r in recorded)
        ListTile(
          dense: true,
          leading: Icon(
            r.source == 'WAITER' ? Icons.person_pin : Icons.point_of_sale,
            color: scheme.error,
          ),
          title: Text('${qty(r.quantity)}× ${r.productName}'
              '${r.variantName == null ? '' : ' (${r.variantName})'}'),
          subtitle: Text([
            time(r.removedAt),
            if (r.removedByName != null && r.removedByName!.isNotEmpty)
              r.removedByName!,
            r.source == 'WAITER'
                ? l10n.translate('waiter')
                : l10n.translate('cashier'),
          ].join(' · ')),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            kitchenChip(r.wasSentToKitchen),
            const SizedBox(width: 8),
            Text(money.format(r.amount)),
          ]),
        ),
    ];

    return AlertDialog(
      title: Row(children: [
        Icon(Icons.remove_shopping_cart_outlined, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(l10n.translate('cancelled_items_title'))),
      ]),
      content: SizedBox(
        width: 460,
        child: tiles.isEmpty
            ? Text(l10n.translate('no_cancelled_items'))
            : ListView(shrinkWrap: true, children: tiles),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text(
            '${l10n.translate('total')}: ${money.format(total)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('close')),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }
}
