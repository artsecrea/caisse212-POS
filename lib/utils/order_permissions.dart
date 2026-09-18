import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/order_provider.dart';
import '../services/permission_service.dart';
import 'app_localizations.dart';
import 'snackbar_helper.dart';

/// The one place the "may this line go onto the current order?" rule lives.
///
/// It used to be copy-pasted inline at every till entry point, and the copies
/// drifted: two of them (creating a product from the empty grid, and creating
/// one from an unknown barcode) never had the check at all, which let a cashier
/// holding `pos:catalog` but not `pos:orders:item:add` append to a saved order
/// by going the long way round. Route every add through here instead of
/// re-deriving it.
///
/// Returns true when the caller may proceed with the add.
///
/// The denial uses [SnackBarHelper.error] rather than the settings-gated
/// `showErrorSnackBar`: a blocked tap that says nothing is indistinguishable
/// from a broken till, and `enableSnackBars` is off by default.
bool ensureCanAddItemToOrder(BuildContext context, WidgetRef ref) {
  if (canAddItemToCurrentOrder(ref)) return true;
  SnackBarHelper.error(
    context,
    AppLocalizations.of(context)!.translate('no_permission'),
  );
  return false;
}

/// The rule without the UI, for callers that need to decide something other
/// than "show a snackbar and stop" — see the quick-create flows, which still
/// save the new product and only skip putting it on the ticket.
///
/// A brand-new (unsaved) cart is unrestricted: nothing is persisted yet, so
/// there is no order to protect. The permission only bites once the order has
/// an id.
bool canAddItemToCurrentOrder(WidgetRef ref) {
  final orderId = ref.read(orderProvider).orderId;
  if (orderId == null) return true;
  if (!canEditWaiterOrder(ref)) return false;
  return ref
      .read(permissionServiceProvider)
      .hasPermission(Permissions.ordersItemAdd);
}

/// Whether [source] marks an order the WAITER APP raised.
///
/// Reads `Orders.source`, never `waiterId`: a cashier can attach a waiter to
/// an order they rang up themselves, so a non-null `waiterId` says nothing
/// about who created it. Case-insensitive because the column is free text
/// fed by both this app and the LAN server.
bool isWaiterRaisedOrder(String? source) =>
    source != null && source.toUpperCase() == 'WAITER';

/// Whether the current user may edit the order currently in the panel, given
/// who raised it.
///
/// A waiter order belongs to the waiter who rang it up — their table, their
/// covers, their attribution — so by default a cashier cannot alter it.
/// Passing needs either admin (which bypasses every permission) or the
/// explicit [Permissions.ordersWaiterUpdate] grant.
///
/// Anything the cashier raised themselves, and any unsaved cart, is
/// unaffected: this only ever narrows access to *someone else's* order.
bool canEditWaiterOrder(WidgetRef ref) {
  final order = ref.read(orderProvider);
  if (order.orderId == null) return true;
  if (!isWaiterRaisedOrder(order.source)) return true;
  return ref
      .read(permissionServiceProvider)
      .hasPermission(Permissions.ordersWaiterUpdate);
}

/// [canEditWaiterOrder] with the standard denial message, for callers that
/// just need to stop and say why.
bool ensureCanEditWaiterOrder(BuildContext context, WidgetRef ref) {
  if (canEditWaiterOrder(ref)) return true;
  SnackBarHelper.error(
    context,
    AppLocalizations.of(context)!.translate('waiter_order_locked'),
  );
  return false;
}
