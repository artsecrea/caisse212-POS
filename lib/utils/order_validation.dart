import '../domain/models/app_settings.dart';
import '../domain/models/order_models.dart';

/// Which sub-dialog to open when the user taps "Fix now" on the violation
/// prompt. Each value maps to an existing entry-flow already in main_screen.
enum OrderRuleFix {
  setTable,
  setWaiter,
  setCustomer,
  setDeliveryAddress,
}

/// A single rule that the current order violates. The UI uses [errorKey] to
/// render the message and [fix] to decide which dialog to open next.
class OrderRuleViolation {
  final String errorKey;
  final OrderRuleFix fix;
  const OrderRuleViolation({required this.errorKey, required this.fix});
}

/// Validate [order] against the admin-configured rules in [settings].
///
/// Returns the first violated rule, or `null` when the order satisfies every
/// enabled rule. Pure function, no I/O — safe to call from any chokepoint
/// (Save / Proceed / Pay / split pay).
OrderRuleViolation? validateOrderRules(
  CurrentOrder order,
  AppSettings settings,
) {
  final isDineIn = order.type == 'DINE_IN';
  final isDelivery = order.type == 'DELIVERY';

  if (settings.requireTableForDineIn && isDineIn && order.tableId == null) {
    return const OrderRuleViolation(
      errorKey: 'error_table_required_for_dine_in',
      fix: OrderRuleFix.setTable,
    );
  }
  if (settings.requireWaiterForDineIn && isDineIn && order.waiterId == null) {
    return const OrderRuleViolation(
      errorKey: 'error_waiter_required_for_dine_in',
      fix: OrderRuleFix.setWaiter,
    );
  }
  if (settings.requireCustomerForDelivery &&
      isDelivery &&
      order.customerId == null) {
    return const OrderRuleViolation(
      errorKey: 'error_customer_required_for_delivery',
      fix: OrderRuleFix.setCustomer,
    );
  }
  if (settings.requireDeliveryAddress &&
      isDelivery &&
      (order.deliveryAddress == null ||
          order.deliveryAddress!.trim().isEmpty)) {
    return const OrderRuleViolation(
      errorKey: 'error_delivery_address_required',
      fix: OrderRuleFix.setDeliveryAddress,
    );
  }
  return null;
}
