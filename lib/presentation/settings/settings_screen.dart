import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../utils/app_localizations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedNavIndex = 0;

  List<NavItem> _getNavItems(AppLocalizations l10n) => [
    NavItem(icon: Icons.palette, label: l10n.translate('appearance')),
    NavItem(icon: Icons.display_settings, label: l10n.translate('display')),
    NavItem(icon: Icons.shopping_cart, label: l10n.translate('order_defaults')),
    NavItem(icon: Icons.attach_money, label: l10n.translate('currency')),
    NavItem(icon: Icons.touch_app, label: l10n.translate('action_buttons')),
    NavItem(icon: Icons.sync, label: l10n.translate('sync_settings')),
    NavItem(icon: Icons.dns, label: l10n.translate('server_settings')),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final navItems = _getNavItems(l10n);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).dialogBackgroundColor,
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.2),
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
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
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
      default:
        return const SizedBox.shrink();
    }
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
        _buildLanguageSelector(
          context: context,
          currentLanguage: settings.language,
          onChanged: (value) => notifier.setLanguage(value),
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
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.8,
          crossAxisSpacing: 12,
          mainAxisSpacing: 8,
          children: [
            _buildSwitchTile(
              context: context,
              icon: Icons.table_bar,
              title: l10n.translate('table_button'),
              subtitle: l10n.translate('table_selection'),
              value: settings.showTableButton,
              onChanged: (value) => notifier.setShowTableButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.person,
              title: l10n.translate('customer_button'),
              subtitle: l10n.translate('customer_selection'),
              value: settings.showCustomerButton,
              onChanged: (value) => notifier.setShowCustomerButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.badge,
              title: l10n.translate('commercial_button'),
              subtitle: l10n.translate('commercial_selection'),
              value: settings.showCommercialButton,
              onChanged: (value) => notifier.setShowCommercialButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.discount,
              title: l10n.translate('coupon_button'),
              subtitle: l10n.translate('apply_coupons'),
              value: settings.showCouponButton,
              onChanged: (value) => notifier.setShowCouponButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.percent,
              title: l10n.translate('discount_button'),
              subtitle: l10n.translate('manual_discount'),
              value: settings.showDiscountButton,
              onChanged: (value) => notifier.setShowDiscountButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.print,
              title: l10n.translate('print_button'),
              subtitle: l10n.translate('print_orders'),
              value: settings.showPrintButton,
              onChanged: (value) => notifier.setShowPrintButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.people,
              title: l10n.translate('persons_button'),
              subtitle: l10n.translate('number_of_persons'),
              value: settings.showPersonsButton,
              onChanged: (value) => notifier.setShowPersonsButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.restaurant,
              title: l10n.translate('order_type_button'),
              subtitle: l10n.translate('toggle_order_type'),
              value: settings.showOrderTypeButton,
              onChanged: (value) => notifier.setShowOrderTypeButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.task_alt,
              title: l10n.translate('confirm_button'),
              subtitle: l10n.translate('confirm_order'),
              value: settings.showConfirmOrderButton,
              onChanged: (value) => notifier.setShowConfirmOrderButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.payment,
              title: l10n.translate('pay_button'),
              subtitle: l10n.translate('process_payment'),
              value: settings.showPayButton,
              onChanged: (value) => notifier.setShowPayButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.summarize,
              title: l10n.translate('daily_summary_button'),
              subtitle: l10n.translate('daily_report'),
              value: settings.showDailySummaryButton,
              onChanged: (value) => notifier.setShowDailySummaryButton(value),
            ),
          ],
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
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

  Widget _buildCategoryDisplayModeSelector({
    required BuildContext context,
    required CategoryDisplayMode currentMode,
    required ValueChanged<CategoryDisplayMode> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.3),
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
                color: isSelected ? color.withOpacity(0.8) : Colors.grey,
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                          ? Theme.of(context).primaryColor.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.withOpacity(0.3),
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
                                ? Theme.of(context).primaryColor.withOpacity(0.8)
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
  }) {
    final l10n = AppLocalizations.of(context)!;
    final languages = [
      {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
      {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
      {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    ];

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('language'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('select_app_language'),
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
                          ? Theme.of(context).primaryColor.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey.withOpacity(0.3),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
                          Text(
                            '${l10n.translate('server_url')}: http://localhost:${serverService.port}',
                            style: const TextStyle(fontFamily: 'monospace'),
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
        const SizedBox(height: 16),

        // API Endpoints Documentation
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.api),
                    const SizedBox(width: 12),
                    Text(
                      l10n.translate('available_endpoints'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildEndpointDoc('GET', '/health', l10n.translate('health_check')),
                _buildEndpointDoc('GET', '/orders/', l10n.translate('get_orders')),
                _buildEndpointDoc('POST', '/orders/', l10n.translate('create_order')),
                _buildEndpointDoc('PUT', '/orders/{code}', l10n.translate('update_order')),
                _buildEndpointDoc('PUT', '/orders/{code}?status=X', l10n.translate('update_order_status')),
                _buildEndpointDoc('PUT', '/orders/products/{id}?status=X', l10n.translate('update_product_status')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndpointDoc(String method, String path, String description) {
    Color methodColor;
    switch (method) {
      case 'GET':
        methodColor = Colors.blue;
        break;
      case 'POST':
        methodColor = Colors.green;
        break;
      case 'PUT':
        methodColor = Colors.orange;
        break;
      case 'DELETE':
        methodColor = Colors.red;
        break;
      default:
        methodColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: methodColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              method,
              style: TextStyle(
                color: methodColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            description,
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final String label;

  const NavItem({required this.icon, required this.label});
}