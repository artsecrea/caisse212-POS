import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drift/drift.dart' show OrderingTerm;

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/refund_service.dart';
import 'package:loggecrea/loggecrea.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import './adaptive_text_field.dart';
import '../../services/pos_notifications.dart';

/// A refundable order line: the DB row plus the bits the dialog needs to show.
/// Trims the trailing `.0` so a whole quantity reads "2", not "2.0", while a
/// weighed line still shows its decimals.
String _fmtQty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

class _RefundableLine {
  final OrderProduct row;
  final String name;

  /// Per-unit price actually charged, components included. Matches the
  /// arithmetic used by the reports and by [RefundService].
  final double perUnit;

  /// Quantity still refundable (sold minus already refunded).
  final double remaining;

  /// Quantity already given back on earlier refunds — shown so the cashier can
  /// see this is a second (or third) refund against the same line.
  final double alreadyRefunded;

  /// The unit sold, when the line is serial-tracked.
  ///
  /// Shown in the picker so the cashier knows which physical unit is coming
  /// back. A serial line is exactly one unit, so refunding it is always "in
  /// full" — which is the condition under which the server frees the serial
  /// again (with `restock: true`; on waste it stays sold).
  final String? serialNumber;

  const _RefundableLine({
    required this.row,
    required this.name,
    required this.perUnit,
    required this.remaining,
    this.alreadyRefunded = 0,
    this.serialNumber,
  });

  bool get isSerial => serialNumber != null;

  int get id => row.id;
}

