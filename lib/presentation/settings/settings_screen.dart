import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

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
                  const Text(
                    'Settings',
                    style: TextStyle(
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
            const Text(
              'Appearance',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.dark_mode,
              title: 'Dark Mode',
              subtitle: 'Use dark theme',
              value: settings.isDarkMode,
              onChanged: (value) => settingsNotifier.setDarkMode(value),
            ),

            const SizedBox(height: 24),

            // Display Section
            const Text(
              'Display',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              context: context,
              icon: Icons.image,
              title: 'Show Product Images',
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
            const Text(
              'Order Defaults',
              style: TextStyle(
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
}

