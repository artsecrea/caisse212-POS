import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/order_models.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../services/local_payment_service.dart';
import '../../services/ticket_settlement_service.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// Settle every unpaid order attributed to a single waiter in one shot.
///
/// Workflow:
///   1. Loads the waiter's unpaid orders via
///      [OrderRepository.getPaginatedOrdersWithFullDetails].
///   2. Shows them as a checklist with a live grand total.
///   3. On "Pay all (cash)" — for each selected order the same primitives
///      the cashier payment screen uses run in a loop: insert a CASH ticket
///      covering the order's remaining due, mark every line PAID, mark the
///      order as paid (`paidOrderDefaultStatus` from Settings), then push
///      to sync if online. One slip is printed via
///      [PrintingService.printWaiterSettlementSlip].
///
/// Notes:
///   - No new schema entity. Each settled order ends up indistinguishable
///     from "the cashier rang up an order and the waiter paid cash" — the
///     normal sync pipeline carries them up without changes.
///   - Print failure does NOT roll back the settlement; the cashier can
///     reprint from the daily summary or order details later.
class WaiterSettlementDialog extends ConsumerStatefulWidget {
  final int waiterId;
  final String waiterName;
  /// When provided, the loaded set is narrowed to JUST these order ids —
  /// used when the cashier already picked a subset on the upstream surface
  /// (e.g. checkboxes in [WaiterProfileDialog]'s Unpaid tab). null = show
  /// every unpaid order for this waiter (existing "settle all" behavior).
  final Set<int>? restrictedOrderIds;
  const WaiterSettlementDialog({
    super.key,
    required this.waiterId,
    required this.waiterName,
    this.restrictedOrderIds,
  });

  @override
  ConsumerState<WaiterSettlementDialog> createState() =>
      _WaiterSettlementDialogState();
}

