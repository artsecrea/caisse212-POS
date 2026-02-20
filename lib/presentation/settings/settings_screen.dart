import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../utils/app_localizations.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedNavIndex = 0;

  final List<NavItem> _navItems = const [
    NavItem(icon: Icons.palette, label: 'Appearance'),
    NavItem(icon: Icons.display_settings, label: 'Display'),
    NavItem(icon: Icons.shopping_cart, label: 'Order Defaults'),
    NavItem(icon: Icons.attach_money, label: 'Currency'),
    NavItem(icon: Icons.touch_app, label: 'Action Buttons'),
    NavItem(icon: Icons.sync, label: 'Sync Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

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
                            itemCount: _navItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                            itemBuilder: (context, index) {
                              final isSelected = _selectedNavIndex == index;
                              return _buildNavItem(
                                icon: _navItems[index].icon,
                                label: _navItems[index].label,
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
                          title: const Text('Reset Settings'),
                          content: const Text('Are you sure you want to reset all settings to defaults?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await settingsNotifier.resetToDefaults();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Settings reset to defaults'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset to Defaults'),
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
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
            ),
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
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAppearanceContent(
      AppSettings settings,
      SettingsNotifier notifier,
      BuildContext context,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Appearance',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Customize the look and feel of the application',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.dark_mode,
          title: 'Dark Mode',
          subtitle: 'Use dark theme throughout the app',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Display Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Configure how content is displayed',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.image,
          title: 'Show Product Images',
          subtitle: 'Display product images in the grid view',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Order Defaults',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Set default values for new orders',
          style: TextStyle(color: Colors.grey),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Currency Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select your preferred currency',
          style: TextStyle(color: Colors.grey),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Action Buttons',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Toggle visibility of action buttons',
          style: TextStyle(color: Colors.grey),
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
              title: 'Table Button',
              subtitle: 'Table selection',
              value: settings.showTableButton,
              onChanged: (value) => notifier.setShowTableButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.person,
              title: 'Customer Button',
              subtitle: 'Customer selection',
              value: settings.showCustomerButton,
              onChanged: (value) => notifier.setShowCustomerButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.badge,
              title: 'Commercial Button',
              subtitle: 'Commercial selection',
              value: settings.showCommercialButton,
              onChanged: (value) => notifier.setShowCommercialButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.discount,
              title: 'Coupon Button',
              subtitle: 'Apply coupons',
              value: settings.showCouponButton,
              onChanged: (value) => notifier.setShowCouponButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.percent,
              title: 'Discount Button',
              subtitle: 'Manual discount',
              value: settings.showDiscountButton,
              onChanged: (value) => notifier.setShowDiscountButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.print,
              title: 'Print Button',
              subtitle: 'Print orders',
              value: settings.showPrintButton,
              onChanged: (value) => notifier.setShowPrintButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.people,
              title: 'Persons Button',
              subtitle: 'Number of persons',
              value: settings.showPersonsButton,
              onChanged: (value) => notifier.setShowPersonsButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.restaurant,
              title: 'Order Type Button',
              subtitle: 'Toggle order type',
              value: settings.showOrderTypeButton,
              onChanged: (value) => notifier.setShowOrderTypeButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.task_alt,
              title: 'Confirm Button',
              subtitle: 'Confirm order',
              value: settings.showConfirmOrderButton,
              onChanged: (value) => notifier.setShowConfirmOrderButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.payment,
              title: 'Pay Button',
              subtitle: 'Process payment',
              value: settings.showPayButton,
              onChanged: (value) => notifier.setShowPayButton(value),
            ),
            _buildSwitchTile(
              context: context,
              icon: Icons.summarize,
              title: 'Daily Summary',
              subtitle: 'Daily report',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sync Settings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Configure data synchronization',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildSwitchTile(
          context: context,
          icon: Icons.sync,
          title: 'Auto Sync Online',
          subtitle: 'Automatically sync orders when online',
          value: settings.autoSyncOnline,
          onChanged: (value) => notifier.setAutoSyncOnline(value),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.auto_delete,
          title: 'Auto Clear Synced Data',
          subtitle: 'Clear old synced data daily',
          value: settings.autoClearSyncedData,
          onChanged: (value) => notifier.setAutoClearSyncedData(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.timer,
          title: 'Sync Interval',
          subtitle: 'How often to sync data (minutes)',
          value: settings.autoSyncDurationMinutes,
          min: 1,
          max: 60,
          onChanged: (value) => notifier.setAutoSyncDuration(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.backup,
          title: 'Bulk Sync Size',
          subtitle: 'Number of records to sync at once',
          value: settings.bulkSyncSize,
          min: 10,
          max: 200,
          onChanged: (value) => notifier.setBulkSyncSize(value),
        ),
        const SizedBox(height: 12),
        _buildNumberSelector(
          context: context,
          icon: Icons.calendar_today,
          title: 'Data Retention',
          subtitle: 'Days to keep synced data before deletion',
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Order Type',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Select default type for new orders',
                      style: TextStyle(
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
                    label: 'Dine In',
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
                    label: 'Take Away',
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default Order Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Initial status for new orders',
                      style: TextStyle(
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
                  label: 'On Hold',
                  value: 'ONHOLD',
                  currentValue: currentStatus,
                  color: Colors.grey,
                  onTap: () => onChanged('ONHOLD'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.pending,
                  label: 'Pending',
                  value: 'PENDING',
                  currentValue: currentStatus,
                  color: Colors.orange,
                  onTap: () => onChanged('PENDING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.restaurant,
                  label: 'Preparing',
                  value: 'PREPARING',
                  currentValue: currentStatus,
                  color: Colors.blue,
                  onTap: () => onChanged('PREPARING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.check_circle,
                  label: 'Completed',
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category Display Mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'How to display categories on main screen',
                      style: TextStyle(
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
                    label: 'Top Bar',
                    subtitle: 'Categories in horizontal bar',
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
                    label: 'Full Page',
                    subtitle: 'Select category first',
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
    final currencies = [
      {'symbol': '\$', 'name': 'US Dollar'},
      {'symbol': '€', 'name': 'Euro'},
      {'symbol': '£', 'name': 'British Pound'},
      {'symbol': 'DH', 'name': 'Moroccan Dirham'},
      {'symbol': '₹', 'name': 'Indian Rupee'},
      {'symbol': '¥', 'name': 'Japanese Yen'},
      {'symbol': 'CHF', 'name': 'Swiss Franc'},
      {'symbol': 'R', 'name': 'South African Rand'},
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Currency Symbol',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Select currency to display in the app',
                      style: TextStyle(
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Language',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'Select app language',
                      style: TextStyle(
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
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: const Text('Order Panel Position'),
        subtitle: const Text('Show order panel on the right side'),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final String label;

  const NavItem({required this.icon, required this.label});
}