import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../domain/models/exchange.dart';
import '../../domain/models/order_models.dart';
import '../../providers/database_providers.dart';
import '../../services/local_returns_service.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// The exchange under way, set by the refund dialog's Exchange button and
/// cleared once settled or cancelled. In memory only: nothing is written until
/// the exchange is settled, so an abandoned one leaves no trace.
final exchangeDraftProvider = StateProvider<ExchangeDraft?>((ref) => null);

/// Settle an exchange: the new order (already saved) is paid partly by the
/// credit of the goods brought back, and the difference is collected or given
/// back. Everything is written in ONE transaction — the refund, the EXCHANGE
/// credit ticket, the customer's ticket and the order's lines — so a crash can
/// never leave a refund without its new sale, or the reverse.
///
/// Returns true when settled.
Future<bool> showExchangeSettleDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CurrentOrder order,
  required ExchangeDraft draft,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final fmt = ref.read(currencyFormatterProvider);
  final policy = ref.read(refundPolicyProvider);
  final newTotal = order.total;
  final settlement = settleExchange(draft.credit, newTotal);

  // Customer pays: any till method. Given back: what the refund policy allows.
  var payMethod = TransactionType.fromString(
      ref.read(settingsProvider).defaultPaymentMethod);
  if (!TransactionType.pickable.contains(payMethod)) payMethod = TransactionType.cash;
  var backMethod = policy.allowedMethods.contains('CASH')
      ? 'CASH'
      : policy.allowedMethods.first;
  var busy = false;

  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final cs = Theme.of(ctx).colorScheme;
      String money(double v) => fmt.format(v);

      Widget line(String label, String value,
              {bool bold = false, Color? color}) =>
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontWeight: bold ? FontWeight.bold : null,
                        color: color)),
              ),
              Text(value,
                  style: TextStyle(
                      fontWeight: bold ? FontWeight.bold : null,
                      color: color)),
            ]),
          );

      Future<void> confirm() async {
        if (busy) return;
        setLocal(() => busy = true);
        final done = await _settle(
          context: ctx,
          ref: ref,
          order: order,
          draft: draft,
          settlement: settlement,
          payMethod: payMethod.value,
          backMethod: backMethod,
        );
        if (done && ctx.mounted) {
          Navigator.pop(ctx, true);
        } else {
          setLocal(() => busy = false);
        }
      }

      return AlertDialog(
        title: Row(children: [
          const Icon(Icons.swap_horiz),
          const SizedBox(width: 8),
          Text(l10n.translate('exchange')),
        ]),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${l10n.translate('exchange_returned')} · ${draft.order.code}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final r in draft.lines)
                  line('${_qty(r.quantity)} × ${r.name}', '-${money(r.amount)}'),
                line(l10n.translate('exchange_credit'), money(draft.credit),
                    bold: true),
                const Divider(height: 20),
                Text(l10n.translate('exchange_new_items'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                for (final i in order.items)
                  line('${_qty(i.quantity)} × ${i.displayName}',
                      money(i.totalPrice)),
                line(l10n.translate('total'), money(newTotal), bold: true),
                const Divider(height: 20),
                line(l10n.translate('exchange_credit'),
                    '-${money(settlement.creditUsed)}'),
                const SizedBox(height: 8),
                if (settlement.customerPays > 0.005) ...[
                  line(l10n.translate('exchange_customer_pays'),
                      money(settlement.customerPays),
                      bold: true, color: cs.primary),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    for (final m in TransactionType.pickable)
                      ChoiceChip(
                        label: Text(m.value),
                        selected: payMethod == m,
                        onSelected: busy
                            ? null
                            : (_) => setLocal(() => payMethod = m),
                      ),
                  ]),
                ] else if (settlement.paidBack > 0.005) ...[
                  line(l10n.translate('exchange_give_back'),
                      money(settlement.paidBack),
                      bold: true, color: cs.error),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    for (final m in policy.allowedMethods)
                      ChoiceChip(
                        label: Text(m),
                        selected: backMethod == m,
                        onSelected: busy
                            ? null
                            : (_) => setLocal(() => backMethod = m),
                      ),
                  ]),
                ] else
                  line(l10n.translate('exchange_even'), money(0), bold: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton.icon(
            onPressed: busy ? null : confirm,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(l10n.translate('exchange_confirm')),
          ),
        ],
      );
    }),
  );
  return ok ?? false;
}

String _qty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

