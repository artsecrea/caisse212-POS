import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/database_providers.dart';
import '../widgets/users_management_screen.dart' show kPermissionGroups;
import '../../domain/models/app_settings.dart';
import '../../utils/app_localizations.dart';
import '../../utils/responsive_utils.dart';
import '../../services/discovery_service.dart';
import '../../domain/models/scale_config.dart';
import '../../providers/scale_config_provider.dart';
import '../../providers/order_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedNavIndex = 0;

  List<NavItem> _getNavItems(AppLocalizations l10n, {required bool isAdmin}) => [
    NavItem(icon: Icons.palette, label: l10n.translate('appearance')),
    NavItem(icon: Icons.display_settings, label: l10n.translate('display')),
    NavItem(icon: Icons.shopping_cart, label: l10n.translate('order_defaults')),
    NavItem(icon: Icons.attach_money, label: l10n.translate('currency')),
    NavItem(icon: Icons.touch_app, label: l10n.translate('action_buttons')),
    NavItem(icon: Icons.sync, label: l10n.translate('sync_settings')),
    NavItem(icon: Icons.dns, label: l10n.translate('server_settings')),
    NavItem(icon: Icons.scale, label: l10n.translate('scale_config')),
    if (isAdmin)
      NavItem(icon: Icons.badge, label: l10n.translate('cashier_role_defaults')),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.watch(currentUserProvider);
    final isAdmin = currentUser?.type.toLowerCase() == 'admin';
    final navItems = _getNavItems(l10n, isAdmin: isAdmin);
    // Clamp selection in case the admin-only tab disappears (e.g. on logout).
    if (_selectedNavIndex >= navItems.length) {
      _selectedNavIndex = 0;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: dialogWidth(context, 1000),
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (non-scrollable)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  const Icon(Icons.settings, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    l10n.translate('settings'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(),
            ),
            // Main content with navigation
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Navigation
                  Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            itemCount: navItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                            itemBuilder: (context, index) {
                              final isSelected = _selectedNavIndex == index;
                              return _buildNavItem(
                                icon: navItems[index].icon,
                                label: navItems[index].label,
                                isSelected: isSelected,
                                onTap: () => setState(() => _selectedNavIndex = index),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  // Right Content
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: _buildContentForIndex(
                        index: _selectedNavIndex,
                        settings: settings,
                        settingsNotifier: settingsNotifier,
                        context: context,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Reset Button at bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.translate('reset_settings')),
                          content: Text(l10n.translate('reset_settings_confirm')),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(l10n.translate('cancel')),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(l10n.translate('reset_to_defaults')),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await settingsNotifier.resetToDefaults();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l10n.translate('settings_reset')),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.translate('reset_to_defaults')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Theme.of(context).primaryColor : null,
              size: 20,
            ),
            const SizedBox(width: 12),
            Flexible(child: Text(
              label,
              maxLines: 2,
              style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Theme.of(context).primaryColor : null,
                  overflow: TextOverflow.ellipsis,

              ),
            ))

          ],
        ),
      ),
    );
  }

  Widget _buildContentForIndex({
    required int index,
    required AppSettings settings,
    required SettingsNotifier settingsNotifier,
    required BuildContext context,
  }) {
    switch (index) {
      case 0:
        return _buildAppearanceContent(settings, settingsNotifier, context);
      case 1:
        return _buildDisplayContent(settings, settingsNotifier, context);
      case 2:
        return _buildOrderDefaultsContent(settings, settingsNotifier, context);
      case 3:
        return _buildCurrencyContent(settings, settingsNotifier, context);
      case 4:
        return _buildActionButtonsContent(settings, settingsNotifier, context);
      case 5:
        return _buildSyncSettingsContent(settings, settingsNotifier, context);
      case 6:
        return _buildServerSettingsContent(settings, settingsNotifier, context);
      case 7:
        return const _ScaleConfigSection();
      case 8:
        return _buildCashierDefaultsContent(settings, settingsNotifier, context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCashierDefaultsContent(
    AppSettings settings,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final granted = settings.cashierDefaultPermissions.toSet();

    void toggle(String token, bool selected) {
      final next = Set<String>.from(granted);
      if (selected) {
        next.add(token);
      } else {
        next.remove(token);
      }
      notifier.setCashierDefaultPermissions(next.toList()..sort());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('cashier_role_defaults'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('cashier_role_defaults_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.translate('cashier_role_defaults_hint'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in kPermissionGroups.entries)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(entry.key,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${entry.value.where(granted.contains).length} / ${entry.value.length}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final token in entry.value)
                  SwitchListTile(
                    dense: true,
                    title: Text(token,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13)),
                    value: granted.contains(token),
                    onChanged: (v) => toggle(token, v),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAppearanceContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('appearance'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('appearance_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.dark_mode,
          title: l10n.translate('dark_mode'),
          subtitle: l10n.translate('dark_mode_subtitle'),
          value: settings.isDarkMode,
          onChanged: (value) => notifier.setDarkMode(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.notifications,
          title: l10n.translate('enable_snack_bars'),
          subtitle: l10n.translate('enable_snack_bars_subtitle'),
          value: settings.enableSnackBars,
          onChanged: (value) => notifier.setEnableSnackBars(value),
        ),
        const SizedBox(height: 12),
        _buildLanguageSelector(
          context: context,
          currentLanguage: settings.language,
          onChanged: (value) => notifier.setLanguage(value),
        ),
        const SizedBox(height: 12),
        _buildLanguageSelector(
          context: context,
          currentLanguage: settings.loggingLanguage,
          onChanged: (value) => notifier.setLoggingLanguage(value),
          titleKey: 'logging_language',
          subtitleKey: 'select_logging_language',
          icon: Icons.history_edu,
        ),
      ],
    );
  }

  Widget _buildDisplayContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('display_settings'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('display_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.image,
          title: l10n.translate('show_product_images'),
          subtitle: l10n.translate('show_product_images_subtitle'),
          value: settings.showProductImages,
          onChanged: (value) => notifier.setShowProductImages(value),
        ),
        const SizedBox(height: 12),
        _buildProductCardSizeSelector(
          context: context,
          currentSize: settings.productCardSize,
          onChanged: (value) => notifier.setProductCardSize(value),
        ),
        const SizedBox(height: 12),
        _buildCategoryDisplayModeSelector(
          context: context,
          currentMode: settings.categoryDisplayMode,
          onChanged: (value) => notifier.setCategoryDisplayMode(value),
        ),
        const SizedBox(height: 12,),
        _buildOrderPanelPositionSwitch(
          context: context,
          value: settings.orderPanelOnRight,
          onChanged: (value) => notifier.setOrderPanelOnRight(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.connected_tv,
          title: l10n.translate('customer_display'),
          subtitle: l10n.translate('customer_display_subtitle'),
          value: settings.enableCustomerDisplay,
          onChanged: (value) => notifier.setEnableCustomerDisplay(value),
        ),
        const SizedBox(height: 24),
        // ── On-screen keyboard ──────────────────────────────────────
        Text(
          l10n.translate('onscreen_keyboard'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.keyboard,
          title: l10n.translate('show_onscreen_keyboard'),
          subtitle: l10n.translate('show_onscreen_keyboard_subtitle'),
          value: settings.showOnscreenKeyboard,
          onChanged: (value) => notifier.setShowOnscreenKeyboard(value),
        ),
        if (settings.showOnscreenKeyboard) ...[
          const SizedBox(height: 16),
          _buildKeyboardWidthSlider(context, settings, notifier),
        ],
      ],
    );
  }

  Widget _buildOrderDefaultsContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('order_defaults'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('order_defaults_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildOrderTypeSelector(
          context: context,
          currentType: settings.defaultOrderType,
          onChanged: (value) => notifier.setDefaultOrderType(value),
        ),
        const SizedBox(height: 12),
        _buildOrderStatusSelector(
          context: context,
          currentStatus: settings.defaultOrderStatus,
          onChanged: (value) => notifier.setDefaultOrderStatus(value),
        ),
        const SizedBox(height: 12),
        _buildPaidOrderStatusSelector(
          context: context,
          currentStatus: settings.paidOrderDefaultStatus,
          onChanged: (value) => notifier.setPaidOrderDefaultStatus(value),
        ),
        const SizedBox(height: 12),
        _buildDefaultPaymentMethodSelector(
          context: context,
          currentMethod: settings.defaultPaymentMethod,
          onChanged: (value) => notifier.setDefaultPaymentMethod(value),
        ),
      ],
    );
  }

  Widget _buildCurrencyContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('currency_settings'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('select_currency'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildCurrencySelector(
          context: context,
          currentCurrency: settings.currency,
          onChanged: (value) => notifier.setCurrency(value),
        ),
      ],
    );
  }

  Widget _buildActionButtonsContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;

    // Button configuration data
    final buttonConfigs = {
      'persons': (icon: Icons.people, titleKey: 'persons_button', subtitleKey: 'number_of_persons', visible: settings.showPersonsButton, setVisible: notifier.setShowPersonsButton),
      'orderType': (icon: Icons.restaurant, titleKey: 'order_type_button', subtitleKey: 'toggle_order_type', visible: settings.showOrderTypeButton, setVisible: notifier.setShowOrderTypeButton),
      'confirmOrder': (icon: Icons.task_alt, titleKey: 'confirm_button', subtitleKey: 'confirm_order', visible: settings.showConfirmOrderButton, setVisible: notifier.setShowConfirmOrderButton),
      'table': (icon: Icons.table_bar, titleKey: 'table_button', subtitleKey: 'table_selection', visible: settings.showTableButton, setVisible: notifier.setShowTableButton),
      'waiter': (icon: Icons.person_pin, titleKey: 'waiter_button', subtitleKey: 'waiter_selection', visible: settings.showWaiterButton, setVisible: notifier.setShowWaiterButton),
      'customer': (icon: Icons.person, titleKey: 'customer_button', subtitleKey: 'customer_selection', visible: settings.showCustomerButton, setVisible: notifier.setShowCustomerButton),
      'commercial': (icon: Icons.badge, titleKey: 'commercial_button', subtitleKey: 'commercial_selection', visible: settings.showCommercialButton, setVisible: notifier.setShowCommercialButton),
      'coupon': (icon: Icons.discount, titleKey: 'coupon_button', subtitleKey: 'apply_coupons', visible: settings.showCouponButton, setVisible: notifier.setShowCouponButton),
      'discount': (icon: Icons.percent, titleKey: 'discount_button', subtitleKey: 'manual_discount', visible: settings.showDiscountButton, setVisible: notifier.setShowDiscountButton),
      'print': (icon: Icons.print, titleKey: 'print_button', subtitleKey: 'print_orders', visible: settings.showPrintButton, setVisible: notifier.setShowPrintButton),
      'dailySummary': (icon: Icons.summarize, titleKey: 'daily_summary_button', subtitleKey: 'daily_report', visible: settings.showDailySummaryButton, setVisible: notifier.setShowDailySummaryButton),
      'pay': (icon: Icons.payment, titleKey: 'pay_button', subtitleKey: 'process_payment', visible: settings.showPayButton, setVisible: notifier.setShowPayButton),
      'proceed': (icon: Icons.check_circle, titleKey: 'proceed_button', subtitleKey: 'save_order', visible: true, setVisible: (_) async {}), // Always visible
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('action_buttons'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('action_buttons_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.translate('button_arrangement'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('drag_to_reorder'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        // Reorderable list for button arrangement
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: settings.buttonOrder.length,
          onReorder: (oldIndex, newIndex) {
            final newOrder = List<String>.from(settings.buttonOrder);
            if (newIndex > oldIndex) newIndex--;
            final item = newOrder.removeAt(oldIndex);
            newOrder.insert(newIndex, item);
            notifier.setButtonOrder(newOrder);
          },
          itemBuilder: (context, index) {
            final buttonKey = settings.buttonOrder[index];
            final config = buttonConfigs[buttonKey];
            if (config == null) return const SizedBox.shrink(key: ValueKey('unknown'));

            final isProceeed = buttonKey == 'proceed';

            return Card(
              key: ValueKey(buttonKey),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Icon(Icons.drag_handle, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Icon(config.icon, color: config.visible ? Theme.of(context).colorScheme.primary : Colors.grey),
                  ],
                ),
                title: Text(
                  l10n.translate(config.titleKey),
                  style: TextStyle(
                    color: config.visible ? null : Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  l10n.translate(config.subtitleKey),
                  style: TextStyle(
                    color: config.visible ? Colors.grey : Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
                trailing: isProceeed
                    ? Chip(
                        label: Text(l10n.translate('always_visible'), style: const TextStyle(fontSize: 10)),
                        backgroundColor: Colors.green.withValues(alpha: 0.2),
                      )
                    : Switch(
                        value: config.visible,
                        onChanged: (value) => config.setVisible(value),
                      ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSyncSettingsContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('sync_settings'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('sync_settings_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.sync,
          title: l10n.translate('auto_sync_online'),
          subtitle: l10n.translate('auto_sync_subtitle'),
          value: settings.autoSyncOnline,
          onChanged: (value) => notifier.setAutoSyncOnline(value),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.auto_delete,
          title: l10n.translate('auto_clear_synced'),
          subtitle: l10n.translate('auto_clear_subtitle'),
          value: settings.autoClearSyncedData,
          onChanged: (value) => notifier.setAutoClearSyncedData(value),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.receipt_long,
          title: l10n.translate('sync_unpaid_orders'),
          subtitle: l10n.translate('sync_unpaid_orders_subtitle'),
          value: settings.syncUnpaidOrders,
          onChanged: (value) => notifier.setSyncUnpaidOrders(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.timer,
          title: l10n.translate('sync_interval'),
          subtitle: l10n.translate('sync_interval_subtitle'),
          value: settings.autoSyncDurationMinutes,
          min: 1,
          max: 60,
          onChanged: (value) => notifier.setAutoSyncDuration(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.backup,
          title: l10n.translate('bulk_sync_size'),
          subtitle: l10n.translate('bulk_sync_subtitle'),
          value: settings.bulkSyncSize,
          min: 10,
          max: 200,
          onChanged: (value) => notifier.setBulkSyncSize(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.calendar_today,
          title: l10n.translate('data_retention'),
          subtitle: l10n.translate('data_retention_subtitle'),
          value: settings.dataRetentionDays,
          min: 1,
          max: 30,
          onChanged: (value) => notifier.setDataRetentionDays(value),
        ),
      ],
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildOrderTypeSelector({
    required BuildContext context,
    required String currentType,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_menu),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('default_order_type'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('select_default_order_type'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildOrderTypeOption(
                    context: context,
                    icon: Icons.restaurant,
                    label: l10n.translate('dine_in'),
                    value: 'DINE_IN',
                    currentValue: currentType,
                    onTap: () => onChanged('DINE_IN'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildOrderTypeOption(
                    context: context,
                    icon: Icons.takeout_dining,
                    label: l10n.translate('take_away'),
                    value: 'TAKE_AWAY',
                    currentValue: currentType,
                    onTap: () => onChanged('TAKE_AWAY'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderTypeOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String currentValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == currentValue;
    final color = value == 'DINE_IN' ? Colors.green : Colors.orange;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderStatusSelector({
    required BuildContext context,
    required String currentStatus,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pending_actions),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('default_order_status'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('initial_order_status'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.pause_circle,
                  label: l10n.translate('on_hold'),
                  value: 'ONHOLD',
                  currentValue: currentStatus,
                  color: Colors.grey,
                  onTap: () => onChanged('ONHOLD'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.pending,
                  label: l10n.translate('pending'),
                  value: 'PENDING',
                  currentValue: currentStatus,
                  color: Colors.orange,
                  onTap: () => onChanged('PENDING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.restaurant,
                  label: l10n.translate('preparing'),
                  value: 'PREPARING',
                  currentValue: currentStatus,
                  color: Colors.blue,
                  onTap: () => onChanged('PREPARING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.check_circle,
                  label: l10n.translate('completed'),
                  value: 'COMPLETED',
                  currentValue: currentStatus,
                  color: Colors.green,
                  onTap: () => onChanged('COMPLETED'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildPaidOrderStatusSelector({
    required BuildContext context,
    required String currentStatus,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('paid_order_default_status'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('paid_order_initial_status'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.pause_circle,
                  label: l10n.translate('on_hold'),
                  value: 'ONHOLD',
                  currentValue: currentStatus,
                  color: Colors.grey,
                  onTap: () => onChanged('ONHOLD'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.pending,
                  label: l10n.translate('pending'),
                  value: 'PENDING',
                  currentValue: currentStatus,
                  color: Colors.orange,
                  onTap: () => onChanged('PENDING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.restaurant,
                  label: l10n.translate('preparing'),
                  value: 'PREPARING',
                  currentValue: currentStatus,
                  color: Colors.blue,
                  onTap: () => onChanged('PREPARING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.check_circle,
                  label: l10n.translate('completed'),
                  value: 'COMPLETED',
                  currentValue: currentStatus,
                  color: Colors.green,
                  onTap: () => onChanged('COMPLETED'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderStatusOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String currentValue,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isSelected = value == currentValue;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultPaymentMethodSelector({
    required BuildContext context,
    required String currentMethod,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payment),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('default_payment_method'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('default_payment_method_subtitle'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.money,
                  label: l10n.translate('cash'),
                  value: 'CASH',
                  currentValue: currentMethod,
                  color: Colors.green,
                  onTap: () => onChanged('CASH'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.credit_card,
                  label: l10n.translate('card'),
                  value: 'CARD',
                  currentValue: currentMethod,
                  color: Colors.blue,
                  onTap: () => onChanged('CARD'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.phone_android,
                  label: l10n.translate('mobile'),
                  value: 'MOBILE',
                  currentValue: currentMethod,
                  color: Colors.purple,
                  onTap: () => onChanged('MOBILE'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.more_horiz,
                  label: l10n.translate('other'),
                  value: 'OTHER',
                  currentValue: currentMethod,
                  color: Colors.grey,
                  onTap: () => onChanged('OTHER'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCardSizeSelector({
    required BuildContext context,
    required int currentSize,
    required ValueChanged<int> onChanged,
  }) {
    final options = [
      (1, Icons.view_comfy, 'Small'),
      (2, Icons.grid_view, 'Medium'),
      (3, Icons.crop_square, 'Large'),
    ];
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.grid_3x3),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Card Size',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Size of product cards in the grid',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final (size, icon, label) in options) ...[
                  if (size > 1) const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => onChanged(size),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: currentSize == size
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: currentSize == size
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                            width: currentSize == size ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              icon,
                              color: currentSize == size
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: currentSize == size
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: currentSize == size
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDisplayModeSelector({
    required BuildContext context,
    required CategoryDisplayMode currentMode,
    required ValueChanged<CategoryDisplayMode> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.view_module),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('category_display_mode'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('category_display_subtitle'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCategoryModeOption(
                    context: context,
                    icon: Icons.view_headline,
                    label: l10n.translate('top_bar'),
                    subtitle: l10n.translate('categories_horizontal'),
                    value: CategoryDisplayMode.topBar,
                    currentValue: currentMode,
                    onTap: () => onChanged(CategoryDisplayMode.topBar),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCategoryModeOption(
                    context: context,
                    icon: Icons.grid_view,
                    label: l10n.translate('full_page'),
                    subtitle: l10n.translate('select_category_first'),
                    value: CategoryDisplayMode.fullPage,
                    currentValue: currentMode,
                    onTap: () => onChanged(CategoryDisplayMode.fullPage),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryModeOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required CategoryDisplayMode value,
    required CategoryDisplayMode currentValue,
    required VoidCallback onTap,
  }) {
    final isSelected = value == currentValue;
    final color = Theme.of(context).primaryColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? color : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? color.withValues(alpha: 0.8) : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencySelector({
    required BuildContext context,
    required String currentCurrency,
    required ValueChanged<String> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final currencies = [
      {'symbol': '\$', 'name': l10n.translate('us_dollar')},
      {'symbol': '€', 'name': l10n.translate('euro')},
      {'symbol': '£', 'name': l10n.translate('british_pound')},
      {'symbol': 'DH', 'name': l10n.translate('moroccan_dirham')},
      {'symbol': '₹', 'name': l10n.translate('indian_rupee')},
      {'symbol': '¥', 'name': l10n.translate('japanese_yen')},
      {'symbol': 'CHF', 'name': l10n.translate('swiss_franc')},
      {'symbol': 'R', 'name': l10n.translate('south_african_rand')},
    ];

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_money),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('currency_symbol'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('select_currency_display'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: currencies.map((currency) {
                final isSelected = currency['symbol'] == currentCurrency;
                return InkWell(
                  onTap: () => onChanged(currency['symbol']!),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currency['symbol']!,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Theme.of(context).primaryColor : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currency['name']!,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected
                                ? Theme.of(context).primaryColor.withValues(alpha: 0.8)
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector({
    required BuildContext context,
    required String currentLanguage,
    required ValueChanged<String> onChanged,
    String titleKey = 'language',
    String subtitleKey = 'select_app_language',
    IconData icon = Icons.language,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final languages = [
      {'code': 'en', 'name': 'English', 'flag': ''},
      {'code': 'ar', 'name': 'العربية', 'flag': ''},
      {'code': 'fr', 'name': 'Français', 'flag': ''},
    ];

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate(titleKey),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate(subtitleKey),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: languages.map((language) {
                final isSelected = language['code'] == currentLanguage;
                return InkWell(
                  onTap: () => onChanged(language['code']!),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          language['flag']!,
                          style: const TextStyle(fontSize: 32),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          language['name']!,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Theme.of(context).primaryColor : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberSelector({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: value > min
                      ? () => onChanged(value - 1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 28,
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  alignment: Alignment.center,
                  child: Text(
                    value.toString(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: value < max
                      ? () => onChanged(value + 1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 28,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderPanelPositionSwitch({
    required BuildContext context,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text(l10n.translate('order_panel_position')),
        subtitle: Text(l10n.translate('order_panel_right')),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildKeyboardWidthSlider(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final fraction = settings.onscreenKeyboardWidthFraction;
    final percent = (fraction * 100).round();
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.width_normal, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('keyboard_width'),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '$percent% ${l10n.translate('of_screen_width')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Slider(
              value: fraction,
              min: 0.25,
              max: 1.0,
              divisions: 15, // steps of ~5%
              label: '$percent%',
              onChanged: (v) => notifier.setOnscreenKeyboardWidthFraction(v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('25%', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text('50%', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text('75%', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text('100%', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerSettingsContent(
    AppSettings settings,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController portController = TextEditingController(
      text: (settings.serverPort ?? 8080).toString(),
    );
    final TextEditingController passwordController = TextEditingController(
      text: settings.serverPassword ?? '',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('server_settings'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('server_settings_subtitle'),
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),

        // Auto-start server
        _buildSwitchTile(
          context: context,
          icon: Icons.power_settings_new,
          title: l10n.translate('auto_start_server'),
          subtitle: l10n.translate('auto_start_subtitle'),
          value: settings.autoStartServer,
          onChanged: (value) => notifier.setAutoStartServer(value),
        ),
        const SizedBox(height: 16),

        // Server Port
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.settings_ethernet),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('server_port'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.translate('server_port_subtitle'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '8080',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    final port = int.tryParse(value);
                    if (port != null && port > 0 && port < 65536) {
                      notifier.setServerPort(port);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Server Password
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('server_password'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.translate('server_password_subtitle'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: l10n.translate('leave_empty_disable'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    notifier.setServerPassword(value.isEmpty ? null : value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Server Status Card
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('server_information'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Consumer(
                  builder: (context, ref, _) {
                    final serverService = ref.read(serverServiceProvider);
                    final isRunning = serverService.isRunning;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isRunning ? Icons.check_circle : Icons.cancel,
                              color: isRunning ? Colors.green : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isRunning ? l10n.translate('server_running') : l10n.translate('server_stopped'),
                              style: TextStyle(
                                color: isRunning ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (isRunning) ...[
                          const SizedBox(height: 8),
                          FutureBuilder<String>(
                            future: DiscoveryService.getLocalIp(),
                            builder: (context, snapshot) {
                              final ip = snapshot.data ?? 'loading...';
                              final url = 'http://$ip:${serverService.port}';
                              return Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      '${l10n.translate('server_url')}: $url',
                                      style: const TextStyle(fontFamily: 'monospace'),
                                    ),
                                  ),
                                  if (snapshot.hasData)
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      tooltip: 'Copy URL',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: url));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('URL copied to clipboard'),
                                            duration: Duration(seconds: 1),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Consumer(
                  builder: (context, ref, _) {
                    final serverService = ref.read(serverServiceProvider);
                    final isRunning = serverService.isRunning;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isRunning)
                          ElevatedButton.icon(
                            onPressed: () async {
                              await ref.read(serverServiceProvider).stop();
                              ref.read(serverRunningProvider.notifier).state = false;
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.translate('server_stopped'))),
                                );
                              }
                            },
                            icon: const Icon(Icons.stop),
                            label: Text(l10n.translate('stop_server')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                await startServerWithSettings(ref);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(l10n.translate('server_started'))),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('${l10n.translate('server_start_failed')}: $e')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: Text(l10n.translate('start_server')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),

      ],
    );
  }

}

class NavItem {
  final IconData icon;
  final String label;

  const NavItem({required this.icon, required this.label});
}
// ---------------------------------------------------------------------------
// Scale Configuration Section
// ---------------------------------------------------------------------------

class _ScaleConfigSection extends ConsumerStatefulWidget {
  const _ScaleConfigSection();

  @override
  ConsumerState<_ScaleConfigSection> createState() => _ScaleConfigSectionState();
}

class _ScaleConfigSectionState extends ConsumerState<_ScaleConfigSection> {
  late ScaleConfig _draft;
  final _testBarcodeCtrl = TextEditingController();
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(scaleConfigProvider);
    _testBarcodeCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _testBarcodeCtrl.dispose();
    super.dispose();
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  bool get _cartHasItems => ref.read(orderProvider).items.isNotEmpty;

  String? _validate() {
    if (_draft.prefix.isEmpty) return 'Prefix cannot be empty.';
    final expected = _draft.expectedTotalLength;
    final test = _testBarcodeCtrl.text.trim();
    if (test.isNotEmpty && test.length != expected) {
      return 'Total barcode length should be $expected '
          '(prefix ${_draft.prefix.length} + PLU ${_draft.pluLength} '
          '+ value ${_draft.weightLength}'
          '${_draft.hasCheckDigit ? " + check 1" : ""} = $expected), '
          'but test barcode has ${test.length} chars.';
    }
    return null;
  }

  // ── live preview ─────────────────────────────────────────────────────────

  Widget _buildPreview(AppLocalizations l10n) {
    final raw = _testBarcodeCtrl.text.trim();
    final expected = _draft.expectedTotalLength;
    final lengthOk = raw.length == expected;

    // Segment colors
    const cPrefix = Color(0xFF1565C0);
    const cPlu    = Color(0xFF2E7D32);
    const cValue  = Color(0xFFE65100);
    const cCheck  = Color(0xFF6A1B9A);

    // Extracted values (only if length matches)
    String? plu, valueStr;
    double? parsedValue;
    if (raw.length == expected) {
      final off = _draft.prefix.length;
      plu      = raw.substring(off, off + _draft.pluLength);
      valueStr = raw.substring(off + _draft.pluLength, off + _draft.pluLength + _draft.weightLength);
      final digits = RegExp(r'^\d+$');
      if (digits.hasMatch(valueStr)) {
        parsedValue = int.parse(valueStr) / _pow10(_draft.weightDecimalPlaces);
      }
    }

    final valueLabel = _draft.barcodeType == ScaleBarcodeType.weightEmbedded
        ? (parsedValue != null ? '→ ${parsedValue.toStringAsFixed(_draft.weightDecimalPlaces)} kg' : '')
        : (parsedValue != null ? '→ ${parsedValue.toStringAsFixed(2)} currency' : '');

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title + total length badge
            Row(
              children: [
                Text(l10n.translate('live_preview'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (raw.isEmpty || lengthOk) ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${l10n.translate('total_length')}: $expected',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Test barcode input
            TextField(
              controller: _testBarcodeCtrl,
              decoration: InputDecoration(
                labelText: l10n.translate('test_barcode'),
                hintText: l10n.translate('type_or_scan_barcode'),
                prefixIcon: const Icon(Icons.qr_code_scanner),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffixIcon: _testBarcodeCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _testBarcodeCtrl.clear(),
                      )
                    : null,
              ),
            ),
            if (raw.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Segmented color bar
              LayoutBuilder(builder: (context, constraints) {
                final total = _draft.expectedTotalLength;
                Widget _seg(String label, int len, Color color, String? extracted) {
                  final frac = len / total;
                  return Expanded(
                    flex: (frac * 100).round(),
                    child: Column(
                      children: [
                        Container(
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          extracted ?? '—',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _seg('Prefix', _draft.prefix.length, cPrefix,
                        raw.length >= _draft.prefix.length
                            ? raw.substring(0, _draft.prefix.length)
                            : null),
                    const SizedBox(width: 4),
                    _seg('PLU', _draft.pluLength, cPlu, plu),
                    const SizedBox(width: 4),
                    _seg('Value', _draft.weightLength, cValue,
                        valueStr != null ? '$valueStr\n$valueLabel' : valueStr),
                    if (_draft.hasCheckDigit) ...[
                      const SizedBox(width: 4),
                      _seg('Chk', 1, cCheck,
                          raw.length == expected ? raw[expected - 1] : null),
                    ],
                  ],
                );
              }),
              if (!lengthOk)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${l10n.translate('expected')} $expected ${l10n.translate('chars')}, '
                    '${l10n.translate('got')} ${raw.length}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.translate('scale_config'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(l10n.translate('scale_config_subtitle'),
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),

        // Cart-has-items warning
        if (_cartHasItems)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.translate('scale_config_locked'),
                      style: const TextStyle(color: Colors.orange)),
                ),
              ],
            ),
          ),

        // ── Prefix ──────────────────────────────────────────────────
        Text(l10n.translate('scale_prefix'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SizedBox(
          width: 200,
          child: TextField(
            enabled: !_cartHasItems,
            controller: TextEditingController(text: _draft.prefix)
              ..selection = TextSelection.collapsed(offset: _draft.prefix.length),
            decoration: InputDecoration(
              hintText: '21',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (v) => setState(() => _draft = _draft.copyWith(prefix: v)),
          ),
        ),
        const SizedBox(height: 16),

        // ── PLU length & Weight/Value length ────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('plu_length'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _draft.pluLength,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: List.generate(
                      8, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                    onChanged: _cartHasItems
                        ? null
                        : (v) => setState(() => _draft = _draft.copyWith(pluLength: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('value_length'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _draft.weightLength,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: List.generate(
                      8, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                    onChanged: _cartHasItems
                        ? null
                        : (v) => setState(() => _draft = _draft.copyWith(weightLength: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('decimal_places'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    value: _draft.weightDecimalPlaces,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: List.generate(
                      5, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
                    onChanged: _cartHasItems
                        ? null
                        : (v) => setState(() => _draft = _draft.copyWith(weightDecimalPlaces: v)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Check digit toggle ───────────────────────────────────────
        SwitchListTile(
          value: _draft.hasCheckDigit,
          onChanged: _cartHasItems
              ? null
              : (v) => setState(() => _draft = _draft.copyWith(hasCheckDigit: v)),
          title: Text(l10n.translate('has_check_digit')),
          subtitle: Text(l10n.translate('has_check_digit_subtitle')),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),

        // ── Barcode type ─────────────────────────────────────────────
        Text(l10n.translate('barcode_type'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SegmentedButton<ScaleBarcodeType>(
          segments: [
            ButtonSegment(
              value: ScaleBarcodeType.weightEmbedded,
              label: Text(l10n.translate('weight_embedded'), style: const TextStyle(fontSize: 12)),
              icon: const Icon(Icons.monitor_weight_outlined, size: 16),
            ),
            ButtonSegment(
              value: ScaleBarcodeType.priceEmbedded,
              label: Text(l10n.translate('price_embedded'), style: const TextStyle(fontSize: 12)),
              icon: const Icon(Icons.attach_money, size: 16),
            ),
          ],
          selected: {_draft.barcodeType},
          onSelectionChanged: _cartHasItems
              ? null
              : (s) => setState(() => _draft = _draft.copyWith(barcodeType: s.first)),
        ),
        const SizedBox(height: 24),

        // ── Live preview ─────────────────────────────────────────────
        _buildPreview(l10n),
        const SizedBox(height: 24),

        // ── Error message ────────────────────────────────────────────
        if (_saveError != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_saveError!, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),

        // ── Save button ──────────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _cartHasItems
              ? null
              : () {
                  final err = _validate();
                  if (err != null) {
                    setState(() => _saveError = err);
                    return;
                  }
                  setState(() => _saveError = null);
                  ref.read(scaleConfigProvider.notifier).save(_draft);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(AppLocalizations.of(context)!.translate('scale_config_saved')),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
          icon: const Icon(Icons.save),
          label: Text(l10n.translate('save')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

double _pow10(int n) {
  double result = 1.0;
  for (int i = 0; i < n; i++) result *= 10.0;
  return result;
}
