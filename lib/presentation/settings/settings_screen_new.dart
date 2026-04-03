import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _currencyController = TextEditingController();
  int _expandedIndex = 0; // Track which panel is expanded

  @override
  void initState() {
    super.initState();
    // Initialize currency controller with current setting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsProvider);
      _currencyController.text = settings.currency;
    });
  }

  @override
  void dispose() {
    _currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24),
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
            const Divider(height: 1),

            // Scrollable content with ExpansionPanelList
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ExpansionPanelList(
                  expandedHeaderPadding: EdgeInsets.zero,
                  elevation: 0,
                  expansionCallback: (int index, bool isExpanded) {
                    setState(() {
                      _expandedIndex = isExpanded ? -1 : index;
                    });
                  },
                  children: [
                    // Appearance Panel
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          leading: const Icon(Icons.palette_outlined),
                          title: const Text(
                            'Appearance',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildSwitchTile(
                              context: context,
                              icon: Icons.dark_mode,
                              title: 'Dark Mode',
                              subtitle: 'Use dark theme',
                              value: settings.isDarkMode,
                              onChanged: (value) => settingsNotifier.setDarkMode(value),
                            ),
                          ],
                        ),
                      ),
                      isExpanded: _expandedIndex == 0,
                    ),

                    // Display Panel
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          leading: const Icon(Icons.display_settings),
                          title: const Text(
                            'Display',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildSwitchTile(
                              context: context,
                              icon: Icons.image,
                              title: 'Show Product Images',
                              subtitle: 'Display product images in the grid',
                              value: settings.showProductImages,
                              onChanged: (value) => settingsNotifier.setShowProductImages(value),
                            ),
                            const SizedBox(height: 16),
                            _buildCategoryDisplayModeSelector(
                              context: context,
                              currentMode: settings.categoryDisplayMode,
                              onChanged: (value) => settingsNotifier.setCategoryDisplayMode(value),
                            ),
                          ],
                        ),
                      ),
                      isExpanded: _expandedIndex == 1,
                    ),

                    // Order Defaults Panel
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: const Text(
                            'Order Defaults',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildOrderTypeSelector(
                              context: context,
                              currentType: settings.defaultOrderType,
                              onChanged: (value) => settingsNotifier.setDefaultOrderType(value),
                            ),
                            const SizedBox(height: 16),
                            _buildOrderStatusSelector(
                              context: context,
                              currentStatus: settings.defaultOrderStatus,
                              onChanged: (value) => settingsNotifier.setDefaultOrderStatus(value),
                            ),
                            const SizedBox(height: 16),
                            _buildPaidOrderStatusSelector(
                              context: context,
                              currentStatus: settings.paidOrderDefaultStatus,
                              onChanged: (value) => settingsNotifier.setPaidOrderDefaultStatus(value),
                            ),
                          ],
                        ),
                      ),
                      isExpanded: _expandedIndex == 2,
                    ),

                    // Currency Panel
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          leading: const Icon(Icons.attach_money),
                          title: const Text(
                            'Currency',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Text('Current: ${settings.currency}'),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Enter your currency symbol',
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _currencyController,
                              decoration: InputDecoration(
                                labelText: 'Currency Symbol',
                                hintText: 'e.g., \$, €, £, DH',
                                prefixIcon: const Icon(Icons.money),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                helperText: 'This will be displayed before all prices',
                              ),
                              maxLength: 5,
                              onChanged: (value) {
                                if (value.isNotEmpty) {
                                  settingsNotifier.setCurrency(value);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Common currencies:',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildQuickCurrencyChip('\$', 'USD', settingsNotifier),
                                _buildQuickCurrencyChip('€', 'EUR', settingsNotifier),
                                _buildQuickCurrencyChip('£', 'GBP', settingsNotifier),
                                _buildQuickCurrencyChip('DH', 'MAD', settingsNotifier),
                                _buildQuickCurrencyChip('₹', 'INR', settingsNotifier),
                                _buildQuickCurrencyChip('¥', 'JPY', settingsNotifier),
                                _buildQuickCurrencyChip('CHF', 'CHF', settingsNotifier),
                                _buildQuickCurrencyChip('R', 'ZAR', settingsNotifier),
                              ],
                            ),
                          ],
                        ),
                      ),
                      isExpanded: _expandedIndex == 3,
                    ),

                    // Action Buttons Panel
                    ExpansionPanel(
                      headerBuilder: (context, isExpanded) {
                        return ListTile(
                          leading: const Icon(Icons.touch_app),
                          title: const Text(
                            'Action Buttons',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: const Text('Show or hide buttons'),
                        );
                      },
                      body: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            _buildSwitchTile(
                              context: context,
                              icon: Icons.table_bar,
                              title: 'Table Button',
                              subtitle: 'Show table selection',
                              value: settings.showTableButton,
                              onChanged: (value) => settingsNotifier.setShowTableButton(value),
                            ),
                            const SizedBox(height: 8),
                            _buildSwitchTile(
                              context: context,
                              icon: Icons.person,
                              title: 'Customer Button',
                              subtitle: 'Show customer selection',
                              value: settings.showCustomerButton,
                              onChanged: (value) => settingsNotifier.setShowCustomerButton(value),
                            ),
                            const SizedBox(height: 8),
                            _buildSwitchTile(
                              context: context,
                              icon: Icons.badge,
                              title: 'Commercial Button',
                              subtitle: 'Show commercial selection',
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
                              subtitle: 'Show manual discount',
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
                          ],
                        ),
                      ),
                      isExpanded: _expandedIndex == 4,
                    ),
                  ],
                ),
              ),
            ),

            // Footer with Reset Button
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
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
                      _currencyController.text = '\$';
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCurrencyChip(String symbol, String code, SettingsNotifier notifier) {
    return ActionChip(
      label: Text('$symbol $code'),
      onPressed: () {
        _currencyController.text = symbol;
        notifier.setCurrency(symbol);
      },
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
      child: SwitchListTile(
        secondary: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: onChanged,
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
            const Text(
              'Default Order Type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
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
    final color = Theme.of(context).primaryColor;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? color : Colors.grey),
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
            const Text(
              'Default Order Status',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Status for new orders (syncs when COMPLETED)',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(context, 'PENDING', 'Pending', currentStatus, onChanged),
                _buildStatusChip(context, 'COMPLETED', 'Completed', currentStatus, onChanged),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    String value,
    String label,
    String currentValue,
    ValueChanged<String> onChanged,
  ) {
    final isSelected = value == currentValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) => onChanged(value),
    );
  }

  Widget _buildPaidOrderStatusSelector({
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
            const Text(
              'Paid Order Default Status',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Status when order is fully paid',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(context, 'ONHOLD', 'On Hold', currentStatus, onChanged),
                _buildStatusChip(context, 'PENDING', 'Pending', currentStatus, onChanged),
                _buildStatusChip(context, 'PREPARING', 'Preparing', currentStatus, onChanged),
                _buildStatusChip(context, 'COMPLETED', 'Completed', currentStatus, onChanged),
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
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category Display',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildCategoryModeOption(
                    context: context,
                    icon: Icons.view_list,
                    label: 'Top Bar',
                    subtitle: 'Horizontal',
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
                    subtitle: 'Grid view',
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : null,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? color.withValues(alpha: 0.8) : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

