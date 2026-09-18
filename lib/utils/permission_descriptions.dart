import 'app_localizations.dart';

/// Human-readable title + one-line subtitle for a permission token.
///
/// Both fields are l10n keys resolved at render time via [AppLocalizations],
/// so admins see "Create order" / "Open a new sale and add items" instead of
/// the raw `pos:orders:create` token. Used by the cashier-defaults section in
/// settings and the user-details permission editor.
class PermissionDescription {
  final String titleKey;
  final String subtitleKey;
  const PermissionDescription({
    required this.titleKey,
    required this.subtitleKey,
  });
}

/// One entry per token in the `kPermissionGroups` catalog
/// (`users_management_screen.dart`). Keep these in sync — if you add a new
/// permission constant in `Permissions`, add it here and to `app_localizations`.
const Map<String, PermissionDescription> kPermissionDescriptions = {
  // ── Manual / Misc ──────────────────────────────────────────────────────
  'pos:manualDiscount': PermissionDescription(
    titleKey: 'perm_pos_manualDiscount_title',
    subtitleKey: 'perm_pos_manualDiscount_subtitle',
  ),
  'pos:printing': PermissionDescription(
    titleKey: 'perm_pos_printing_title',
    subtitleKey: 'perm_pos_printing_subtitle',
  ),

  // ── Orders ─────────────────────────────────────────────────────────────
  'pos:orders:create': PermissionDescription(
    titleKey: 'perm_pos_orders_create_title',
    subtitleKey: 'perm_pos_orders_create_subtitle',
  ),
  'pos:orders:view': PermissionDescription(
    titleKey: 'perm_pos_orders_view_title',
    subtitleKey: 'perm_pos_orders_view_subtitle',
  ),
  'pos:orders:update': PermissionDescription(
    titleKey: 'perm_pos_orders_update_title',
    subtitleKey: 'perm_pos_orders_update_subtitle',
  ),
  'pos:orders:delete': PermissionDescription(
    titleKey: 'perm_pos_orders_delete_title',
    subtitleKey: 'perm_pos_orders_delete_subtitle',
  ),
  'pos:orders:cancel': PermissionDescription(
    titleKey: 'perm_pos_orders_cancel_title',
    subtitleKey: 'perm_pos_orders_cancel_subtitle',
  ),
  'pos:orders:item:add': PermissionDescription(
    titleKey: 'perm_pos_orders_item_add_title',
    subtitleKey: 'perm_pos_orders_item_add_subtitle',
  ),
  'pos:orders:item:remove': PermissionDescription(
    titleKey: 'perm_pos_orders_item_remove_title',
    subtitleKey: 'perm_pos_orders_item_remove_subtitle',
  ),
  'pos:orders:item:modify': PermissionDescription(
    titleKey: 'perm_pos_orders_item_modify_title',
    subtitleKey: 'perm_pos_orders_item_modify_subtitle',
  ),

  // ── Tickets ────────────────────────────────────────────────────────────
  'pos:tickets:create': PermissionDescription(
    titleKey: 'perm_pos_tickets_create_title',
    subtitleKey: 'perm_pos_tickets_create_subtitle',
  ),
  'pos:tickets:view': PermissionDescription(
    titleKey: 'perm_pos_tickets_view_title',
    subtitleKey: 'perm_pos_tickets_view_subtitle',
  ),
  'pos:tickets:update': PermissionDescription(
    titleKey: 'perm_pos_tickets_update_title',
    subtitleKey: 'perm_pos_tickets_update_subtitle',
  ),
  'pos:tickets:print': PermissionDescription(
    titleKey: 'perm_pos_tickets_print_title',
    subtitleKey: 'perm_pos_tickets_print_subtitle',
  ),
  'pos:tickets:delete': PermissionDescription(
    titleKey: 'perm_pos_tickets_delete_title',
    subtitleKey: 'perm_pos_tickets_delete_subtitle',
  ),

  // ── Sessions ───────────────────────────────────────────────────────────
  'pos:sessions:start': PermissionDescription(
    titleKey: 'perm_pos_sessions_start_title',
    subtitleKey: 'perm_pos_sessions_start_subtitle',
  ),
  'pos:sessions:end': PermissionDescription(
    titleKey: 'perm_pos_sessions_end_title',
    subtitleKey: 'perm_pos_sessions_end_subtitle',
  ),
  'pos:sessions:pause': PermissionDescription(
    titleKey: 'perm_pos_sessions_pause_title',
    subtitleKey: 'perm_pos_sessions_pause_subtitle',
  ),
  'pos:sessions:view': PermissionDescription(
    titleKey: 'perm_pos_sessions_view_title',
    subtitleKey: 'perm_pos_sessions_view_subtitle',
  ),
  'pos:sessions:delete': PermissionDescription(
    titleKey: 'perm_pos_sessions_delete_title',
    subtitleKey: 'perm_pos_sessions_delete_subtitle',
  ),

  // ── Customers ──────────────────────────────────────────────────────────
  'pos:customer:set': PermissionDescription(
    titleKey: 'perm_pos_customer_set_title',
    subtitleKey: 'perm_pos_customer_set_subtitle',
  ),
  'pos:customer:create': PermissionDescription(
    titleKey: 'perm_pos_customer_create_title',
    subtitleKey: 'perm_pos_customer_create_subtitle',
  ),
  'pos:customer:view': PermissionDescription(
    titleKey: 'perm_pos_customer_view_title',
    subtitleKey: 'perm_pos_customer_view_subtitle',
  ),
  'pos:customer:delete': PermissionDescription(
    titleKey: 'perm_pos_customer_delete_title',
    subtitleKey: 'perm_pos_customer_delete_subtitle',
  ),

  // ── Commercials ────────────────────────────────────────────────────────
  'pos:commercial:set': PermissionDescription(
    titleKey: 'perm_pos_commercial_set_title',
    subtitleKey: 'perm_pos_commercial_set_subtitle',
  ),
  'pos:commercial:create': PermissionDescription(
    titleKey: 'perm_pos_commercial_create_title',
    subtitleKey: 'perm_pos_commercial_create_subtitle',
  ),
  'pos:commercial:view': PermissionDescription(
    titleKey: 'perm_pos_commercial_view_title',
    subtitleKey: 'perm_pos_commercial_view_subtitle',
  ),

  // ── Waiters ────────────────────────────────────────────────────────────
  'pos:waiter:set': PermissionDescription(
    titleKey: 'perm_pos_waiter_set_title',
    subtitleKey: 'perm_pos_waiter_set_subtitle',
  ),
  'pos:waiter:view': PermissionDescription(
    titleKey: 'perm_pos_waiter_view_title',
    subtitleKey: 'perm_pos_waiter_view_subtitle',
  ),
  'pos:waiter:create': PermissionDescription(
    titleKey: 'perm_pos_waiter_create_title',
    subtitleKey: 'perm_pos_waiter_create_subtitle',
  ),
  'pos:waiter:delete': PermissionDescription(
    titleKey: 'perm_pos_waiter_delete_title',
    subtitleKey: 'perm_pos_waiter_delete_subtitle',
  ),

  // ── Tables ─────────────────────────────────────────────────────────────
  'pos:tables:set': PermissionDescription(
    titleKey: 'perm_pos_tables_set_title',
    subtitleKey: 'perm_pos_tables_set_subtitle',
  ),
  'pos:tables:clear': PermissionDescription(
    titleKey: 'perm_pos_tables_clear_title',
    subtitleKey: 'perm_pos_tables_clear_subtitle',
  ),

  // ── Products ───────────────────────────────────────────────────────────
  'pos:products:view': PermissionDescription(
    titleKey: 'perm_pos_products_view_title',
    subtitleKey: 'perm_pos_products_view_subtitle',
  ),
  'pos:products:modify': PermissionDescription(
    titleKey: 'perm_pos_products_modify_title',
    subtitleKey: 'perm_pos_products_modify_subtitle',
  ),

  // ── Devices ────────────────────────────────────────────────────────────
  'pos:devices:use': PermissionDescription(
    titleKey: 'perm_pos_devices_use_title',
    subtitleKey: 'perm_pos_devices_use_subtitle',
  ),
  'pos:devices:view': PermissionDescription(
    titleKey: 'perm_pos_devices_view_title',
    subtitleKey: 'perm_pos_devices_view_subtitle',
  ),
  'pos:devices:update': PermissionDescription(
    titleKey: 'perm_pos_devices_update_title',
    subtitleKey: 'perm_pos_devices_update_subtitle',
  ),
  'pos:devices:delete': PermissionDescription(
    titleKey: 'perm_pos_devices_delete_title',
    subtitleKey: 'perm_pos_devices_delete_subtitle',
  ),

  // ── Users ──────────────────────────────────────────────────────────────
  'pos:users:view': PermissionDescription(
    titleKey: 'perm_pos_users_view_title',
    subtitleKey: 'perm_pos_users_view_subtitle',
  ),
  'pos:users:create': PermissionDescription(
    titleKey: 'perm_pos_users_create_title',
    subtitleKey: 'perm_pos_users_create_subtitle',
  ),
  'pos:users:update': PermissionDescription(
    titleKey: 'perm_pos_users_update_title',
    subtitleKey: 'perm_pos_users_update_subtitle',
  ),
  'pos:users:delete': PermissionDescription(
    titleKey: 'perm_pos_users_delete_title',
    subtitleKey: 'perm_pos_users_delete_subtitle',
  ),

  // ── Notes ──────────────────────────────────────────────────────────────
  'pos:notes:view': PermissionDescription(
    titleKey: 'perm_pos_notes_view_title',
    subtitleKey: 'perm_pos_notes_view_subtitle',
  ),
  'pos:notes:create': PermissionDescription(
    titleKey: 'perm_pos_notes_create_title',
    subtitleKey: 'perm_pos_notes_create_subtitle',
  ),
  'pos:notes:update': PermissionDescription(
    titleKey: 'perm_pos_notes_update_title',
    subtitleKey: 'perm_pos_notes_update_subtitle',
  ),
  'pos:notes:delete': PermissionDescription(
    titleKey: 'perm_pos_notes_delete_title',
    subtitleKey: 'perm_pos_notes_delete_subtitle',
  ),

  // ── Agenda ─────────────────────────────────────────────────────────────
  'pos:agenda:view': PermissionDescription(
    titleKey: 'perm_pos_agenda_view_title',
    subtitleKey: 'perm_pos_agenda_view_subtitle',
  ),
  'pos:agenda:manage': PermissionDescription(
    titleKey: 'perm_pos_agenda_manage_title',
    subtitleKey: 'perm_pos_agenda_manage_subtitle',
  ),

  // ── Logs ───────────────────────────────────────────────────────────────
  'pos:logs:view': PermissionDescription(
    titleKey: 'perm_pos_logs_view_title',
    subtitleKey: 'perm_pos_logs_view_subtitle',
  ),

  // ── Settings ───────────────────────────────────────────────────────────
  'pos:settings:view': PermissionDescription(
    titleKey: 'perm_pos_settings_view_title',
    subtitleKey: 'perm_pos_settings_view_subtitle',
  ),
  'pos:settings:update': PermissionDescription(
    titleKey: 'perm_pos_settings_update_title',
    subtitleKey: 'perm_pos_settings_update_subtitle',
  ),

  // ── Reports ────────────────────────────────────────────────────────────
  'pos:reports:view': PermissionDescription(
    titleKey: 'perm_pos_reports_view_title',
    subtitleKey: 'perm_pos_reports_view_subtitle',
  ),

  // ── Sync ───────────────────────────────────────────────────────────────
  'pos:sync:orders': PermissionDescription(
    titleKey: 'perm_pos_sync_orders_title',
    subtitleKey: 'perm_pos_sync_orders_subtitle',
  ),
  'pos:sync:tickets': PermissionDescription(
    titleKey: 'perm_pos_sync_tickets_title',
    subtitleKey: 'perm_pos_sync_tickets_subtitle',
  ),
  'pos:sync:sessions': PermissionDescription(
    titleKey: 'perm_pos_sync_sessions_title',
    subtitleKey: 'perm_pos_sync_sessions_subtitle',
  ),
  'pos:sync:customers': PermissionDescription(
    titleKey: 'perm_pos_sync_customers_title',
    subtitleKey: 'perm_pos_sync_customers_subtitle',
  ),
  'pos:sync:all': PermissionDescription(
    titleKey: 'perm_pos_sync_all_title',
    subtitleKey: 'perm_pos_sync_all_subtitle',
  ),
  'pos:sync:viewPending': PermissionDescription(
    titleKey: 'perm_pos_sync_viewPending_title',
    subtitleKey: 'perm_pos_sync_viewPending_subtitle',
  ),
  'pos:sync:managePending': PermissionDescription(
    titleKey: 'perm_pos_sync_managePending_title',
    subtitleKey: 'perm_pos_sync_managePending_subtitle',
  ),

  // ── Catalogue ──────────────────────────────────────────────────────────
  'pos:catalog': PermissionDescription(
    titleKey: 'perm_pos_catalog_title',
    subtitleKey: 'perm_pos_catalog_subtitle',
  ),

  // ── Price override ─────────────────────────────────────────────────────
  'pos:orders:item:price': PermissionDescription(
    titleKey: 'perm_pos_orders_item_price_title',
    subtitleKey: 'perm_pos_orders_item_price_subtitle',
  ),

  // ── Editing someone else's order ───────────────────────────────────────
  'pos:orders:waiter:update': PermissionDescription(
    titleKey: 'perm_pos_orders_waiter_update_title',
    subtitleKey: 'perm_pos_orders_waiter_update_subtitle',
  ),

  // ── Refunds ────────────────────────────────────────────────────────────
  'pos:refunds:view': PermissionDescription(
    titleKey: 'perm_pos_refunds_view_title',
    subtitleKey: 'perm_pos_refunds_view_subtitle',
  ),
  'pos:refunds:create': PermissionDescription(
    titleKey: 'perm_pos_refunds_create_title',
    subtitleKey: 'perm_pos_refunds_create_subtitle',
  ),
  'pos:refunds:waste': PermissionDescription(
    titleKey: 'perm_pos_refunds_waste_title',
    subtitleKey: 'perm_pos_refunds_waste_subtitle',
  ),
  'pos:refunds:amount:override': PermissionDescription(
    titleKey: 'perm_pos_refunds_amount_override_title',
    subtitleKey: 'perm_pos_refunds_amount_override_subtitle',
  ),

  // ── Z (shift) ──────────────────────────────────────────────────────────
  'pos:z:open': PermissionDescription(
    titleKey: 'perm_pos_z_open_title',
    subtitleKey: 'perm_pos_z_open_subtitle',
  ),
  'pos:z:close': PermissionDescription(
    titleKey: 'perm_pos_z_close_title',
    subtitleKey: 'perm_pos_z_close_subtitle',
  ),
  'pos:z:view': PermissionDescription(
    titleKey: 'perm_pos_z_view_title',
    subtitleKey: 'perm_pos_z_view_subtitle',
  ),
  'pos:z:print': PermissionDescription(
    titleKey: 'perm_pos_z_print_title',
    subtitleKey: 'perm_pos_z_print_subtitle',
  ),
};

/// Resolve display strings for a token at runtime. Falls back to the raw
/// token (with a blank subtitle) if no description exists — so unknown or
/// newly-introduced tokens still render rather than crash.
({String title, String subtitle}) describePermission(
  String token,
  AppLocalizations l10n,
) {
  final desc = kPermissionDescriptions[token];
  if (desc == null) {
    return (title: token, subtitle: '');
  }
  return (
    title: l10n.translate(desc.titleKey),
    subtitle: l10n.translate(desc.subtitleKey),
  );
}
