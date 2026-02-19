import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../utils/app_localizations.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            // Appearance Section
            Text(
              l10n.translate('appearance'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.dark_mode,
              title: l10n.translate('dark_mode'),
              subtitle: 'Use dark theme',
              value: settings.isDarkMode,
              onChanged: (value) => settingsNotifier.setDarkMode(value),
            ),
            const SizedBox(height: 12),
            _buildLanguageSelector(
              context: context,
              currentLanguage: settings.language,
              onChanged: (value) => settingsNotifier.setLanguage(value),
            ),

            const SizedBox(height: 24),

            // Display Section
            Text(
              'Display',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.image,
              title: l10n.translate('show_product_images'),
              subtitle: 'Display product images in the grid',
              value: settings.showProductImages,
              onChanged: (value) => settingsNotifier.setShowProductImages(value),
            ),
            const SizedBox(height: 12),
            _buildCategoryDisplayModeSelector(
              context: context,
              currentMode: settings.categoryDisplayMode,
              onChanged: (value) => settingsNotifier.setCategoryDisplayMode(value),
            ),

            const SizedBox(height: 24),

            // Order Defaults Section
            Text(
              'Order Defaults',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildOrderTypeSelector(
              context: context,
              currentType: settings.defaultOrderType,
              onChanged: (value) => settingsNotifier.setDefaultOrderType(value),
            ),
            const SizedBox(height: 12),
            _buildOrderStatusSelector(
              context: context,
              currentStatus: settings.defaultOrderStatus,
              onChanged: (value) => settingsNotifier.setDefaultOrderStatus(value),
            ),

            const SizedBox(height: 24),

            // Currency Section
            const Text(
              'Currency',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildCurrencySelector(
              context: context,
              currentCurrency: settings.currency,
              onChanged: (value) => settingsNotifier.setCurrency(value),
            ),

            const SizedBox(height: 24),

            // Action Buttons Section
            const Text(
              'Action Buttons Visibility',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.table_bar,
              title: 'Table Button',
              subtitle: 'Show table selection button',
              value: settings.showTableButton,
              onChanged: (value) => settingsNotifier.setShowTableButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.person,
              title: 'Customer Button',
              subtitle: 'Show customer selection button',
              value: settings.showCustomerButton,
              onChanged: (value) => settingsNotifier.setShowCustomerButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.badge,
              title: 'Commercial Button',
              subtitle: 'Show commercial selection button',
              value: settings.showCommercialButton,
              onChanged: (value) => settingsNotifier.setShowCommercialButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.discount,
              title: 'Coupon Button',
              subtitle: 'Show coupon button',
              value: settings.showCouponButton,
              onChanged: (value) => settingsNotifier.setShowCouponButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.percent,
              title: 'Discount Button',
              subtitle: 'Show manual discount button',
              value: settings.showDiscountButton,
              onChanged: (value) => settingsNotifier.setShowDiscountButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.print,
              title: 'Print Button',
              subtitle: 'Show print button',
              value: settings.showPrintButton,
              onChanged: (value) => settingsNotifier.setShowPrintButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.people,
              title: 'Persons Button',
              subtitle: 'Show number of persons button',
              value: settings.showPersonsButton,
              onChanged: (value) => settingsNotifier.setShowPersonsButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.restaurant,
              title: 'Order Type Button',
              subtitle: 'Show order type toggle button',
              value: settings.showOrderTypeButton,
              onChanged: (value) => settingsNotifier.setShowOrderTypeButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.task_alt,
              title: 'Confirm Order Button',
              subtitle: 'Show confirm order button',
              value: settings.showConfirmOrderButton,
              onChanged: (value) => settingsNotifier.setShowConfirmOrderButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.payment,
              title: 'Pay Button',
              subtitle: 'Show pay button',
              value: settings.showPayButton,
              onChanged: (value) => settingsNotifier.setShowPayButton(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.summarize,
              title: 'Daily Summary Button',
              subtitle: 'Show daily summary report button',
              value: settings.showDailySummaryButton,
              onChanged: (value) => settingsNotifier.setShowDailySummaryButton(value),
            ),

            const SizedBox(height: 24),

            // Sync Settings Section
            const Text(
              'Sync Settings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.sync,
              title: 'Auto Sync Online',
              subtitle: 'Automatically sync orders when online',
              value: settings.autoSyncOnline,
              onChanged: (value) => settingsNotifier.setAutoSyncOnline(value),
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.auto_delete,
              title: 'Auto Clear Synced Data',
              subtitle: 'Clear old synced data daily',
              value: settings.autoClearSyncedData,
              onChanged: (value) => settingsNotifier.setAutoClearSyncedData(value),
            ),
            const SizedBox(height: 12),
            _buildNumberSelector(
              context: context,
              icon: Icons.timer,
              title: 'Sync Interval (minutes)',
              subtitle: 'How often to sync data',
              value: settings.autoSyncDurationMinutes,
              min: 1,
              max: 60,
              onChanged: (value) => settingsNotifier.setAutoSyncDuration(value),
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
              onChanged: (value) => settingsNotifier.setBulkSyncSize(value),
            ),
            const SizedBox(height: 12),
            _buildNumberSelector(
              context: context,
              icon: Icons.calendar_today,
              title: 'Data Retention (days)',
              subtitle: 'Days to keep synced data before deletion',
              value: settings.dataRetentionDays,
              min: 1,
              max: 30,
              onChanged: (value) => settingsNotifier.setDataRetentionDays(value),
            ),

            const SizedBox(height: 32),

            // Reset Button
            Center(
              child: OutlinedButton.icon(
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
            ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
                      'Initial status for new orders (syncs when COMPLETED)',
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

  Widget _buildCategoryDisplayModeSelector({
    required BuildContext context,
    required CategoryDisplayMode currentMode,
    required ValueChanged<CategoryDisplayMode> onChanged,
  }) {
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
  }) {
    final languages = [
      {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
      {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
      {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
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
}

