import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/order_models.dart';
import '../../providers/settings_provider.dart';
import 'tip_dialog.dart';

/// Show the tip dialog unconditionally for [order]. Returns a copy of
/// [order] with the new tip stamped on it. Performs **no persistence**
/// — the caller decides whether and how to save:
///
///   - **Pre-save flows** (`_payDirectly`, `_showPaymentDialog`): show
///     this dialog *before* `saveOrder`, then pass the returned order
///     into `saveOrder` so the very first row write already carries the
///     tip. No double-write.
///   - **Already-saved-order flows** (orders management, order
///     confirmation): call `orderRepo.updateOrder(returnedOrder)` after
///     this dialog so the existing row is updated with the new tip.
///   - **Dedicated Tip button** on the toolbar: stamp the tip onto the
///     in-memory order via `OrderNotifier.setTip`. If the order is
///     already saved, also call `updateOrder` to persist; if not, the
///     cashier's next Proceed/Pay save will include the tip naturally.
///
/// This shape is what the cashier asked for: never save an order just to
/// then add the tip — the tip is on the order before any write.
///
/// Returns [order] unchanged when:
///   - order total is 0,
///   - cashier dismissed the dialog (null pop),
///   - cashier picked a negative value (guard — UI clamps to 0).
Future<CurrentOrder> runTipFlow(
  BuildContext context,
  WidgetRef ref,
  CurrentOrder order,
) async {
  if (order.total <= 0) return order;

  final tipAmount = await showDialog<double>(
    context: context,
    barrierDismissible: false,
    builder: (_) => TipDialog(
      orderTotal: order.total,
      initialTip: order.tip,
    ),
  );

  if (tipAmount == null) return order;
  if (tipAmount < 0) return order;
  return order.copyWith(tip: tipAmount);
}

/// Auto-prompt variant gated by `settings.showTipDialog`. Used at every
/// site that opens PaymentScreen (or the inline cash-pay path
/// `_payDirectly`) so the cashier gets asked exactly when the cashier has
/// opted in.
Future<CurrentOrder> applyTipIfEnabled(
  BuildContext context,
  WidgetRef ref,
  CurrentOrder order,
) async {
  final settings = ref.read(settingsProvider);
  if (!settings.showTipDialog) return order;
  return runTipFlow(context, ref, order);
}