Future<bool> _settle({
  required BuildContext context,
  required WidgetRef ref,
  required CurrentOrder order,
  required ExchangeDraft draft,
  required ExchangeSettlement settlement,
  required String payMethod,
  required String backMethod,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final returns = ref.read(returnsServiceProvider);
  final session = ref.read(currentSessionProvider);
  final user = ref.read(currentUserProvider);
  final orderId = order.orderId;
  if (session == null || orderId == null || order.orderCode == null) {
    SnackBarHelper.error(context, l10n.translate('refund_needs_open_session'));
    return false;
  }
  late Refund refund;
  late int lastTicketId;
  late String lastTicketNum;
  try {
    // Records both sides, completes the new order (status, table) exactly
    // as a payment does, and tells the admins.
    final result = await returns.settleExchange(
      draft: draft,
      newOrderId: orderId,
      newOrderCode: order.orderCode!,
      newTotal: order.total,
      payMethod: payMethod,
      backMethod: backMethod,
      sessionId: session.id,
      zDay: ref.read(currentZDayProvider),
      refundedBy: user?.id,
      cashierName: user?.effectiveDisplayName,
      posName: ref.read(apiServiceProvider).terminalTag(),
    );
    refund = result.refund;
    lastTicketId = result.lastTicketId;
    lastTicketNum = result.lastTicketNum;
  } catch (e) {
    Logger.instance.error('Exchange settle failed: $e');
    if (context.mounted) SnackBarHelper.failure(context, e);
    return false;
  }

  // One ticket for both sides of the swap. Detached, like a payment's.
  final prefs = ref.read(sharedPreferencesProvider);
  final differenceMethod = settlement.customerPays > 0.005
      ? payMethod
      : (settlement.paidBack > 0.005 ? backMethod : null);
  unawaited(() async {
    try {
      await ref.read(printingServiceProvider).printPaymentDocuments(
            ticketId: lastTicketId,
            ticketNumber: lastTicketNum,
            amount: order.total,
            paymentMethod: differenceMethod ?? TransactionType.exchange.value,
            createdAt: DateTime.now(),
            items: [
              for (final item in order.items)
                {
                  'name': item.displayName,
                  'quantity': item.quantity,
                  'price': item.totalPrice,
                  'components': item.components
                      .map((c) => {
                            'name': c.name,
                            'quantity': c.quantity,
                            'removalCharge': c.removalCharge,
                          })
                      .toList(),
                },
            ],
            orderType: order.type,
            hasTable: order.tableId != null,
            orderCode: order.orderCode,
            cashierName: user?.firstName,
            storeName: prefs.getString('business_name'),
            storeAddress: prefs.getString('business_address'),
            storePhone: prefs.getString('business_phone'),
            customerName: order.customerName,
            tableName: order.tableName,
            exchange: ExchangeReceipt(
              originalOrderCode: draft.order.code,
              refundCode: refund.code,
              returned: draft.lines,
              credit: draft.credit,
              settlement: settlement,
              differenceMethod: differenceMethod,
            ),
          );
    } catch (e) {
      Logger.instance.error('Exchange ticket failed to print: $e');
    }
  }());

  // New order first, then the refund that names it.
  unawaited(returns.publish(exchangeOrderId: orderId));
  return true;
}

/// The banner over the order panel while an exchange is under way.
class ExchangeBanner extends ConsumerWidget {
  const ExchangeBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(exchangeDraftProvider);
    if (draft == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);
    final newTotal = ref.watch(orderProvider).total;
    final st = settleExchange(draft.credit, newTotal);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.swap_horiz, color: cs.onTertiaryContainer),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${l10n.translate('exchange')} · ${draft.order.code}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.onTertiaryContainer),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(exchangeDraftProvider.notifier).state = null,
              child: Text(l10n.translate('exchange_cancel')),
            ),
          ]),
          for (final r in draft.lines)
            Text('↩ ${_qty(r.quantity)} × ${r.name}   -${fmt.format(r.amount)}',
                style: TextStyle(color: cs.onTertiaryContainer)),
          const SizedBox(height: 4),
          Text(
            '${l10n.translate('exchange_credit')}: ${fmt.format(draft.credit)}'
            '   ·   ${st.customerPays > 0.005 ? '${l10n.translate('exchange_customer_pays')}: ${fmt.format(st.customerPays)}' : '${l10n.translate('exchange_give_back')}: ${fmt.format(st.paidBack)}'}',
            style: TextStyle(
                fontWeight: FontWeight.w600, color: cs.onTertiaryContainer),
          ),
        ],
      ),
    );
  }
}