class _WaiterSettlementDialogState
    extends ConsumerState<WaiterSettlementDialog> {
  List<OrderFullDetails> _orders = const [];
  final Set<int> _selectedIds = {};
  bool _isLoading = true;
  bool _isWorking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(orderQueriesProvider);
      // pageSize is high enough that a single waiter shift won't paginate
      // in practice. If you ever see a waiter rack up >200 unpaid orders
      // the workflow itself is broken before pagination is.
      final result = await repo.getPaginatedOrdersWithFullDetails(
        page: 0,
        pageSize: 200,
        waiterId: widget.waiterId,
        unpaidOnly: true,
      );
      // When the caller narrowed the scope via `restrictedOrderIds`, drop
      // anything else. Empty restriction set = nothing shown; null = show
      // every unpaid order.
      final restricted = widget.restrictedOrderIds;
      final scoped = restricted == null
          ? result.orders
          : result.orders
              .where((o) => restricted.contains(o.order.id))
              .toList();
      if (!mounted) return;
      setState(() {
        _orders = scoped;
        _selectedIds
          ..clear()
          ..addAll(_orders.map((o) => o.order.id));
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorText(e, AppLocalizations.of(context)!);
        _isLoading = false;
      });
    }
  }

  double _due(OrderFullDetails o) {
    final remaining = o.total - o.totalPaid;
    return remaining < 0 ? 0 : remaining;
  }

  double _grandTotal() {
    var sum = 0.0;
    for (final o in _orders) {
      if (_selectedIds.contains(o.order.id)) sum += _due(o);
    }
    return sum;
  }

  Future<void> _printSlip() async {
    final cashier = ref.read(currentUserProvider);
    final printingService = ref.read(printingServiceProvider);
    final selected = _orders
        .where((o) => _selectedIds.contains(o.order.id))
        .toList();
    final ok = await printingService.printWaiterSettlementSlip(
      waiterName: widget.waiterName,
      cashierName: cashier?.firstName,
      orders: selected
          .map((o) => (
                code: o.order.code,
                due: _due(o),
                tableName: o.tableName,
              ))
          .toList(),
      grandTotal: _grandTotal(),
    );
    if (!mounted) return;
    if (ok) {
      SnackBarHelper.success(context, AppLocalizations.of(context)!
          .translate('printed_successfully'));
    } else {
      SnackBarHelper.error(context, AppLocalizations.of(context)!
          .translate('print_error'));
    }
  }

  Future<void> _payAllCash() async {
    if (_isWorking) return;
    final selected = _orders
        .where((o) => _selectedIds.contains(o.order.id))
        .toList();
    if (selected.isEmpty) return;

    setState(() => _isWorking = true);
    final payments = ref.read(paymentServiceProvider);
    final printingService = ref.read(printingServiceProvider);
    final cashier = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name');
    final businessAddress = prefs.getString('business_address');
    final businessPhone = prefs.getString('business_phone');

    final fmt = ref.read(currencyFormatterProvider);
    final settledTotal = _grandTotal();
    final settledCount = selected.length;

    try {
      for (final o in selected) {
        final orderId = o.order.id;
        final due = _due(o);
        if (due <= 0) continue;

        // The waiter keeps `servedBy`; the till that took the cash takes
        // `takenBy`, so the money lands in this cashier's session. Every
        // line is paid by now, so the order completes and frees its table
        // exactly as a cashier-paid one does.
        final paid = await payments.pay(
          orderId,
          paymentMethod: 'CASH',
          amount: due,
          lines: UnpaidLinesOf(orderId),
        );
        final ticketId = paid.ticketId;
        final ticketNumStr = paid.ticketNum;
        await payments.completeIfSettled(orderId);

        // Per-order payment receipt — same call shape the cashier payment
        // screen uses (payment_screen.dart:1569). This is what the user
        // expects: a real receipt per order, not the settlement summary
        // slip (which stays available behind the "Print slip" button).
        // Print failure is logged + swallowed; payment is already
        // committed and `tickets.print_count` lets the cashier reprint
        // from order details later.
        try {
          final itemsForPrint = o.items.map((item) {
            return {
              'name': item.displayName,
              'quantity': item.quantity,
              'price': item.totalPrice,
              'components': item.components
                  .map((c) => {'name': c.name, 'quantity': c.quantity})
                  .toList(),
            };
          }).toList();

          await printingService.printPaymentDocuments(
            ticketId: ticketId,
            ticketNumber: ticketNumStr,
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
            // source: 'POS' (the default) — the cashier is settling on
            // behalf of the waiter through the cashier UI. The waiter
            // source rule applies to *creation*, not to post-settlement
            // receipts.
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
          await ref.read(paymentServiceProvider).recordPrint(ticketId);
        } catch (e) {
          // Non-fatal — payment is committed; cashier can reprint.
          // ignore: avoid_print
          print('Waiter settlement receipt print failed: $e');
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      SnackBarHelper.success(
        context,
        AppLocalizations.of(context)!
            .translate('settle_done')
            .replaceAll('{0}', settledCount.toString())
            .replaceAll('{1}', fmt.format(settledTotal)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isWorking = false);
      SnackBarHelper.error(
        context,
        AppLocalizations.of(context)!
            .translate('settle_failed')
            .replaceAll('{0}', e.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = ref.read(currencyFormatterProvider);
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.point_of_sale, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.translate('settle_waiter_title')
                  .replaceAll('{0}', widget.waiterName),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: _buildBody(l10n, fmt, cs),
      ),
      actions: [
        TextButton(
          onPressed:
              _isWorking ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.translate('cancel')),
        ),
        OutlinedButton.icon(
          onPressed: (_isWorking || _selectedIds.isEmpty) ? null : _printSlip,
          icon: const Icon(Icons.print_outlined),
          label: Text(l10n.translate('settle_print_slip')),
        ),
        ElevatedButton.icon(
          onPressed:
              (_isWorking || _selectedIds.isEmpty) ? null : _payAllCash,
          icon: _isWorking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.payments),
          label: Text(l10n.translate('settle_pay_all_cash')),
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AppLocalizations l10n, CurrencyFormatter fmt,
      ColorScheme cs) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(_error!, style: TextStyle(color: cs.error)),
      );
    }
    if (_orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          l10n.translate('settle_no_unpaid'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _orders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final o = _orders[i];
              final id = o.order.id;
              final checked = _selectedIds.contains(id);
              final due = _due(o);
              return CheckboxListTile(
                dense: true,
                value: checked,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds.add(id);
                    } else {
                      _selectedIds.remove(id);
                    }
                  });
                },
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.order.code,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(fmt.format(due),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                subtitle: Text(
                  [
                    o.order.type,
                    if (o.tableName != null) o.tableName!,
                    if (o.customerName != null) o.customerName!,
                  ].join(' • '),
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            children: [
              Text(
                l10n.translate('total_due'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                fmt.format(_grandTotal()),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