/// Refund some or all of a paid order.
///
/// The refund is written locally and pushed by `syncRefundsBulk` — it works
/// offline, like every other money movement in the POS. Each line can be
/// refunded back into stock or written off as waste, which is the one decision
/// the server cannot make for us.
Future<bool> showRefundDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Order order,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final fmt = ref.read(currencyFormatterProvider);
  final refundService = ref.read(refundServiceProvider);
  final db = ref.read(databaseProvider);

  // A refund line points at the SERVER id of an order line. An order that has
  // never synced has no server ids to point at, so the refund could be taken at
  // the counter and then be unsendable forever. Blocked here with a message
  // that says what to do, rather than inventing an id.
  if (!order.isSynced) {
    SnackBarHelper.error(context, l10n.translate('order_not_synced_refund'));
    return false;
  }

  // Quantities already given back, so a line can never be refunded twice.
  final alreadyRefunded =
      await refundService.refundedQuantitiesForOrder(order.id);

  // Work from the order_products rows, not the display DTO — a refund line
  // has to reference a real line id.
  final rows = await (db.select(db.orderProducts)
        ..where((op) => op.orderId.equals(order.id))
        ..orderBy([(op) => OrderingTerm.asc(op.id)]))
      .get();

  final opIds = rows.map((r) => r.id).toList();
  final comps = opIds.isEmpty
      ? <OrderProductComponent>[]
      : await (db.select(db.orderProductComponents)
            ..where((c) => c.orderProductId.isIn(opIds)))
          .get();
  final compCost = <int, double>{};
  for (final c in comps) {
    compCost[c.orderProductId] =
        (compCost[c.orderProductId] ?? 0) + c.price * c.quantity;
  }

  final productIds = rows.map((r) => r.productId).toSet().toList();
  final products = productIds.isEmpty
      ? <Product>[]
      : await (db.select(db.products)..where((p) => p.id.isIn(productIds)))
          .get();
  final nameById = {for (final p in products) p.id: p.name};

  // Serial numbers for any tracked line, so the slip and the picker name the
  // exact unit being returned.
  final serialIds = rows.map((r) => r.serialId).whereType<int>().toSet();
  final serialNumberById = <int?, String?>{};
  if (serialIds.isNotEmpty) {
    final serialRows = await (db.select(db.serials)
          ..where((t) => t.id.isIn(serialIds)))
        .get();
    for (final sr in serialRows) {
      serialNumberById[sr.id] = sr.serialNumber;
    }
  }

  final refundable = <_RefundableLine>[];
  for (final r in rows) {
    // A cancelled line was never sold, so there is nothing to give back.
    if (r.state == 'CANCELED') continue;
    final remaining = r.quantity - (alreadyRefunded[r.id] ?? 0);
    if (remaining <= 0.0001) continue;
    refundable.add(_RefundableLine(
      row: r,
      name: nameById[r.productId] ?? '#${r.productId}',
      perUnit: (r.unitaryPrice - r.manualDiscount) + (compCost[r.id] ?? 0),
      remaining: remaining,
      alreadyRefunded: alreadyRefunded[r.id] ?? 0,
      serialNumber: serialNumberById[r.serialId],
    ));
  }

  if (!context.mounted) return false;
  if (refundable.isEmpty) {
    SnackBarHelper.error(context, l10n.translate('nothing_left_to_refund'));
    return false;
  }

  // qty selected per order-product id; 0 = not refunding this line.
  final selected = <int, double>{for (final i in refundable) i.id: 0.0};
  // Restock defaults ON for every line, serial ones included: a serial refunded
  // in full with restock returns to stock and the unit becomes sellable again.
  // Switching it off is the "waste" case — the unit stays sold, which is what
  // you want for a broken or lost item.
  final restock = <int, bool>{for (final i in refundable) i.id: true};

  // Writing stock off is how a refund can quietly hide inventory, so it sits
  // behind its own token. Without it the toggle is forced ON and disabled —
  // never hidden, so the cashier can see the goods ARE going back and who to
  // ask if they should not.
  final canWaste = ref
      .read(permissionServiceProvider)
      .hasRefundPermission(Permissions.refundsWaste);

  // Typing an amount is the one field that can be abused — the doc's own
  // warning — so it stays derived and read-only unless the token is held.
  final canOverrideAmount = ref
      .read(permissionServiceProvider)
      .hasRefundPermission(Permissions.refundsAmountOverride);

  // Per-line typed amount. Null = take the derived figure, which is what the
  // server does too when `amount` is omitted.
  final overrideAmount = <int, double?>{for (final i in refundable) i.id: null};
  var method = 'CASH';
  final reasonCtrl = TextEditingController();
  var busy = false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final cs = Theme.of(ctx).colorScheme;

      // Honours a typed amount, so the big total on screen is the figure that
      // will actually be recorded and handed over — not the derived one it
      // replaced.
      final total = refundable.fold<double>(0, (s, i) {
        final qty = selected[i.id] ?? 0;
        if (qty <= 0) return s;
        return s + (overrideAmount[i.id] ?? i.perUnit * qty);
      });
      final anySelected =
          refundable.any((i) => (selected[i.id] ?? 0) > 0);

      Future<void> submit() async {
        if (busy || !anySelected) return;
        setLocal(() => busy = true);
        try {
          final user = ref.read(currentUserProvider);
          final session = ref.read(currentSessionProvider);
          final lines = <RefundLineDraft>[
            for (final i in refundable)
              if ((selected[i.id] ?? 0) > 0)
                RefundLineDraft(
                  orderProductId: i.id,
                  quantity: selected[i.id]!,
                  restock: restock[i.id] ?? true,
                  // Null unless typed — a derived amount is deliberately NOT
                  // sent, so the server derives its own (see the sync payload).
                  amount: overrideAmount[i.id],
                ),
          ];
          final created = await refundService.createRefund(
            order: order,
            method: method,
            lines: lines,
            reason: reasonCtrl.text.trim().isEmpty
                ? null
                : reasonCtrl.text.trim(),
            refundedBy: user?.id,
            sessionId: session?.id,
            zDay: ref.read(currentZDayProvider),
            // The terminal tag, not the raw name: a till with no name set
            // would otherwise drop that segment from the code entirely and
            // collide with every other unnamed till.
            posName: ref.read(apiServiceProvider).terminalTag(),
          );

          notifyRefund(
            ref.read,
            orderCode: created.orderCode,
            amount: created.totalAmount,
            method: created.method,
            reason: created.reason,
          );

          // Slip first, sync second. The customer is standing there and the
          // paper carries the refund code support will ask them for; a slow or
          // offline network must not delay it. Failures are swallowed for the
          // same reason the close-session prints are: the refund is already
          // recorded, and a dead printer must not undo it.
          try {
            final slip = await refundService.slipFor(created);
            await ref.read(printingServiceProvider).printRefundSlip(
                  data: slip,
                  // Same source the Z and session slips use.
                  businessName:
                      ref.read(sharedPreferencesProvider).getString('business_name'),
                );
          } catch (e) {
            Logger.instance.error('Refund slip failed to print: $e');
          }

          // Best-effort immediate push; the queue covers it when offline.
          try {
            await ref.read(dataSyncServiceProvider).syncRefundsBulk();
          } catch (_) {}

          if (ctx.mounted) Navigator.pop(ctx, true);
        } catch (e) {
          setLocal(() => busy = false);
          if (ctx.mounted) SnackBarHelper.failure(ctx, e);
        }
      }

      return AlertDialog(
        title: Row(children: [
          Icon(Icons.assignment_return, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l10n.translate('refund')} · ${order.code}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.translate('refund_pick_lines'),
                    style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 12),
                ...refundable.map((i) {
                  final max = i.remaining;
                  final qty = selected[i.id] ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: qty > 0
                          ? cs.errorContainer.withValues(alpha: 0.35)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(i.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                          ),
                          Text(fmt.format(i.perUnit * (qty == 0 ? max : qty))),
                        ]),
                        // The unit being handed back. Printed here because on a
                        // serial line the cashier must match the box in front of
                        // them to the line they are refunding — two identical
                        // phones on one order are different physical units.
                        if (i.serialNumber != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              Icon(Icons.qr_code_2,
                                  size: 13, color: cs.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  i.serialNumber!,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          ),
                        // Why this line offers less than was sold. Without it a
                        // partly-refunded line just looks wrong to the cashier.
                        if (i.alreadyRefunded > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              l10n
                                  .translate('already_refunded_n')
                                  .replaceAll('{0}', _fmtQty(i.alreadyRefunded))
                                  .replaceAll('{1}', _fmtQty(i.row.quantity)),
                              style: TextStyle(
                                  fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Text('${l10n.translate('quantity')}: '),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: busy || qty <= 0
                                ? null
                                : () => setLocal(() => selected[i.id] =
                                    (qty - 1).clamp(0, max).toDouble()),
                          ),
                          Text(qty == qty.roundToDouble()
                              ? qty.toStringAsFixed(0)
                              : qty.toStringAsFixed(2)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: busy || qty >= max
                                ? null
                                : () => setLocal(() => selected[i.id] =
                                    (qty + 1).clamp(0, max).toDouble()),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => setLocal(() => selected[i.id] = max),
                            child: Text(l10n.translate('all')),
                          ),
                          const Spacer(),
                          // Back to stock, or written off? The server posts a
                          // positive stock movement only when this is on.
                          Tooltip(
                            message: !canWaste
                                ? l10n.translate('no_permission_waste')
                                : i.isSerial
                                    ? l10n.translate('serial_restock_hint')
                                    : l10n.translate('restock_hint'),
                            child: Row(children: [
                              Text(l10n.translate('restock'),
                                  style: const TextStyle(fontSize: 12)),
                              Switch(
                                value: restock[i.id] ?? true,
                                onChanged: busy || qty <= 0 || !canWaste
                                    ? null
                                    : (v) => setLocal(() => restock[i.id] = v),
                              ),
                            ]),
                          ),
                        ]),
                        if (canOverrideAmount && qty > 0) ...[
                          const SizedBox(height: 6),
                          Row(children: [
                            Text('${l10n.translate('amount')}: ',
                                style: const TextStyle(fontSize: 12)),
                            SizedBox(
                              width: 110,
                              child: AdaptiveKeyboardTextField(
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                  isDense: true,
                                  // The derived figure as the hint, so leaving
                                  // it blank visibly means "use this".
                                  hintText:
                                      (i.perUnit * qty).toStringAsFixed(2),
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (v) {
                                  final parsed =
                                      double.tryParse(v.replaceAll(',', '.'));
                                  setLocal(() => overrideAmount[i.id] =
                                      (v.trim().isEmpty) ? null : parsed);
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Flagged visually, per the guide: an overridden
                            // amount should never look like a normal one.
                            if (overrideAmount[i.id] != null)
                              Icon(Icons.edit_note,
                                  size: 16, color: cs.error),
                          ]),
                        ],
                      ],
                    ),
                  );
                }),
                const Divider(height: 20),
                Row(children: [
                  Text('${l10n.translate('refund_method')}: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: method,
                    onChanged: busy
                        ? null
                        : (v) => setLocal(() => method = v ?? 'CASH'),
                    items: const ['CASH', 'CARD', 'TRANSFER', 'CHECK']
                        .map((m) =>
                            DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                  ),
                ]),
                const SizedBox(height: 8),
                AdaptiveKeyboardTextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('reason'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.translate('refund_total'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(fmt.format(total),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: busy || total <= 0 ? null : submit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.assignment_return),
            label: Text(l10n.translate('confirm_refund')),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
          ),
        ],
      );
    }),
  );

  reasonCtrl.dispose();
  return ok ?? false;
}
