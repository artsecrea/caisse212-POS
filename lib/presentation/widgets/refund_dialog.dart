import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../domain/models/exchange.dart';
import '../../domain/models/refund_policy.dart';
import '../../providers/catalogue_repository.dart';
import '../../providers/order_provider.dart'
    show orderProvider, orderRepositoryProvider;
import 'exchange_settle_dialog.dart' show exchangeDraftProvider;
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart'
    show lastKnownOnlineStatusProvider;
import '../../utils/admin_auth.dart';
import '../../services/refund_service.dart';
import '../../services/api_service.dart'
    show RefundLookupException, RefundLookupFailure;
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

String _fmtDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
  // Quantities refunded on other tills, per local line (from the server).
  // Callers go through [startRefund], which fetches them; refunds are online.
  Map<int, double> refundedElsewhere = const {},
}) async {
  final l10n = AppLocalizations.of(context)!;
  final fmt = ref.read(currencyFormatterProvider);
  final refundService = ref.read(refundServiceProvider);
  final orderRepo = ref.read(orderRepositoryProvider);
  final catalogue = ref.read(catalogueRepositoryProvider);
  final serials = ref.read(serialServiceProvider);

  // A refund line points at the SERVER id of an order line. An order that has
  // never synced has no server ids to point at, so the refund could be taken at
  // the counter and then be unsendable forever. Blocked here with a message
  // that says what to do, rather than inventing an id.
  if (!order.isSynced) {
    SnackBarHelper.error(context, l10n.translate('order_not_synced_refund'));
    return false;
  }

  // The policy set in BMS (or today's behaviour when there is none).
  final policy = ref.read(refundPolicyProvider);
  if (!policy.enabled) {
    SnackBarHelper.error(context, l10n.translate('refund_policy_disabled'));
    return false;
  }

  // The money comes out of a drawer, so it has to land in a session and a Z.
  // Without one the refund would belong to no Z at all and the drawer it was
  // paid from would never be asked to account for it.
  final session = ref.read(currentSessionProvider);
  if (session == null) {
    SnackBarHelper.error(context, l10n.translate('refund_needs_open_session'));
    return false;
  }

  final policyContext = await refundService.policyContextFor(
    order,
    currentZId: session.zId ?? ref.read(currentZProvider)?.id,
    currentZDay: ref.read(currentZDayProvider),
  );
  if (!context.mounted) return false;

  // Quantities already given back — here and on every other till — so a line
  // can never be refunded twice.
  final alreadyRefunded = <int, double>{
    ...await refundService.refundedQuantitiesForOrder(order.id),
  };
  refundedElsewhere.forEach((id, q) {
    alreadyRefunded[id] = (alreadyRefunded[id] ?? 0) + q;
  });

  // Work from the order_products rows, not the display DTO — a refund line
  // has to reference a real line id.
  final rows = await orderRepo.linesOfOrder(order.id);

  final comps = await orderRepo.componentsOfLines(rows.map((r) => r.id));
  final compCost = <int, double>{};
  for (final c in comps) {
    compCost[c.orderProductId] =
        (compCost[c.orderProductId] ?? 0) + c.price * c.quantity;
  }

  final products =
      await catalogue.productsByIds(rows.map((r) => r.productId).toSet());
  final nameById = {for (final p in products) p.id: p.name};

  // Serial numbers for any tracked line, so the slip and the picker name the
  // exact unit being returned.
  final serialNumberById = await serials
      .serialNumbersByIds(rows.map((r) => r.serialId).whereType<int>().toSet());

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
  //
  // The starting position comes from the policy (a restaurant may want
  // "not returned" by default: served food does not go back on a shelf).
  final restock = <int, bool>{
    for (final i in refundable) i.id: policy.defaultRestock
  };

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
  // Default method: the way the order was paid, when the policy wants them to
  // match; otherwise cash; always one the policy allows.
  String pickDefaultMethod() {
    if (policy.methodMustMatchPayment) {
      for (final m in policy.allowedMethods) {
        if (policyContext.paidMethods.contains(m)) return m;
      }
    }
    return policy.allowedMethods.contains('CASH')
        ? 'CASH'
        : policy.allowedMethods.first;
  }

  var method = pickDefaultMethod();
  final reasonCtrl = TextEditingController();
  // Preset reason from the policy, when it defines any.
  RefundReason? presetReason;
  var busy = false;

  final permissions = ref.read(permissionServiceProvider);
  // Strict, unlike the four original refund tokens: the policy is a business
  // rule set on purpose, and the lenient "no refund token at all = allow"
  // rollout rule would let a pre-V148 role walk past every limit. Nobody is
  // stuck: a supervisor can always approve at the till.
  bool holds(String permission) => permissions.hasPermission(permission);

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

      final isFullRefund = refundable.every(
          (i) => (selected[i.id] ?? 0) >= i.remaining - 0.0001);
      final includesNonRefundable = refundable.any((i) =>
          (selected[i.id] ?? 0) > 0 &&
          policyContext.nonRefundableLineIds.contains(i.id));
      final issues = anySelected
          ? refundPolicyIssues(
              policy,
              RefundAttempt(
                saleZDay: policyContext.saleZDay,
                currentZDay: ref.read(currentZDayProvider),
                saleZClosed: policyContext.saleZClosed,
                total: total,
                method: method,
                paidMethods: policyContext.paidMethods,
                includesNonRefundable: includesNonRefundable,
                isFullRefund: isFullRefund,
              ))
          : const <RefundPolicyIssue>[];
      final needsApproval = unapprovedIssues(issues, holds);
      final exchangeIssues = [
        for (final i in issues)
          if (i.flag != RefundPolicyFlag.method) i
      ];
      final exchangeNeedsApproval = unapprovedIssues(exchangeIssues, holds);

      // The text that is stored and printed: the preset's label, plus the
      // typed detail when the preset is "Other" or there are no presets.
      String? reasonText() {
        final typed = reasonCtrl.text.trim();
        final preset = presetReason;
        if (preset == null) return typed.isEmpty ? null : typed;
        if (preset.isOther && typed.isNotEmpty) return '${preset.label}: $typed';
        return preset.label;
      }

      final reasonMissing = policy.requireReason &&
          (reasonText() == null ||
              (presetReason?.isOther == true && reasonCtrl.text.trim().isEmpty));

      Future<void> submit({int? approvedBy}) async {
        if (busy || !anySelected || reasonMissing) return;
        setLocal(() => busy = true);
        try {
          final user = ref.read(currentUserProvider);
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
            reason: reasonText(),
            reasonCode: presetReason?.code,
            approvedBy: approvedBy,
            // Every limit this refund went past, approved or covered by the
            // cashier's own token alike: the back office audits both.
            policyFlags: [for (final i in issues) i.flag],
            earlierSale: policyContext.saleZClosed,
            refundedElsewhere: refundedElsewhere,
            refundedBy: user?.id,
            sessionId: session.id,
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

      Future<void> approveAndSubmit() async {
        if (busy || !anySelected || reasonMissing) return;
        final approval = await showAdminCredentialDialog(
          ctx,
          ref,
          title: l10n.translate('refund_approval_title'),
          description: l10n.translate('refund_approval_body'),
          confirmLabel: l10n.translate('refund_approve'),
          permissions: permissionsNeeded(needsApproval),
        );
        if (approval == null) return;
        await submit(approvedBy: approval.adminId);
      }

      // Exchange: the goods come back, but the money is spent on new goods
      // rung up on the main screen. Nothing is written here — the refund is
      // created when the new order is settled, so an abandoned exchange
      // leaves no trace.
      Future<void> startExchange() async {
        if (busy || !anySelected || reasonMissing) return;
        if (ref.read(orderProvider).items.isNotEmpty) {
          SnackBarHelper.error(ctx, l10n.translate('exchange_cart_not_empty'));
          return;
        }
        int? approvedBy;
        if (exchangeNeedsApproval.isNotEmpty) {
          final approval = await showAdminCredentialDialog(
            ctx,
            ref,
            title: l10n.translate('refund_approval_title'),
            description: l10n.translate('refund_approval_body'),
            confirmLabel: l10n.translate('refund_approve'),
            permissions: permissionsNeeded(exchangeNeedsApproval),
          );
          if (approval == null) return;
          approvedBy = approval.adminId;
        }
        ref.read(exchangeDraftProvider.notifier).state = ExchangeDraft(
          order: order,
          lines: [
            for (final i in refundable)
              if ((selected[i.id] ?? 0) > 0)
                ExchangeReturnLine(
                  orderProductId: i.id,
                  name: i.name,
                  quantity: selected[i.id]!,
                  amount: double.parse((overrideAmount[i.id] ??
                          i.perUnit * selected[i.id]!)
                      .toStringAsFixed(2)),
                  restock: restock[i.id] ?? true,
                  amountOverridden: overrideAmount[i.id] != null,
                ),
          ],
          reason: reasonText(),
          reasonCode: presetReason?.code,
          approvedBy: approvedBy,
          policyFlags: [for (final i in exchangeIssues) i.flag],
          earlierSale: policyContext.saleZClosed,
          refundedElsewhere: refundedElsewhere,
        );
        if (ctx.mounted) Navigator.pop(ctx, false);
      }

      String issueLabel(RefundPolicyIssue issue) {
        switch (issue.flag) {
          case RefundPolicyFlag.closedZ:
            return l10n.translate('refund_issue_closed_z');
          case RefundPolicyFlag.window:
            final days = policyContext.saleZDay == null
                ? 0
                : businessDaysBetween(
                    policyContext.saleZDay!, ref.read(currentZDayProvider));
            return l10n
                .translate('refund_issue_window')
                .replaceAll('{days}', '$days')
                .replaceAll('{limit}', '${policy.windowDays ?? 0}');
          case RefundPolicyFlag.amount:
            return l10n
                .translate('refund_issue_amount')
                .replaceAll('{limit}', fmt.format(policy.approvalAbove ?? 0));
          case RefundPolicyFlag.method:
            return l10n.translate('refund_issue_method');
          case RefundPolicyFlag.nonRefundable:
            return l10n.translate('refund_issue_non_refundable');
          case RefundPolicyFlag.partial:
            return l10n.translate('refund_issue_partial');
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
                // Sold in an earlier Z: say where the money will be booked, so
                // nobody expects the closed Z to change.
                if (policyContext.saleZClosed) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.history,
                          size: 18, color: cs.onSecondaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translate('refund_earlier_z').replaceAll(
                              '{day}',
                              policyContext.saleZDay == null
                                  ? '?'
                                  : _fmtDay(policyContext.saleZDay!)),
                          style: TextStyle(color: cs.onSecondaryContainer),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
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
                          if (policyContext.nonRefundableLineIds
                              .contains(i.id)) ...[
                            Icon(Icons.block, size: 14, color: cs.error),
                            const SizedBox(width: 3),
                            Text(l10n.translate('refund_non_refundable_tag'),
                                style:
                                    TextStyle(fontSize: 11, color: cs.error)),
                            const SizedBox(width: 8),
                          ],
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
                                // Putting goods BACK is never the abuse case,
                                // so it is always allowed; taking them out of
                                // stock needs the waste token.
                                onChanged: busy ||
                                        qty <= 0 ||
                                        (!canWaste && (restock[i.id] ?? true))
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
                    // All four are offered; one the policy does not allow is
                    // marked and simply lands in the approval list.
                    items: kRefundMethods
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(m),
                                  if (!policy.allowedMethods.contains(m)) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.lock_outline, size: 14),
                                  ],
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(width: 12),
                  if (policyContext.paidMethods.isNotEmpty)
                    Expanded(
                      child: Text(
                        l10n.translate('refund_paid_with').replaceAll(
                            '{methods}', policyContext.paidMethods.join(', ')),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                if (policy.reasons.isNotEmpty) ...[
                  DropdownButtonFormField<RefundReason>(
                    initialValue: presetReason,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText: l10n.translate('reason') +
                          (policy.requireReason ? ' *' : ''),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final r in policy.reasons)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged:
                        busy ? null : (r) => setLocal(() => presetReason = r),
                  ),
                  const SizedBox(height: 8),
                ],
                // Free text: always when there are no presets, otherwise only
                // as the detail of "Other".
                if (policy.reasons.isEmpty || presetReason?.isOther == true)
                  AdaptiveKeyboardTextField(
                    controller: reasonCtrl,
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: policy.reasons.isEmpty
                          ? l10n.translate('reason') +
                              (policy.requireReason ? ' *' : '')
                          : l10n.translate('refund_reason_detail'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                // Policy limits this refund goes past: the cashier sees each
                // one, and whether their own permission covers it.
                if (issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: needsApproval.isEmpty
                          ? cs.surfaceContainerHighest.withValues(alpha: 0.5)
                          : cs.tertiaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          needsApproval.isEmpty
                              ? l10n.translate('refund_policy_covered')
                              : l10n.translate('refund_needs_approval'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        for (final issue in issues)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(children: [
                              Icon(
                                needsApproval.contains(issue)
                                    ? Icons.lock_outline
                                    : Icons.check_circle_outline,
                                size: 16,
                                color: needsApproval.contains(issue)
                                    ? cs.onTertiaryContainer
                                    : cs.primary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(issueLabel(issue))),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ],
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
          OutlinedButton.icon(
            onPressed: busy || total <= 0 || reasonMissing ? null : startExchange,
            icon: const Icon(Icons.swap_horiz),
            label: Text(l10n.translate('exchange')),
          ),
          ElevatedButton.icon(
            onPressed: busy || total <= 0 || reasonMissing
                ? null
                : needsApproval.isEmpty
                    ? () => submit()
                    : approveAndSubmit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(needsApproval.isEmpty
                    ? Icons.assignment_return
                    : Icons.supervisor_account),
            label: Text(needsApproval.isEmpty
                ? l10n.translate('confirm_refund')
                : l10n.translate('refund_request_approval')),
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

/// Refund an order by its code — the one entry point for every refund.
///
/// Refunds are ONLINE-ONLY. The order and every refund already given on it
/// (on any till) are read fresh from the server, because the server is the
/// only place that knows what another till did: a refund checked against this
/// till's copy alone could give the same goods back twice. If the server cannot
/// be reached the refund waits — it is refused with a message, never taken on
/// a guess.
///
/// The refund RECORD is still written locally and pushed by the usual sync, so
/// it lands in this session's Z even if the push itself is delayed.
Future<bool> startRefund({
  required BuildContext context,
  required WidgetRef ref,
  required String orderCode,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final code = orderCode.trim();
  if (code.isEmpty) return false;

  // Cheap refusals first, before any network call.
  if (!ref.read(refundPolicyProvider).enabled) {
    SnackBarHelper.error(context, l10n.translate('refund_policy_disabled'));
    return false;
  }
  if (ref.read(currentSessionProvider) == null) {
    SnackBarHelper.error(context, l10n.translate('refund_needs_open_session'));
    return false;
  }

  final api = ref.read(apiServiceProvider);
  final sync = ref.read(dataSyncServiceProvider);
  final refunds = ref.read(refundServiceProvider);
  final orderRepo = ref.read(orderRepositoryProvider);

  Future<Order?> localOrder() => orderRepo.findOrderRowByCode(code);

  // A modal spinner: the lookup is two round-trips and the cashier must not
  // start a second refund meanwhile.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 20),
        Expanded(child: Text(l10n.translate('refund_checking_online'))),
      ]),
    ),
  );
  void closeSpinner() {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  Order? order;
  Map<int, double> elsewhere = const {};
  try {
    // An order of this till not on the server yet has nothing to check
    // against: push it first.
    final before = await localOrder();
    if (before != null && !before.isSynced) {
      await sync.syncSingleOrder(before.id);
    }

    final item = await api.fetchOrderForRefund(code);
    final serverRefunds = await api.fetchRefundsForRefund(code);

    // Take the server's copy (lines, payments, cancellations). Skipped by
    // applyServerOrder only when this till still has an edit to push, in
    // which case the local row is the newer one anyway.
    await sync.applyServerOrder(item);
    order = await localOrder();
    if (order != null) {
      elsewhere = otherTillsRefunded(
        serverRefunds: serverRefunds,
        localCodes: await refunds.localRefundCodes(order.id),
        localIdByServerId: await refunds.localIdsByServerId(order.id),
      );
    }
  } on RefundLookupException catch (e) {
    closeSpinner();
    if (context.mounted) {
      SnackBarHelper.error(
          context,
          l10n.translate(e.failure == RefundLookupFailure.notFound
              ? 'refund_receipt_not_found'
              : 'action_needs_network'));
    }
    return false;
  } catch (e) {
    closeSpinner();
    Logger.instance.error('Refund lookup of $code failed: $e');
    if (context.mounted) {
      SnackBarHelper.error(context, l10n.translate('action_needs_network'));
    }
    return false;
  }
  closeSpinner();

  if (!context.mounted) return false;
  if (order == null) {
    SnackBarHelper.error(context, l10n.translate('refund_receipt_not_found'));
    return false;
  }
  if (order.status == 'CANCELED') {
    SnackBarHelper.error(context, l10n.translate('nothing_left_to_refund'));
    return false;
  }
  final done = await showRefundDialog(
    context: context,
    ref: ref,
    order: order,
    refundedElsewhere: elsewhere,
  );
  if (done && context.mounted) {
    SnackBarHelper.success(context, l10n.translate('refund_recorded'));
  }
  if (!done && ref.read(exchangeDraftProvider) != null && context.mounted) {
    // Back to the till: the new goods are rung up in the cart, under the
    // exchange banner, and Pay settles both sides.
    Navigator.of(context)
        .popUntil((r) => r.settings.name == '/main' || r.isFirst);
    SnackBarHelper.showToast(l10n.translate('exchange_started'),
        kind: ToastKind.info);
  }
  return done;
}

/// "Refund": type or scan the order code off the receipt, then [startRefund].
Future<bool> showRefundReceiptDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final codeCtrl = TextEditingController();

  final code = await showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final c = codeCtrl.text.trim();
        if (c.isNotEmpty) Navigator.pop(ctx, c);
      }

      return Consumer(builder: (ctx, ref, _) {
        final online = ref.watch(lastKnownOnlineStatusProvider);
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.assignment_return),
            const SizedBox(width: 8),
            Text(l10n.translate('refund_receipt')),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdaptiveKeyboardTextField(
                  controller: codeCtrl,
                  autofocus: true,
                  enabled: online,
                  onSubmitted: (_) => online ? submit() : null,
                  decoration: InputDecoration(
                    labelText: l10n.translate('refund_receipt_hint'),
                    prefixIcon: const Icon(Icons.qr_code_scanner),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (!online) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.wifi_off, size: 18, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.translate('action_needs_network'),
                          style: TextStyle(color: cs.error)),
                    ),
                  ]),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('cancel')),
            ),
            FilledButton.icon(
              onPressed: online ? submit : null,
              icon: const Icon(Icons.search),
              label: Text(l10n.translate('refund_receipt_find')),
            ),
          ],
        );
      });
    },
  );
  codeCtrl.dispose();
  if (code == null || !context.mounted) return false;
  return startRefund(context: context, ref: ref, orderCode: code);
}
