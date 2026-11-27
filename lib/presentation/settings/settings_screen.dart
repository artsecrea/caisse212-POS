import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/settings_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/catalogue_repository.dart';
import '../../providers/database_providers.dart';
import '../../services/local_order_service.dart';
import '../../providers/update_provider.dart';
import '../../services/update_config.dart';
import '../widgets/users_management_screen.dart' show kPermissionGroups;
import '../widgets/update_dialog.dart';
import '../../domain/models/app_settings.dart';
import '../../utils/app_localizations.dart';
import '../../utils/permission_descriptions.dart';
import '../../utils/responsive_utils.dart';
import '../../services/discovery_service.dart';
import '../../domain/models/scale_config.dart';
import '../../domain/models/z_report_sections.dart';
import '../../providers/scale_config_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/session_rules_provider.dart';
import '../../providers/business_day_provider.dart';
import '../../services/z_service.dart' show ZService;
import '../../providers/sse_provider.dart';
import '../../services/sse_service.dart';
import '../widgets/settings_lock_dialog.dart'
    show kSettingsPinMaxLength, isValidSettingsPin;
import '../../services/permission_service.dart'
    show Permissions, permissionServiceProvider;
import '../../services/autostart_service.dart';
import '../../utils/full_logout.dart';
import '../../providers/admin_elevation_provider.dart';
import '../widgets/adaptive_text_field.dart';
import '../../utils/snackbar_helper.dart';

/// Lower-cased because Windows reports e.g. `DESKTOP-JDJEKZB`; DNS/NetBIOS
/// lookups are case-insensitive and the lower form reads better in a URL.
final String _hostName = () {
  if (kIsWeb) return '';
  try {
    return Platform.localHostname.trim().toLowerCase();
  } catch (_) {
    return '';
  }
}();

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedNavIndex = 0;

  // Owned by the State, not rebuilt per frame. A controller created inside
  // `build` is a fresh object on every rebuild, and every settings write
  // rebuilds this screen — so the on-screen keyboard kept typing into a
  // controller that was thrown away before the next keystroke landed, and
  // the caret reset to the invalid `offset: -1` that makes the keyboard
  // swallow input outright.
  late final TextEditingController _portController;
  late final TextEditingController _serverPasswordController;
  late final TextEditingController _quickCashController;
  late final TextEditingController _notePresetsController;
  late final TextEditingController _deliveryFeePresetsController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _portController = TextEditingController(
      text: (settings.serverPort ?? 8080).toString(),
    );
    _serverPasswordController = TextEditingController(
      text: settings.serverPassword ?? '',
    );
    _notePresetsController = TextEditingController(
      text: settings.notePresets.join(', '),
    );
    _deliveryFeePresetsController = TextEditingController(
      text: settings.deliveryFeePresets.map(_trimPreset).join(', '),
    );
    _quickCashController = TextEditingController(
      text: settings.quickCashAmounts.join(', '),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    _serverPasswordController.dispose();
    _quickCashController.dispose();
    _notePresetsController.dispose();
    _deliveryFeePresetsController.dispose();
    super.dispose();
  }

  List<NavItem> _getNavItems(AppLocalizations l10n, {required bool isAdmin}) => [
    NavItem(icon: Icons.palette, label: l10n.translate('appearance')),
    NavItem(icon: Icons.display_settings, label: l10n.translate('display')),
    NavItem(icon: Icons.shopping_cart, label: l10n.translate('order_defaults')),
    NavItem(icon: Icons.attach_money, label: l10n.translate('currency')),
    NavItem(icon: Icons.touch_app, label: l10n.translate('action_buttons')),
    NavItem(icon: Icons.sync, label: l10n.translate('sync_settings')),
    NavItem(icon: Icons.dns, label: l10n.translate('server_settings')),
    NavItem(icon: Icons.scale, label: l10n.translate('scale_config')),
    NavItem(icon: Icons.info_outline, label: l10n.translate('about')),
    NavItem(icon: Icons.schedule, label: l10n.translate('session_rules')),
    if (isAdmin)
      NavItem(icon: Icons.badge, label: l10n.translate('cashier_role_defaults')),
    if (isAdmin)
      NavItem(icon: Icons.point_of_sale, label: l10n.translate('z_settings')),
    if (isAdmin)
      NavItem(icon: Icons.lock_outline, label: l10n.translate('settings_lock')),
    if (isAdmin)
      NavItem(
          icon: Icons.assignment_turned_in_outlined,
          label: l10n.translate('session_close_rules')),
    if (isAdmin)
      NavItem(
          icon: Icons.restaurant_menu,
          label: l10n.translate('kitchen_rules')),
  ];

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.watch(currentUserProvider);
    final isAdmin = currentUser?.type.toLowerCase() == 'admin';
    // `pos:settings:view` gets you in (top_bar gates the menu entry on it);
    // `pos:settings:update` is what lets you change anything. Enforced once
    // here rather than on ~200 individual controls — a single AbsorbPointer
    // cannot be forgotten the way a per-widget `onChanged: canEdit ? … : null`
    // is forgotten on the next setting somebody adds.
    final canEditSettings = ref
        .watch(permissionServiceProvider)
        .hasPermission(Permissions.settingsUpdate);
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
            if (!canEditSettings)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .secondaryContainer
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    Icon(Icons.lock_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('settings_read_only'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                  ]),
                ),
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
                      child: AbsorbPointer(
                        // About (index 8) is the update check and the logout —
                        // not settings writes — so it stays usable read-only.
                        absorbing: !canEditSettings && _selectedNavIndex != 8,
                        child: Opacity(
                          opacity:
                              (!canEditSettings && _selectedNavIndex != 8)
                                  ? 0.6
                                  : 1.0,
                          child: _buildContentForIndex(
                            index: _selectedNavIndex,
                            settings: settings,
                            settingsNotifier: settingsNotifier,
                            context: context,
                          ),
                        ),
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
                    onPressed: !canEditSettings ? null : () async {
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
                          SnackBarHelper.showToast(l10n.translate('settings_reset'), kind: ToastKind.success);
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
                  // Full logout — disconnect the terminal from its tenant and
                  // wipe the local database. Moved here from the top-bar menu:
                  // it is a setup action, and it had no business sitting one tap
                  // from Logout in a menu the cashier opens all shift.
                  //
                  // Admin-only, and still behind its own credential prompt plus
                  // a confirmation inside runFullLogout.
                  if (isAdmin) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () => runFullLogout(context, ref),
                      icon: const Icon(Icons.link_off),
                      label: Text(l10n.translate('full_logout')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ],
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
        return _buildAboutContent(context);
      case 9:
        return _buildSessionRulesContent(context);
      case 10:
        return _buildCashierDefaultsContent(settings, settingsNotifier, context);
      case 11:
        return _buildZSettingsContent(settings, settingsNotifier, context);
      case 12:
        return _buildSettingsLockContent(settings, settingsNotifier, context);
      case 13:
        return _buildSessionCloseRulesContent(
            settings, settingsNotifier, context);
      case 14:
        return _buildKitchenRulesContent(settings, settingsNotifier, context);
      default:
        return const SizedBox.shrink();
    }
  }

  /// Kitchen ticket rules — admin only (the nav entry is behind `isAdmin`).
  ///
  /// Admin-only because it adds a control to every order line: a shop that
  /// does not work in courses should never see it, and a cashier should not
  /// be able to summon it for themselves.
  Widget _buildKitchenRulesContent(
    AppSettings settings,
    SettingsNotifier settingsNotifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('kitchen_rules'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('kitchen_rules_subtitle'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.coursesEnabled,
                  onChanged: settingsNotifier.setCoursesEnabled,
                  title: Text(l10n.translate('courses_enabled')),
                  subtitle: Text(
                    l10n.translate('courses_enabled_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: settings.printKitchenCancellations,
                  onChanged: settingsNotifier.setPrintKitchenCancellations,
                  title: Text(l10n.translate('print_kitchen_cancellations')),
                  subtitle: Text(
                    l10n.translate('print_kitchen_cancellations_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Session-close rules — admin only (the nav entry is behind `isAdmin`).
  ///
  /// One switch, off by default. Off is what every till already does: the
  /// cashier closes their own session whatever the drawer says, and the
  /// shortfall and any open tables are reported on the X. On makes that a
  /// supervised moment instead — the discrepancy still prints, but somebody
  /// with authority has to be standing there to accept it.
  ///
  /// Admin-only on purpose: a cashier who could turn this off is not subject
  /// to it.
  Widget _buildSessionCloseRulesContent(
    AppSettings settings,
    SettingsNotifier settingsNotifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('session_close_rules'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('session_close_rules_subtitle'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SwitchListTile(
              value: settings.requireAdminToCloseUnbalanced,
              onChanged: settingsNotifier.setRequireAdminToCloseUnbalanced,
              title: Text(l10n.translate('require_admin_close_unbalanced')),
              subtitle: Text(
                l10n.translate('require_admin_close_unbalanced_hint'),
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SwitchListTile(
              value: settings.disableSessionAutoClose,
              onChanged: settingsNotifier.setDisableSessionAutoClose,
              title: Text(l10n.translate('disable_session_auto_close')),
              subtitle: Text(
                l10n.translate('disable_session_auto_close_hint'),
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.translate('unpaid_orders_at_close'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.unpaidPromptOnZClose,
                  onChanged: settingsNotifier.setUnpaidPromptOnZClose,
                  title: Text(l10n.translate('unpaid_prompt_on_z_close')),
                  subtitle: Text(
                    l10n.translate('unpaid_prompt_on_z_close_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                SwitchListTile(
                  value: settings.allowZCloseWithUnpaid,
                  onChanged: settings.unpaidPromptOnZClose
                      ? settingsNotifier.setAllowZCloseWithUnpaid
                      : null,
                  title: Text(l10n.translate('allow_z_close_with_unpaid')),
                  subtitle: Text(
                    l10n.translate('allow_z_close_with_unpaid_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                const Divider(),
                SwitchListTile(
                  value: settings.unpaidPromptOnSessionClose,
                  onChanged: settingsNotifier.setUnpaidPromptOnSessionClose,
                  title: Text(l10n.translate('unpaid_prompt_on_session_close')),
                  subtitle: Text(
                    l10n.translate('unpaid_prompt_on_session_close_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.translate('z_warnings'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate('z_warnings_hint'),
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                SwitchListTile(
                  value: settings.zWarnOpenTooLong,
                  onChanged: settingsNotifier.setZWarnOpenTooLong,
                  title: Text(l10n.translate('z_warn_open_too_long')),
                  subtitle: Text(
                    l10n.translate('z_warn_open_too_long_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                ListTile(
                  enabled: settings.zWarnOpenTooLong,
                  leading: const Icon(Icons.hourglass_bottom),
                  title: Text(l10n.translate('z_warn_open_hours')),
                  trailing: DropdownButton<int>(
                    value: settings.zWarnOpenHours,
                    items: [
                      for (final h in {
                        6, 8, 10, 12, 14, 16, 18, 20, 24, 36, 48,
                        settings.zWarnOpenHours,
                      }.toList()..sort())
                        DropdownMenuItem(value: h, child: Text('$h h')),
                    ],
                    onChanged: settings.zWarnOpenTooLong
                        ? (h) {
                            if (h != null) settingsNotifier.setZWarnOpenHours(h);
                          }
                        : null,
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  value: settings.zWarnPastCutoff,
                  onChanged: settingsNotifier.setZWarnPastCutoff,
                  title: Text(l10n.translate('z_warn_past_cutoff')),
                  subtitle: Text(
                    l10n.translate('z_warn_past_cutoff_hint'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  isThreeLine: true,
                ),
                ListTile(
                  enabled: settings.zWarnPastCutoff,
                  leading: const Icon(Icons.schedule),
                  title: Text(l10n.translate('z_warn_cutoff_time')),
                  trailing: DropdownButton<String>(
                    value: settings.zWarnCutoffTime,
                    items: [
                      for (final t in {
                        for (var m = 0; m < 24 * 60; m += 30)
                          '${(m ~/ 60).toString().padLeft(2, '0')}:'
                              '${(m % 60).toString().padLeft(2, '0')}',
                        settings.zWarnCutoffTime,
                      }.toList()..sort())
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: settings.zWarnPastCutoff
                        ? (t) {
                            if (t != null) settingsNotifier.setZWarnCutoffTime(t);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 14, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.translate('require_admin_close_note'),
                style: TextStyle(fontSize: 12, color: cs.outline),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Settings lock page — admin only (the nav entry is behind `isAdmin`).
  ///
  /// Deliberately reachable only from INSIDE Settings: whoever is looking at
  /// this already got past the lock, so there is no circularity. Locking
  /// yourself out is recoverable through the master code, which is why the
  /// hint below tells the admin it exists without spelling out the value.
  Widget _buildSettingsLockContent(
    AppSettings settings,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasPin = settings.settingsPin.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('settings_lock'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('settings_lock_intro'),
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        _buildSwitchTile(
          context: context,
          icon: Icons.lock_outline,
          title: l10n.translate('settings_lock_enabled'),
          subtitle: hasPin
              ? l10n.translate('settings_lock_enabled_subtitle')
              : l10n.translate('settings_lock_needs_pin'),
          value: settings.settingsLockEnabled,
          onChanged: (value) {
            // No pin yet: send the admin to set one rather than flip a switch
            // that cannot arm (setSettingsLock would refuse it silently).
            if (!hasPin) {
              _promptForNewPin(context, notifier);
              return;
            }
            notifier.setSettingsLock(enabled: value);
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        hasPin
                            ? l10n.translate('settings_pin_set')
                            : l10n.translate('settings_pin_not_set'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _promptForNewPin(context, notifier),
                      child: Text(hasPin
                          ? l10n.translate('change_pin')
                          : l10n.translate('set_pin')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('settings_master_code_hint'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Ask for a new 4-digit pin, twice, and store it.
  ///
  /// Confirming twice because a mistyped pin is only discovered the next time
  /// somebody needs Settings — by then the admin does not know what they typed.
  Future<void> _promptForNewPin(
      BuildContext context, SettingsNotifier notifier) async {
    final l10n = AppLocalizations.of(context)!;
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;

    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget field(TextEditingController c, String label,
                  {bool autofocus = false}) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AdaptiveKeyboardTextField(
                  controller: c,
                  autofocus: autofocus,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: kSettingsPinMaxLength,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  // Letter-spacing drops with the longer maximum: at 10 an
                  // 8-digit pin overflows the 320-wide dialog field.
                  style: const TextStyle(fontSize: 24, letterSpacing: 6),
                  decoration: InputDecoration(
                    labelText: label,
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
              );

          return AlertDialog(
            title: Text(l10n.translate('set_pin')),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(first, l10n.translate('new_pin'), autofocus: true),
                  field(second, l10n.translate('confirm_pin')),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.translate('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  final a = first.text.trim();
                  if (!isValidSettingsPin(a)) {
                    setLocal(() => error = l10n.translate('pin_length_rule'));
                    return;
                  }
                  if (a != second.text.trim()) {
                    setLocal(() => error = l10n.translate('pins_do_not_match'));
                    return;
                  }
                  Navigator.pop(ctx, a);
                },
                child: Text(l10n.translate('save')),
              ),
            ],
          );
        },
      ),
    );

    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.
    if (pin == null) return;
    // Setting a pin arms the lock: an admin who just typed one twice means to
    // use it, and leaving it disarmed reads as "nothing happened".
    await notifier.setSettingsLock(enabled: true, pin: pin);
  }

  Widget _buildZSettingsContent(
    AppSettings settings,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('z_settings'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate('z_rules_server_managed'),
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        const _ZRulesView(),
        const SizedBox(height: 24),
        Text(
          l10n.translate('z_report_sections'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate('z_report_sections_hint'),
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              _reportBandRow(
                context,
                label: Text(l10n.translate('report_section_col'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                x: const Text('X',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                z: const Text('Z',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              for (final band in ZReportSection.values)
                _reportBandRow(
                  context,
                  label: Text(l10n.translate(band.l10nKey)),
                  x: kZOnlySections.contains(band)
                      ? const Checkbox(value: false, onChanged: null)
                      : Checkbox(
                          value: zBandShown(
                              band, settings.xReportHiddenSections),
                          onChanged: (v) =>
                              notifier.setXReportSectionShown(band, v ?? true),
                        ),
                  z: Checkbox(
                    value: zBandShown(band, settings.zReportHiddenSections),
                    onChanged: (v) =>
                        notifier.setZReportSectionShown(band, v ?? true),
                  ),
                ),
              const Divider(height: 1),
              _reportBandRow(
                context,
                label: Text(l10n.translate('report_skip_zero')),
                x: Checkbox(
                  value: settings.xReportSkipZero,
                  onChanged: (v) =>
                      notifier.setReportSkipZero(isX: true, value: v ?? false),
                ),
                z: Checkbox(
                  value: settings.zReportSkipZero,
                  onChanged: (v) =>
                      notifier.setReportSkipZero(isX: false, value: v ?? false),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.short_text_rounded),
              label: Text(l10n.translate('report_brief_x')),
              onPressed: () => notifier.setXReportHiddenSections([
                for (final band in ZReportSection.values)
                  if (!kBriefXSections.contains(band)) band.name,
              ]),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.notes_rounded),
              label: Text(l10n.translate('report_full_x')),
              onPressed: () => notifier.setXReportHiddenSections(const []),
            ),
          ],
        ),
      ],
    );
  }

  /// One row of the X / Z band table: a label, then the X and Z columns.
  Widget _reportBandRow(
    BuildContext context, {
    required Widget label,
    required Widget x,
    required Widget z,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: [
          Expanded(child: label),
          SizedBox(width: 56, child: Center(child: x)),
          SizedBox(width: 56, child: Center(child: z)),
        ],
      ),
    );
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final token in entry.value)
                  Builder(builder: (context) {
                    final desc = describePermission(token, l10n);
                    return SwitchListTile(
                      dense: true,
                      title: Text(desc.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: desc.subtitle.isEmpty
                          ? null
                          : Text(desc.subtitle,
                              style: TextStyle(
                                  fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      value: granted.contains(token),
                      onChanged: (v) => toggle(token, v),
                    );
                  }),
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        // Desktop only: there is no equivalent an app may set for itself
        // on Android or iOS, so the switch would be a lie there.
        if (AutostartService.isSupported) ...[
          const SizedBox(height: 12),
          _buildSwitchTile(
            context: context,
            icon: Icons.rocket_launch,
            title: l10n.translate('open_on_startup'),
            subtitle: l10n.translate('open_on_startup_subtitle'),
            value: settings.openOnStartup,
            onChanged: (value) => notifier.setOpenOnStartup(value),
          ),
        ],
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        // Only meaningful while images are on — with images off there is
        // nothing for a label to sit on, so the choice would be a dead control.
        if (settings.showProductImages) ...[
          const SizedBox(height: 12),
          _buildLabelLayoutSelector(
            context: context,
            overlay: settings.productLabelOverlay,
            onChanged: (value) => notifier.setProductLabelOverlay(value),
          ),
        ],
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
        // Full-page mode only: with the category bar on screen there is
        // nothing for a back tile to return to, so the toggle would be dead.
        if (settings.categoryDisplayMode == CategoryDisplayMode.fullPage) ...[
          const SizedBox(height: 12),
          _buildSwitchTile(
            context: context,
            icon: Icons.arrow_back_rounded,
            title: l10n.translate('back_tile'),
            subtitle: l10n.translate('back_tile_subtitle'),
            value: settings.showBackTileInProductGrid,
            onChanged: (value) => notifier.setShowBackTileInProductGrid(value),
          ),
        ],
        const SizedBox(height: 12),
        _buildComponentGroupDisplayModeSelector(
          context: context,
          currentMode: settings.componentGroupDisplayMode,
          onChanged: (value) => notifier.setComponentGroupDisplayMode(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.star,
          title: l10n.translate('show_favorites_category'),
          subtitle: l10n.translate('show_favorites_category_subtitle'),
          value: settings.showFavoritesCategory,
          onChanged: (value) => notifier.setShowFavoritesCategory(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.history,
          title: l10n.translate('sort_by_last_used'),
          subtitle: l10n.translate('sort_by_last_used_subtitle'),
          value: settings.sortByLastUsed,
          onChanged: (value) => notifier.setSortByLastUsed(value),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        _buildSwitchTile(
          context: context,
          icon: Icons.search,
          title: l10n.translate('show_product_search'),
          subtitle: l10n.translate('show_product_search_subtitle'),
          value: settings.showProductSearch,
          onChanged: (value) => notifier.setShowProductSearch(value),
        ),
        // No field, nothing to focus — the auto-focus switch would do nothing.
        if (settings.showProductSearch) ...[
          const SizedBox(height: 16),
          _buildSwitchTile(
            context: context,
            icon: Icons.filter_center_focus,
            title: l10n.translate('auto_focus_product_search'),
            subtitle: l10n.translate('auto_focus_product_search_subtitle'),
            value: settings.autoFocusProductSearch,
            onChanged: (value) => notifier.setAutoFocusProductSearch(value),
          ),
        ],
        const SizedBox(height: 16),
        _buildSwitchTile(
          context: context,
          icon: Icons.dialpad,
          title: l10n.translate('numeric_keypad_beta'),
          subtitle: l10n.translate('numeric_keypad_beta_subtitle'),
          value: settings.numericKeypadBeta,
          onChanged: (value) => notifier.setNumericKeypadBeta(value),
          badge: 'BETA',
        ),
        const SizedBox(height: 16),
        _buildSwitchTile(
          context: context,
          icon: Icons.remove_shopping_cart_outlined,
          title: l10n.translate('show_cancelled_items_as_rows_title'),
          subtitle: l10n.translate('show_cancelled_items_as_rows_subtitle'),
          value: settings.showCancelledItemsAsRows,
          onChanged: (value) => notifier.setShowCancelledItemsAsRows(value),
        ),
      ],
    );
  }

  /// Restarts the order numbering the next order would draw from at #1 —
  /// the open session's, its Z's, or the manual counter, per the mode.
  Future<void> _confirmResetOrderNumber(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final orders = ref.read(orderServiceProvider);
    final mode = ref.read(settingsProvider).orderNumberResetMode;
    final session = await ref.read(sessionQueriesProvider).activeSessionOnTill();
    if (!context.mounted) return;
    if (session == null && mode != 'manual') {
      SnackBarHelper.showToast(l10n.translate('reset_order_number_no_session'), kind: ToastKind.info);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('reset_order_number')),
        content: Text(l10n.translate('reset_order_number_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.translate('reset_order_number')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await orders.resetOrderNumber(session?.id, mode: mode);
    SnackBarHelper.showToast(l10n.translate('reset_order_number_done'), kind: ToastKind.info);
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        // Fiscal, so admin only — a cashier must not be able to zero it.
        if (ref.watch(currentUserProvider)?.type.toLowerCase() == 'admin') ...[
          _ZeroPriceTvaField(
            rate: settings.zeroPriceTvaRate,
            onChanged: notifier.setZeroPriceTvaRate,
          ),
          const SizedBox(height: 12),
        ],
        _buildOrderTypeSelector(
          context: context,
          currentType: settings.defaultOrderType,
          onChanged: (value) => notifier.setDefaultOrderType(value),
        ),
        const SizedBox(height: 12),
        _buildOrderStatusSelector(
          context: context,
          // Governs BOTH cashier and waiter orders — waiter-created orders
          // now default to this same status (see server _waiterCreateOrder).
          currentStatus: settings.defaultOrderStatus,
          onChanged: (value) => notifier.setDefaultOrderStatus(value),
        ),
        const SizedBox(height: 12),
        _buildKdsStateSelector(
          context: context,
          currentState: settings.defaultKdsState,
          onChanged: (value) => notifier.setDefaultKdsState(value),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_outlined),
          title: Text(l10n.translate('kitchen_target_minutes')),
          subtitle: Text(l10n.translate('kitchen_target_minutes_subtitle')),
          trailing: DropdownButton<int>(
            value: settings.kitchenTargetMinutes,
            items: [
              for (final m in {
                0, 10, 15, 20, 25, 30, 40, 45, 60,
                settings.kitchenTargetMinutes,
              }.toList()..sort())
                DropdownMenuItem(
                  value: m,
                  child: Text(m == 0 ? l10n.translate('off') : '$m min'),
                ),
            ],
            onChanged: (m) {
              if (m != null) notifier.setKitchenTargetMinutes(m);
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.print_disabled,
          title: l10n.translate('print_waiter_paper'),
          subtitle: l10n.translate('print_waiter_paper_subtitle'),
          value: settings.printWaiterPaper,
          onChanged: (value) => notifier.setPrintWaiterPaper(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.receipt_long,
          title: l10n.translate('print_waiter_order_ticket'),
          subtitle: l10n.translate('print_waiter_order_ticket_subtitle'),
          // Sub-toggle of the master switch above; only has effect while
          // "print waiter paper" is on.
          value: settings.printWaiterOrderTicket,
          onChanged: (value) => notifier.setPrintWaiterOrderTicket(value),
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

        // ── Order number ─────────────────────────────────────────────────
        const SizedBox(height: 28),
        Text(
          l10n.translate('order_number_section'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.translate('order_number_section_hint'),
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.format_list_numbered,
          title: l10n.translate('show_order_number_in_lists'),
          subtitle: l10n.translate('show_order_number_in_lists_subtitle'),
          value: settings.showOrderNumberInLists,
          onChanged: (value) => notifier.setShowOrderNumberInLists(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.soup_kitchen_outlined,
          title: l10n.translate('show_order_number_on_kds'),
          subtitle: l10n.translate('show_order_number_on_kds_subtitle'),
          value: settings.showOrderNumberOnKds,
          onChanged: (value) => notifier.setShowOrderNumberOnKds(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.room_service_outlined,
          title: l10n.translate('show_order_number_on_waiter'),
          subtitle: l10n.translate('show_order_number_on_waiter_subtitle'),
          value: settings.showOrderNumberOnWaiter,
          onChanged: (value) => notifier.setShowOrderNumberOnWaiter(value),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.restart_alt,
              color: Theme.of(context).colorScheme.primary),
          title: Text(l10n.translate('order_number_reset_mode')),
          subtitle: Text(
            l10n.translate(
                'order_number_reset_mode_${settings.orderNumberResetMode}_hint'),
            style: const TextStyle(fontSize: 12),
          ),
          trailing: DropdownButton<String>(
            value: settings.orderNumberResetMode,
            onChanged: (v) {
              if (v != null) notifier.setOrderNumberResetMode(v);
            },
            items: [
              for (final mode in const ['session', 'z', 'manual'])
                DropdownMenuItem(
                  value: mode,
                  child: Text(l10n.translate('order_number_reset_mode_$mode')),
                ),
            ],
          ),
        ),
        if (ref.watch(currentUserProvider)?.type.toLowerCase() == 'admin' ||
            ref.watch(adminElevationProvider) != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: () => _confirmResetOrderNumber(context),
              icon: const Icon(Icons.restart_alt),
              label: Text(l10n.translate('reset_order_number')),
            ),
          ),
        ],

        // ── Payment & tickets ─────────────────────────────────────────────
        const SizedBox(height: 28),
        Text(
          l10n.translate('payment_and_tickets'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.touch_app_outlined,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('pay_button_tap'),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    l10n.translate('pay_button_tap_subtitle'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<PayButtonAction>(
          segments: [
            ButtonSegment(
              value: PayButtonAction.paymentScreen,
              icon: const Icon(Icons.point_of_sale),
              label: Text(l10n.translate('pay_open_payment_screen')),
            ),
            ButtonSegment(
              value: PayButtonAction.quickCash,
              icon: const Icon(Icons.bolt),
              label: Text(l10n.translate('pay_quick_cash')),
            ),
          ],
          selected: {settings.payButtonAction},
          onSelectionChanged: (selection) =>
              notifier.setPayButtonAction(selection.first),
        ),
        const SizedBox(height: 8),
        _buildQuickCashAmountsField(context, notifier),
        const SizedBox(height: 8),
        _buildDeliveryFeePresetsField(context, notifier),
        const SizedBox(height: 8),
        _buildNotePresetsField(context, notifier),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.call_split,
          title: l10n.translate('always_show_ticket_split'),
          subtitle: l10n.translate('always_show_ticket_split_subtitle'),
          value: settings.alwaysShowTicketSplit,
          onChanged: (v) => notifier.setAlwaysShowTicketSplit(v),
        ),
        const SizedBox(height: 8),
        _buildMaxSplitTicketsField(context, settings, notifier),
        // Tip dialog toggle intentionally hidden — full plumbing is still
        // wired (model field, runtime guard in `applyTipIfEnabled`, sync
        // payload, queue replay), the toggle is just removed so the
        // cashier can't enable it yet. Re-add this `_buildSwitchTile` to
        // turn the feature back on.

        // ── Validation rules ──────────────────────────────────────────────
        const SizedBox(height: 28),
        Text(
          l10n.translate('validation_rules'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.table_restaurant,
          title: l10n.translate('rule_require_table_dine_in_title'),
          subtitle: l10n.translate('rule_require_table_dine_in_subtitle'),
          value: settings.requireTableForDineIn,
          onChanged: (v) => notifier.setRequireTableForDineIn(v),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.room_service,
          title: l10n.translate('rule_require_waiter_dine_in_title'),
          subtitle: l10n.translate('rule_require_waiter_dine_in_subtitle'),
          value: settings.requireWaiterForDineIn,
          onChanged: (v) => notifier.setRequireWaiterForDineIn(v),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.person_pin_circle,
          title: l10n.translate('rule_require_customer_delivery_title'),
          subtitle: l10n.translate('rule_require_customer_delivery_subtitle'),
          value: settings.requireCustomerForDelivery,
          onChanged: (v) => notifier.setRequireCustomerForDelivery(v),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.location_on,
          title: l10n.translate('rule_require_delivery_address_title'),
          subtitle: l10n.translate('rule_require_delivery_address_subtitle'),
          value: settings.requireDeliveryAddress,
          onChanged: (v) => notifier.setRequireDeliveryAddress(v),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.table_restaurant,
          title: l10n.translate('auto_clear_table_after_paying_title'),
          subtitle: l10n.translate('auto_clear_table_after_paying_subtitle'),
          value: settings.autoClearTableAfterPaying,
          onChanged: (v) => notifier.setAutoClearTableAfterPaying(v),
        ),
        const SizedBox(height: 8),
        _buildSwitchTile(
          context: context,
          icon: Icons.soup_kitchen,
          title: l10n.translate('payment_completes_kitchen_title'),
          subtitle: l10n.translate('payment_completes_kitchen_subtitle'),
          value: settings.paymentCompletesKitchen,
          onChanged: (v) => notifier.setPaymentCompletesKitchen(v),
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      // Coupon toggle hidden alongside the button itself — same reasoning as
      // the tip entry below. The `case 'coupon':` branch in main_screen is
      // commented out, so the switch would have offered a toggle for something
      // that can never render. Restore both together.
      // 'coupon': (icon: Icons.discount, titleKey: 'coupon_button', subtitleKey: 'apply_coupons', visible: settings.showCouponButton, setVisible: notifier.setShowCouponButton),
      'discount': (icon: Icons.percent, titleKey: 'discount_button', subtitleKey: 'manual_discount', visible: settings.showDiscountButton, setVisible: notifier.setShowDiscountButton),
      'print': (icon: Icons.print, titleKey: 'print_button', subtitleKey: 'print_orders', visible: settings.showPrintButton, setVisible: notifier.setShowPrintButton),
      // A cashier who cannot cancel an order has nothing to gain from a
      // toggle for a button main_screen will refuse to render anyway.
      if (ref
          .watch(permissionServiceProvider)
          .hasPermission(Permissions.ordersCancel))
        'cancelOrder': (icon: Icons.cancel_outlined, titleKey: 'cancel_order_button', subtitleKey: 'cancel_saved_order', visible: settings.showCancelOrderButton, setVisible: notifier.setShowCancelOrderButton),
      // Same gate main_screen uses to render it.
      if (ref.watch(permissionServiceProvider).hasRefundPermission(Permissions.refundsCreate))
        'refund': (icon: Icons.assignment_return, titleKey: 'refund_button', subtitleKey: 'refund_button_hint', visible: settings.showRefundButton, setVisible: notifier.setShowRefundButton),
      'tags': (icon: Icons.label_outline, titleKey: 'tags_button', subtitleKey: 'tags_button_hint', visible: settings.showTagsButton, setVisible: notifier.setShowTagsButton),
      'reserve': (icon: Icons.event_available, titleKey: 'reserve_button', subtitleKey: 'reserve_button_hint', visible: settings.showReserveButton, setVisible: notifier.setShowReserveButton),
      'cashDrawer': (icon: Icons.point_of_sale, titleKey: 'cash_drawer_button', subtitleKey: 'open_cash_drawer', visible: settings.showCashDrawerButton, setVisible: notifier.setShowCashDrawerButton),
      'dailySummary': (icon: Icons.summarize, titleKey: 'daily_summary_button', subtitleKey: 'daily_report', visible: settings.showDailySummaryButton, setVisible: notifier.setShowDailySummaryButton),
      // Tip button toggle intentionally hidden — same reasoning as the
      // tip dialog toggle above. The `case 'tip':` branch in main_screen
      // checks `settings.showTipButton` which defaults to false, so the
      // button never renders. Restore this map entry to expose the toggle.
      'pay': (icon: Icons.payment, titleKey: 'pay_button', subtitleKey: 'process_payment', visible: settings.showPayButton, setVisible: notifier.setShowPayButton),
      'proceed': (icon: Icons.check_circle, titleKey: 'proceed_button', subtitleKey: 'save_order', visible: settings.showProceedButton, setVisible: notifier.setShowProceedButton),
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.translate('button_alignment'),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('button_alignment_subtitle'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SegmentedButton<ActionButtonAlignment>(
          segments: [
            ButtonSegment(
              value: ActionButtonAlignment.left,
              icon: const Icon(Icons.format_align_left),
              label: Text(l10n.translate('align_left')),
            ),
            ButtonSegment(
              value: ActionButtonAlignment.center,
              icon: const Icon(Icons.format_align_center),
              label: Text(l10n.translate('align_center')),
            ),
            ButtonSegment(
              value: ActionButtonAlignment.right,
              icon: const Icon(Icons.format_align_right),
              label: Text(l10n.translate('align_right')),
            ),
          ],
          selected: {settings.actionButtonAlignment},
          onSelectionChanged: (selection) =>
              notifier.setActionButtonAlignment(selection.first),
        ),
        const SizedBox(height: 24),
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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
            if (config == null) return SizedBox.shrink(key: ValueKey('unknown_$buttonKey'));

            return Card(
              key: ValueKey(buttonKey),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Icon(config.icon, color: config.visible ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
                title: Text(
                  l10n.translate(config.titleKey),
                  style: TextStyle(
                    color: config.visible ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  l10n.translate(config.subtitleKey),
                  style: TextStyle(
                    color: config.visible ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.outline,
                    fontSize: 12,
                  ),
                ),
                trailing: Switch(
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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
      ],
    );
  }

  /// Comma-separated note denominations. Parsed on submit / focus-loss rather
  /// than per keystroke: "1, 2, 5" passes through the states "1, " and "1, 2,"
  /// where a live parse would keep rewriting the list under the cursor.
  /// Money as somebody would type it: 15, not 15.0.
  static String _trimPreset(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  /// The shop's own one-tap order notes.
  ///
  /// Comma-separated because that is how the quick-cash amounts beside it
  /// already work, and one habit is easier than two. Notes may contain spaces,
  /// so unlike the amounts this splits on commas alone.
  Widget _buildNotePresetsField(
    BuildContext context,
    SettingsNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;

    void save(String raw) {
      final parsed = raw
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      notifier.setNotePresets(parsed);
      // Re-render what will actually be stored, so duplicates and stray commas
      // snap back rather than lingering as text that means nothing. Cleaned
      // here rather than read back: the save is async, and the state has not
      // landed yet by the time this line runs.
      final stored = <String>[];
      for (final note in parsed) {
        if (!stored.contains(note)) stored.add(note);
      }
      _notePresetsController.text = stored.join(', ');
    }

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
                const Icon(Icons.sticky_note_2_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translate('note_presets')),
                      Text(
                        l10n.translate('note_presets_subtitle'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveKeyboardTextField(
              controller: _notePresetsController,
              decoration: InputDecoration(
                hintText: l10n.translate('note_presets_hint'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onSubmitted: save,
              onEditingComplete: () => save(_notePresetsController.text),
              onTapOutside: (_) => save(_notePresetsController.text),
            ),
          ],
        ),
      ),
    );
  }

  /// One-tap delivery fees.
  Widget _buildDeliveryFeePresetsField(
    BuildContext context,
    SettingsNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;

    void save(String raw) {
      final parsed = raw
          .split(RegExp(r'[,;\s]+'))
          .map((e) => double.tryParse(e.trim().replaceAll(',', '.')))
          .whereType<double>()
          .where((e) => e >= 0)
          .toList();
      notifier.setDeliveryFeePresets(parsed);
      final stored = parsed.toSet().toList()..sort();
      _deliveryFeePresetsController.text =
          stored.map(_trimPreset).join(', ');
    }

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
                const Icon(Icons.delivery_dining),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translate('delivery_fee_presets')),
                      Text(
                        l10n.translate('delivery_fee_presets_subtitle'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveKeyboardTextField(
              controller: _deliveryFeePresetsController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '10, 15, 20, 30',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onSubmitted: save,
              onEditingComplete: () => save(_deliveryFeePresetsController.text),
              onTapOutside: (_) => save(_deliveryFeePresetsController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCashAmountsField(
    BuildContext context,
    SettingsNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;

    void save(String raw) {
      final parsed = raw
          .split(RegExp(r'[,;\s]+'))
          .map((e) => int.tryParse(e.trim()) ?? 0)
          .where((e) => e > 0)
          .toList();
      notifier.setQuickCashAmounts(parsed);
      // Re-render whatever was actually stored, so an unparseable entry
      // snaps back instead of lingering as text that means nothing.
      _quickCashController.text =
          (parsed.isEmpty ? const [200, 100, 50, 20] : (parsed..sort((a, b) => b.compareTo(a))))
              .join(', ');
    }

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.translate('quick_cash_amounts')),
                      Text(
                        l10n.translate('quick_cash_amounts_subtitle'),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveKeyboardTextField(
              controller: _quickCashController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: '200, 100, 50, 20',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onSubmitted: save,
              onEditingComplete: () => save(_quickCashController.text),
              onTapOutside: (_) => save(_quickCashController.text),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaxSplitTicketsField(
    BuildContext context,
    AppSettings settings,
    SettingsNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: const Icon(Icons.confirmation_number_outlined),
        title: Text(l10n.translate('max_split_tickets')),
        subtitle: Text(l10n.translate('max_split_tickets_subtitle')),
        trailing: SizedBox(
          width: 150,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: settings.maxSplitTickets > 2
                    ? () => notifier.setMaxSplitTickets(settings.maxSplitTickets - 1)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '${settings.maxSplitTickets}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: settings.maxSplitTickets < 50
                    ? () => notifier.setMaxSplitTickets(settings.maxSplitTickets + 1)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
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
    /// Optional chip beside the title — for marking a setting as unfinished,
    /// so nobody turns it on expecting it to be as solid as the rest.
    String? badge,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: Icon(icon),
        title: badge == null
            ? Text(title)
            : Row(
                children: [
                  Flexible(child: Text(title)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onTap: () => onChanged('ONHOLD'),
                ),
                // PENDING / PREPARING intentionally NOT offered: they are
                // non-terminal, and the KDS micro-state machine is LAN-local —
                // a partially-completed order never fires the all-same-status
                // cloud sync, so a non-terminal default would leave the backend
                // stuck showing PENDING/PREPARING. Only terminal (COMPLETED) and
                // the KDS-exempt ONHOLD are safe defaults. See kds_changes.md.
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


  /// The kitchen state each PRODUCT starts in when an order is sent to the
  /// kitchen. Distinct from [_buildOrderStatusSelector]: the order header is
  /// born COMPLETED (cloud-terminal), while the live kitchen flow
  /// (PENDING → PREPARING → COMPLETED) runs on the products and is what the KDS
  /// drives. Both PENDING and PREPARING are safe here — unlike the order-level
  /// default — because the KDS drives products to a terminal state locally.
  Widget _buildKdsStateSelector({
    required BuildContext context,
    required String currentState,
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
                const Icon(Icons.kitchen),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('default_kds_state'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      l10n.translate('default_kds_state_subtitle'),
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                  icon: Icons.pending_actions,
                  label: l10n.translate('pending'),
                  value: 'PENDING',
                  currentValue: currentState,
                  color: Colors.orange,
                  onTap: () => onChanged('PENDING'),
                ),
                _buildOrderStatusOption(
                  context: context,
                  icon: Icons.soup_kitchen,
                  label: l10n.translate('preparing'),
                  value: 'PREPARING',
                  currentValue: currentState,
                  color: Colors.blue,
                  onTap: () => onChanged('PREPARING'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Waiter orders now inherit `defaultOrderStatus` (the normal-flow default),
  // so the dedicated waiter-status selector was removed — see the Order
  // Defaults section and server `_waiterCreateOrder`.


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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onTap: () => onChanged('ONHOLD'),
                ),
                // PENDING / PREPARING intentionally NOT offered: they are
                // non-terminal, and the KDS micro-state machine is LAN-local —
                // a partially-completed order never fires the all-same-status
                // cloud sync, so a non-terminal default would leave the backend
                // stuck showing PENDING/PREPARING. Only terminal (COMPLETED) and
                // the KDS-exempt ONHOLD are safe defaults. See kds_changes.md.
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
              color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  onTap: () => onChanged('OTHER'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Where a product card's name and price go: under the image, or on it.
  ///
  /// Shown as two little pictures of the result rather than a switch — the
  /// difference is entirely visual, and "Overlay labels: on" tells nobody what
  /// their till is about to look like.
  Widget _buildLabelLayoutSelector({
    required BuildContext context,
    required bool overlay,
    required ValueChanged<bool> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.view_agenda_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('card_label_layout'),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(l10n.translate('card_label_layout_subtitle'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _labelLayoutOption(
              context: context,
              label: l10n.translate('label_below_image'),
              selected: !overlay,
              onTap: () => onChanged(false),
              preview: _cardPreview(theme, overlay: false),
            ),
            const SizedBox(width: 12),
            _labelLayoutOption(
              context: context,
              label: l10n.translate('label_over_image'),
              selected: overlay,
              onTap: () => onChanged(true),
              preview: _cardPreview(theme, overlay: true),
            ),
          ],
        ),
      ],
    );
  }

  Widget _labelLayoutOption({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Widget preview,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : null,
          ),
          child: Column(
            children: [
              preview,
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// A miniature of the card, to scale: the overlay sample is shorter, because
  /// that is the point of it.
  Widget _cardPreview(ThemeData theme, {required bool overlay}) {
    final image = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(Icons.image_outlined,
          size: 18, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
    );

    Widget bar(double width, {Color? color}) => Container(
          height: 4,
          width: width,
          decoration: BoxDecoration(
            color: color ?? theme.colorScheme.onSurface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        );

    if (overlay) {
      return SizedBox(
        height: 56,
        width: 64,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    bar(34, color: Colors.white),
                    const SizedBox(height: 3),
                    bar(20, color: Colors.white70),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 74,
      width: 64,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SizedBox(width: 64, child: image)),
          const SizedBox(height: 5),
          bar(40),
          const SizedBox(height: 4),
          bar(24),
        ],
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Card Size',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Size of product cards in the grid',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
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
                color: isSelected ? color.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentGroupDisplayModeSelector({
    required BuildContext context,
    required ComponentGroupDisplayMode currentMode,
    required ValueChanged<ComponentGroupDisplayMode> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.restaurant_menu),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.translate('component_group_display_mode'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        l10n.translate('component_group_display_subtitle'),
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
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildComponentGroupModeOption(
                    context: context,
                    icon: Icons.view_list,
                    label: l10n.translate('as_list'),
                    subtitle: l10n.translate('all_groups_at_once'),
                    value: ComponentGroupDisplayMode.list,
                    currentValue: currentMode,
                    onTap: () => onChanged(ComponentGroupDisplayMode.list),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildComponentGroupModeOption(
                    context: context,
                    icon: Icons.linear_scale,
                    label: l10n.translate('step_by_step'),
                    subtitle: l10n.translate('one_group_at_a_time'),
                    value: ComponentGroupDisplayMode.step,
                    currentValue: currentMode,
                    onTap: () => onChanged(ComponentGroupDisplayMode.step),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComponentGroupModeOption({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subtitle,
    required ComponentGroupDisplayMode value,
    required ComponentGroupDisplayMode currentValue,
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
            Icon(icon, size: 32, color: isSelected ? color : Theme.of(context).colorScheme.onSurfaceVariant),
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
                color: isSelected ? color.withValues(alpha: 0.8) : Theme.of(context).colorScheme.onSurfaceVariant,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                                : Theme.of(context).colorScheme.onSurfaceVariant,
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
      {'code': 'es', 'name': 'Español', 'flag': ''},
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  /// Validate + persist the server port. Rejects the privileged range
  /// (< 1024, which includes port 80): those are reserved/require admin on
  /// Windows (http.sys) and are the usual cause of "server won't bind" and the
  /// cross-service 403s a waiter/KDS hits when they land on port 80 instead of
  /// the POS.
  void _saveServerPort(SettingsNotifier notifier, String value) {
    final port = int.tryParse(value.trim());
    if (port == null || port <= 0 || port >= 65536) return;
    if (port < 1024) {
      if (mounted) {
        SnackBarHelper.showToast('Port $port is reserved — use a port ≥ 1024 (e.g. 8080).', kind: ToastKind.warning);
      }
      return;
    }
    notifier.setServerPort(port);
  }

  Widget _buildServerSettingsContent(
    AppSettings settings,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final isAdmin =
        ref.watch(currentUserProvider)?.type.toLowerCase() == 'admin';
    final portController = _portController;
    final passwordController = _serverPasswordController;

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
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
        const SizedBox(height: 12),

        // SSE real-time listener — admin only, off by default.
        if (isAdmin) ...[
          _buildSwitchTile(
            context: context,
            icon: Icons.sensors,
            title: l10n.translate('sse_listener'),
            subtitle: l10n.translate('sse_listener_subtitle'),
            value: settings.sseEnabled,
            onChanged: (value) => notifier.setSseEnabled(value),
          ),
          // Is the push actually working? Without this the only answer was in
          // the log file: the service reconnects silently, so a till that had
          // not been pushed an order in hours looked exactly like a quiet one.
          if (settings.sseEnabled) ...[
            const SizedBox(height: 8),
            const _SseStatusTile(),
          ],
          const SizedBox(height: 12),
        ],

        // Waiter app dashboard: show or hide the owed/collected money
        // fields. Off = backend strips them from the response.
        _buildSwitchTile(
          context: context,
          icon: Icons.visibility,
          title: l10n.translate('waiter_dashboard_show_owed'),
          subtitle: l10n.translate('waiter_dashboard_show_owed_subtitle'),
          value: settings.waiterDashboardShowOwed,
          onChanged: (value) => notifier.setWaiterDashboardShowOwed(value),
        ),
        const SizedBox(height: 12),

        // Call a waiter's phone from the till. The ring-style switch only
        // matters once calls are on, so it is nested rather than listed
        // beside it.
        _buildSwitchTile(
          context: context,
          icon: Icons.campaign,
          title: l10n.translate('waiter_call_enabled'),
          subtitle: l10n.translate('waiter_call_enabled_subtitle'),
          value: settings.waiterCallEnabled,
          onChanged: (value) => notifier.setWaiterCallEnabled(value),
        ),
        if (settings.waiterCallEnabled) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 24),
            child: _buildSwitchTile(
              context: context,
              icon: Icons.notifications_active,
              title: l10n.translate('waiter_call_ring_until_dismissed'),
              subtitle:
                  l10n.translate('waiter_call_ring_until_dismissed_subtitle'),
              value: settings.waiterCallRingUntilDismissed,
              onChanged: (value) =>
                  notifier.setWaiterCallRingUntilDismissed(value),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Kitchen feedback on the waiter phones — each push is its own switch
        // so a noisy kitchen can keep "ready" while muting the rest.
        _buildSwitchTile(
          context: context,
          icon: Icons.soup_kitchen,
          title: l10n.translate('waiter_show_kitchen_status'),
          subtitle: l10n.translate('waiter_show_kitchen_status_subtitle'),
          value: settings.waiterShowKitchenStatus,
          onChanged: (value) => notifier.setWaiterShowKitchenStatus(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.room_service,
          title: l10n.translate('waiter_notify_ready'),
          subtitle: l10n.translate('waiter_notify_ready_subtitle'),
          value: settings.waiterNotifyReady,
          onChanged: (value) => notifier.setWaiterNotifyReady(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.cancel_outlined,
          title: l10n.translate('waiter_notify_canceled'),
          subtitle: l10n.translate('waiter_notify_canceled_subtitle'),
          value: settings.waiterNotifyCanceled,
          onChanged: (value) => notifier.setWaiterNotifyCanceled(value),
        ),
        const SizedBox(height: 12),
        _buildSwitchTile(
          context: context,
          icon: Icons.remove_shopping_cart,
          title: l10n.translate('waiter_notify_rupture'),
          subtitle: l10n.translate('waiter_notify_rupture_subtitle'),
          value: settings.waiterNotifyRupture,
          onChanged: (value) => notifier.setWaiterNotifyRupture(value),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 12),
                AdaptiveKeyboardTextField(
                  controller: portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '8080',
                    helperText: 'Press Enter to save. Avoid port 80 (reserved).',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  // Save on submit / focus-loss, NOT on every keystroke: the
                  // controller is rebuilt each frame, so saving mid-typing could
                  // persist a half-typed value (e.g. "80" while typing "8080").
                  onSubmitted: (value) => _saveServerPort(notifier, value),
                  onTapOutside: (_) => _saveServerPort(notifier, portController.text),
                  onEditingComplete: () =>
                      _saveServerPort(notifier, portController.text),
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
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 12),
                AdaptiveKeyboardTextField(
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
                          // The host name survives DHCP changing the IP, so it
                          // is the address to hand out on Windows networks.
                          // Some Android/TV browsers can't resolve bare host
                          // names, hence the IP stays listed below.
                          if (_hostName.isNotEmpty)
                            Builder(builder: (context) {
                              final hostUrl =
                                  'http://$_hostName:${serverService.port}';
                              return Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      'Host: $hostUrl',
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Copy host URL',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 32, minHeight: 32),
                                    onPressed: () {
                                      Clipboard.setData(
                                          ClipboardData(text: hostUrl));
                                      SnackBarHelper.showToast(
                                          'URL copied to clipboard',
                                          kind: ToastKind.info,
                                          duration: const Duration(seconds: 1));
                                    },
                                  ),
                                ],
                              );
                            }),
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
                                        SnackBarHelper.showToast('URL copied to clipboard', kind: ToastKind.info, duration: Duration(seconds: 1));
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          // Embedded KDS web app — open this URL in any browser
                          // or on a TV to get the live kitchen board (no install).
                          FutureBuilder<String>(
                            future: DiscoveryService.getLocalIp(),
                            builder: (context, snapshot) {
                              final ip = snapshot.data ?? 'loading...';
                              final ipKdsUrl =
                                  'http://$ip:${serverService.port}/kds';
                              final kdsUrl = _hostName.isNotEmpty
                                  ? 'http://$_hostName:${serverService.port}/kds'
                                  : ipKdsUrl;
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.desktop_windows_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'KDS screen — open in a browser / TV',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600),
                                          ),
                                          SelectableText(
                                            kdsUrl,
                                            style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 13),
                                          ),
                                          if (kdsUrl != ipKdsUrl)
                                            SelectableText(
                                              ipKdsUrl,
                                              style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if (snapshot.hasData)
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 18),
                                        tooltip: 'Copy KDS URL',
                                        onPressed: () {
                                          Clipboard.setData(
                                              ClipboardData(text: kdsUrl));
                                          SnackBarHelper.showToast('KDS URL copied', kind: ToastKind.info, duration: Duration(seconds: 1));
                                        },
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Fallback picker: if the machine has more than one
                          // usable address (extra NIC, VPN, virtual adapter),
                          // list the others so the user can copy the right one
                          // when auto-detection guesses wrong.
                          FutureBuilder<List<String>>(
                            future: DiscoveryService.getLocalIpCandidates(),
                            builder: (context, snap) {
                              final all = snap.data ?? const <String>[];
                              if (all.length < 2) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Other addresses (tap to copy):',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: all.skip(1).map((ip) {
                                        final u = 'http://$ip:${serverService.port}';
                                        return ActionChip(
                                          label: Text(ip,
                                              style: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 12)),
                                          onPressed: () {
                                            Clipboard.setData(
                                                ClipboardData(text: u));
                                            SnackBarHelper.showToast('Copied $u', kind: ToastKind.info, duration: const Duration(seconds: 1));
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ),
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
                                SnackBarHelper.showToast(l10n.translate('server_stopped'), kind: ToastKind.info);
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
                                  SnackBarHelper.showToast(l10n.translate('server_started'), kind: ToastKind.info);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  SnackBarHelper.showToast('${l10n.translate('server_start_failed')}: $e', kind: ToastKind.error);
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

  // ── Session Rules (read-only, configured by server) ──────────────────

  Widget _buildSessionRulesContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rules = ref.watch(sessionRulesProvider);
    final cs = Theme.of(context).colorScheme;

    String hourLabel(int? h) =>
        h == null ? '—' : '${h.toString().padLeft(2, '0')}:00';
    String minutesLabel(int? m) => m == null ? '—' : '$m min';
    String countLabel(int? n) => n == null ? '—' : '$n';

    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            Text(value,
                style: TextStyle(
                    color: value == '—' ? cs.outline : cs.primary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.translate('session_rules'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.translate('session_rules_subtitle'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row(l10n.translate('rule_min_start_hour'),
                    hourLabel(rules.minStartHour)),
                const Divider(height: 1),
                row(l10n.translate('rule_cant_open_after_hour'),
                    hourLabel(rules.cantOpenAfterHour)),
                const Divider(height: 1),
                row(l10n.translate('rule_max_session_duration'),
                    minutesLabel(rules.maxSessionDurationMinutes)),
                const Divider(height: 1),
                row(l10n.translate('rule_max_end_hour'),
                    hourLabel(rules.maxEndHour)),
                const Divider(height: 1),
                row(l10n.translate('rule_max_sessions_per_day'),
                    countLabel(rules.maxSessionsPerUserPerDay)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: cs.outline),
            const SizedBox(width: 6),
            Text(
              l10n.translate('session_rules_server_note'),
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ],
        ),
      ],
    );
  }

  // ── About + update check ──────────────────────────────────────────────

  Widget _buildAboutContent(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final info = snap.data;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.translate('about'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoTile(
              context: context,
              icon: Icons.app_settings_alt,
              title: l10n.translate('app_name'),
              value: info?.appName ?? '—',
            ),
            const SizedBox(height: 8),
            _buildInfoTile(
              context: context,
              icon: Icons.tag,
              title: l10n.translate('version'),
              value: info?.version ?? '—',
            ),
            const SizedBox(height: 8),
            _buildInfoTile(
              context: context,
              icon: Icons.numbers,
              title: l10n.translate('build_number'),
              value: info?.buildNumber ?? '—',
            ),
            const SizedBox(height: 24),
            Text(
              l10n.translate('updates_section'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildUpdateStatusTile(context),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.autorenew,
              title: l10n.translate('auto_update'),
              subtitle: l10n.translate('auto_update_subtitle'),
              value: ref.watch(settingsProvider).autoUpdate,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setAutoUpdate(v),
            ),
            const SizedBox(height: 8),
            _buildCheckFrequencyTile(context),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.notifications_active_outlined,
              title: l10n.translate('updates_notify'),
              subtitle: l10n.translate('updates_notify_subtitle'),
              value: ref.read(updateServiceProvider).notify,
              onChanged: (v) async {
                await ref.read(updateServiceProvider).setNotify(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            _buildSwitchTile(
              context: context,
              icon: Icons.restart_alt,
              title: l10n.translate('updates_install_on_start'),
              subtitle: l10n.translate('updates_install_on_start_subtitle'),
              value: ref.read(updateServiceProvider).installOnStart,
              onChanged: (v) async {
                await ref.read(updateServiceProvider).setInstallOnStart(v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 8),
            _buildUpdatesServerTile(context),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _runUpdateCheck(context),
              icon: const Icon(Icons.system_update_alt),
              label: Text(l10n.translate('check_for_updates_now')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 16),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUpdateStatusTile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = ref.watch(updateProvider);
    final last = ref.read(updateServiceProvider).lastCheck;
    final version = s.version ?? '';

    final String status;
    if (s.isDownloading) {
      status = l10n.translate('updates_downloading_short').replaceAll('{0}', version);
    } else if (s.updateReady) {
      status = l10n.translate('updates_downloaded_short').replaceAll('{0}', version);
    } else if (s.hasUpdate) {
      status = l10n.translate('updates_available_short').replaceAll('{0}', version);
    } else {
      status = l10n.translate('updates_up_to_date_short');
    }
    final lastText = last == null
        ? l10n.translate('never')
        : '${_two(last.day)}/${_two(last.month)}/${last.year} '
            '${_two(last.hour)}:${_two(last.minute)}';

    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        leading: s.isBusy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.info_outline),
        title: Text('${l10n.translate('updates_status')}: $status'),
        subtitle: Text('${l10n.translate('updates_last_check')}: $lastText'),
        trailing: Wrap(
          spacing: 8,
          children: [
            if (s.hasUpdate && !s.updateReady && !s.isDownloading)
              OutlinedButton(
                onPressed: () => ref.read(updateProvider.notifier).startDownload(),
                child: Text(l10n.translate('updates_download_now')),
              ),
            if (s.updateReady)
              FilledButton(
                onPressed: () => showUpdateDialog(context,
                    isMandatory: s.updateRequired),
                child: Text(l10n.translate('update_install_now')),
              ),
            if (s.updateReady)
              OutlinedButton(
                onPressed: () async {
                  await ref.read(updateProvider.notifier).discardDownload();
                  if (!context.mounted) return;
                  SnackBarHelper.showToast(
                      l10n.translate('updates_download_deleted'),
                      kind: ToastKind.success);
                },
                child: Text(l10n.translate('updates_delete_download')),
              ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  Widget _buildCheckFrequencyTile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.read(updateServiceProvider);
    const labels = {
      0: 'updates_manual_only',
      1: 'updates_every_hour',
      6: 'updates_every_6h',
      12: 'updates_every_12h',
      24: 'updates_daily',
      168: 'updates_weekly',
    };
    final current = UpdateConfig.checkHoursChoices.contains(service.checkHours)
        ? service.checkHours
        : UpdateConfig.defaultCheckHours;
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(l10n.translate('updates_check_frequency')),
        subtitle: Text(l10n.translate('updates_check_frequency_subtitle')),
        trailing: DropdownButton<int>(
          value: current,
          underline: const SizedBox.shrink(),
          items: [
            for (final h in UpdateConfig.checkHoursChoices)
              DropdownMenuItem(value: h, child: Text(l10n.translate(labels[h]!))),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await service.setCheckHours(v);
            if (mounted) setState(() {});
            // A shorter interval may make a check due right away.
            ref.read(updateProvider.notifier).maybeCheck();
          },
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(
          value,
          style: const TextStyle(
              fontFamily: 'monospace', fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildUpdatesServerTile(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final service = ref.read(updateServiceProvider);
    final url = service.baseUrl;
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.3),
      child: ListTile(
        leading: const Icon(Icons.dns),
        title: Text(l10n.translate('updates_server')),
        subtitle: Text(
          '${url.isEmpty ? l10n.translate('updates_server_not_set') : url}'
          '${service.usesDefaultBaseUrl ? ' (${l10n.translate('updates_server_default')})' : ''}\n'
          '${l10n.translate('updates_app_name')}: ${service.appSlug}',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        trailing: const Icon(Icons.lock_outline),
        onTap: () => _editUpdatesServer(context),
      ),
    );
  }

  /// Field is locked with the till's local date as yyyymmdd — a technician
  /// password that rotates daily, not real security.
  Future<void> _editUpdatesServer(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final expected = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';

    final pwdCtrl = TextEditingController();
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('updates_server')),
        content: AdaptiveKeyboardTextField(
          controller: pwdCtrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: l10n.translate('password')),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim() == expected),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pwdCtrl.text.trim() == expected),
            child: Text(l10n.translate('ok')),
          ),
        ],
      ),
    );
    final typed = pwdCtrl.text;
    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.
    if (unlocked != true) {
      if (unlocked == false && context.mounted && typed.isNotEmpty) {
        SnackBarHelper.showToast(l10n.translate('updates_server_wrong_password'), kind: ToastKind.error);
      }
      return;
    }
    if (!context.mounted) return;

    final service = ref.read(updateServiceProvider);
    final urlCtrl = TextEditingController(
        text: service.usesDefaultBaseUrl ? '' : service.baseUrl);
    final appCtrl = TextEditingController(text: service.appSlug);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('updates_server')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdaptiveKeyboardTextField(
                controller: urlCtrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  hintText: UpdateConfig.defaultBaseUrl,
                ),
              ),
              const SizedBox(height: 12),
              AdaptiveKeyboardTextField(
                controller: appCtrl,
                decoration: InputDecoration(
                  labelText: l10n.translate('updates_app_name'),
                  hintText: UpdateConfig.defaultAppSlug,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('save')),
          ),
        ],
      ),
    );
    final url = urlCtrl.text.trim();
    final app = appCtrl.text.trim().toLowerCase();
    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.
    if (saved != true) return;

    final uri = Uri.tryParse(url);
    final String? invalidKey;
    if (url.isNotEmpty &&
        (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http'))) {
      invalidKey = 'updates_server_invalid';
    } else if (app.isNotEmpty && !RegExp(r'^[a-z0-9_-]+$').hasMatch(app)) {
      invalidKey = 'updates_app_name_invalid';
    } else {
      invalidKey = null;
    }
    if (invalidKey != null) {
      if (!context.mounted) return;
      SnackBarHelper.showToast(l10n.translate(invalidKey), kind: ToastKind.error);
      return;
    }
    await service.setBaseUrl(url);
    await service.setAppSlug(app);
    if (mounted) setState(() {});
  }

  Future<void> _runUpdateCheck(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    SnackBarHelper.showToast(l10n.translate('checking_for_updates'), kind: ToastKind.info, duration: const Duration(seconds: 2));

    // Signed update check against the caisse212-updates service (see
    // UpdateService); macOS/iOS are skipped inside the service.
    if (!kIsWeb &&
        (Platform.isAndroid ||
            Platform.isWindows ||
            Platform.isMacOS ||
            Platform.isLinux)) {
      final notifier = ref.read(updateProvider.notifier);
      final found = await notifier.checkForUpdates();
      if (!context.mounted) return;
      if (found == null) {
        SnackBarHelper.showToast(l10n.translate('update_server_unreachable'), kind: ToastKind.error);
      } else if (found && ref.read(updateProvider).hasUpdate) {
        showUpdateDialog(context,
            isMandatory: ref.read(updateProvider).updateRequired);
      } else {
        SnackBarHelper.showToast(l10n.translate('app_up_to_date'), kind: ToastKind.success);
      }
      return;
    }
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

  // ── CSV export ────────────────────────────────────────────────────────────

  Future<void> _showExportCsvDialog() async {
    final columns = await showDialog<List<_CsvColumnDef>>(
      context: context,
      builder: (_) => const _ExportCsvDialog(),
    );
    if (columns == null || !mounted) return;
    await _exportProductsCsv(columns);
  }

  Future<void> _exportProductsCsv(List<_CsvColumnDef> columns) async {
    final enabled = columns.where((c) => c.enabled).toList();
    if (enabled.isEmpty) return;

    try {
      final all = await ref.read(catalogueRepositoryProvider).allProducts();
      // Export only products that carry an MBW code — not the whole catalog.
      final products = all
          .where((p) =>
              p.isActive && (p.mbwCode != null && p.mbwCode!.trim().isNotEmpty))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final sb = StringBuffer();
      sb.writeln(enabled.map((c) => _csvEscape(c.header)).join(','));
      for (final p in products) {
        final row = enabled.map((c) => switch (c.key) {
          'id'          => p.id.toString(),
          'mbw'         => _csvEscape(p.mbwCode ?? ''),
          'name'        => _csvEscape(p.name),
          'description' => _csvEscape(p.description ?? ''),
          'price'       => p.price.toStringAsFixed(2),
          _             => '',
        });
        sb.writeln(row.join(','));
      }

      Directory? dir;
      try { dir = await getDownloadsDirectory(); } catch (_) {}
      dir ??= await getApplicationDocumentsDirectory();

      final ts = DateTime.now();
      final stamp =
          '${ts.year}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}'
          '_${ts.hour.toString().padLeft(2, '0')}${ts.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}${Platform.pathSeparator}products_$stamp.csv');
      await file.writeAsString(sb.toString());

      if (mounted) {
        SnackBarHelper.showToast('Exported ${products.length} products → ${file.path}', kind: ToastKind.success, duration: const Duration(seconds: 6));
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('Export failed: $e', kind: ToastKind.error);
      }
    }
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
            AdaptiveKeyboardTextField(
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
                              // The segment hues are picked dark so white reads
                              // on the bar; as loose TEXT on a dark surface the
                              // same hue disappears, so lift it here only.
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Color.lerp(color, Colors.white, 0.45)
                                  : color),
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
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
          child: AdaptiveKeyboardTextField(
            enabled: !_cartHasItems,
            initialValue: _draft.prefix,
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
                  SnackBarHelper.showToast(AppLocalizations.of(context)!.translate('scale_config_saved'), kind: ToastKind.success);
                },
          icon: const Icon(Icons.save),
          label: Text(l10n.translate('save')),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        ),

        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),

        // ── Export Products CSV ──────────────────────────────────────
        const Text('Export Products CSV',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          'Choose which columns to include, set their order and header names, then save as CSV.',
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showExportCsvDialog,
          icon: const Icon(Icons.table_chart_outlined),
          label: const Text('Configure & Export'),
        ),
      ],
    );
  }
}

double _pow10(int n) {
  double result = 1.0;
  for (int i = 0; i < n; i++) {
    result *= 10.0;
  }
  return result;
}

// ─── CSV export helpers ──────────────────────────────────────────────────────

String _csvEscape(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

class _CsvColumnDef {
  final String key;
  String header;
  bool enabled = true;
  _CsvColumnDef({required this.key, required this.header});
}

class _ExportCsvDialog extends StatefulWidget {
  const _ExportCsvDialog();

  @override
  State<_ExportCsvDialog> createState() => _ExportCsvDialogState();
}

class _ExportCsvDialogState extends State<_ExportCsvDialog> {
  late final List<_CsvColumnDef> _columns;
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _columns = [
      _CsvColumnDef(key: 'id',          header: 'ID'),
      _CsvColumnDef(key: 'mbw',         header: 'MBW'),
      _CsvColumnDef(key: 'name',        header: 'Name'),
      _CsvColumnDef(key: 'description', header: 'Description'),
      _CsvColumnDef(key: 'price',       header: 'Price'),
    ];
    _controllers = {
      for (final c in _columns) c.key: TextEditingController(text: c.header),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anyEnabled = _columns.any((c) => c.enabled);

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.table_chart_outlined),
        SizedBox(width: 8),
        Text('Export Products CSV'),
      ]),
      content: SizedBox(
        width: 500,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Drag  ≡  to reorder. Uncheck to exclude. Edit the header name.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ReorderableListView(
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _columns.removeAt(oldIndex);
                    _columns.insert(newIndex, item);
                  });
                },
                children: [
                  for (int i = 0; i < _columns.length; i++)
                    _ColumnRow(
                      key: ValueKey(_columns[i].key),
                      index: i,
                      col: _columns[i],
                      controller: _controllers[_columns[i].key]!,
                      onToggle: (v) => setState(() => _columns[i].enabled = v),
                      onHeaderChanged: (v) => _columns[i].header = v,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: anyEnabled ? () => Navigator.pop(context, _columns) : null,
          icon: const Icon(Icons.download),
          label: const Text('Export'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _ColumnRow extends StatelessWidget {
  final int index;
  final _CsvColumnDef col;
  final TextEditingController controller;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onHeaderChanged;

  const _ColumnRow({
    super.key,
    required this.index,
    required this.col,
    required this.controller,
    required this.onToggle,
    required this.onHeaderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.drag_handle, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Checkbox(value: col.enabled, onChanged: (v) => onToggle(v ?? false)),
          const SizedBox(width: 4),
          Expanded(
            child: AdaptiveKeyboardTextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: col.key,
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: onHeaderChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// The terminal's Z rules as the server set them, and the business day they
/// are measured from. Read-only: they are edited in the back office.
class _ZRulesView extends ConsumerWidget {
  const _ZRulesView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final rules = ref.watch(sessionRulesProvider);
    final day = ref.watch(businessDayProvider);
    final open = ref.watch(currentZProvider);
    String orNone(String? v) =>
        (v == null || v.isEmpty) ? l10n.translate('z_rule_none') : v;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Text(value,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ]),
        );
    final start = '${day.startHour.toString().padLeft(2, '0')}:00';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          row(l10n.translate('z_current'),
              open == null ? l10n.translate('no_open_z') : ZService.displayName(open)),
          row(l10n.translate('business_day'),
              ref.read(businessDayProvider.notifier).currentZDay()),
          row(l10n.translate('z_day_start_hour'), start),
          row(l10n.translate('timezone'), orNone(day.timezone)),
          const Divider(height: 20),
          row(l10n.translate('z_open_mode'), orNone(rules.zOpenMode ?? 'AUTO')),
          row(l10n.translate('z_cant_open_after'), orNone(rules.zCantOpenAfter)),
          row(l10n.translate('z_close_mode'), orNone(rules.zCloseMode ?? 'MANUAL')),
          row(l10n.translate('z_auto_close_after'), orNone(rules.zAutoCloseAfter)),
          row(l10n.translate('z_earliest_close_time'),
              orNone(rules.zEarliestCloseTime)),
        ]),
      ),
    );
  }
}

class _SseStatusTile extends ConsumerStatefulWidget {
  const _SseStatusTile();

  @override
  ConsumerState<_SseStatusTile> createState() => _SseStatusTileState();
}

class _SseStatusTileState extends ConsumerState<_SseStatusTile> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The status object only changes on a state change or a heartbeat (~25s).
    // The "last frame" age has to keep counting between those, or a stalled
    // pipe reads as fresh for as long as nothing happens.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _ago(BuildContext context, DateTime? at) {
    final l10n = AppLocalizations.of(context)!;
    if (at == null) return l10n.translate('sse_never');
    final d = DateTime.now().difference(at);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<SseStatus>(
      valueListenable: ref.watch(sseServiceProvider).status,
      builder: (context, status, _) {
        final (Color color, String labelKey) = switch (status.state) {
          SseConnectionState.live => (Colors.green, 'sse_state_live'),
          SseConnectionState.connecting =>
            (Colors.amber, 'sse_state_connecting'),
          SseConnectionState.retrying =>
            (Colors.orange, 'sse_state_retrying'),
          SseConnectionState.rejected => (cs.error, 'sse_state_rejected'),
          SseConnectionState.stopped => (cs.outline, 'sse_state_stopped'),
        };

        // A stalled pipe: still nominally live, but the server's 25s heartbeat
        // has not arrived. Said plainly rather than left for the operator to
        // infer from a timestamp.
        final stale = status.state == SseConnectionState.live &&
            status.lastFrameAt != null &&
            DateTime.now().difference(status.lastFrameAt!).inSeconds > 40;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: stale ? Colors.orange : color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.translate(stale ? 'sse_state_stalled' : labelKey),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    '${l10n.translate('sse_last_frame')}: '
                    '${_ago(context, status.lastFrameAt)}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              if (status.detail != null) ...[
                const SizedBox(height: 6),
                Text(
                  status.detail!,
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '${l10n.translate('sse_events_received')}: ${status.eventCount}'
                '   \u00b7   ${l10n.translate('sse_attempts')}: ${status.attempts}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Admin field for the TVA rate given to open-price (catalogue price 0)
/// products. Its own state so a settings rebuild does not reset the caret
/// mid-typing.
class _ZeroPriceTvaField extends StatefulWidget {
  final double rate;
  final ValueChanged<double> onChanged;

  const _ZeroPriceTvaField({required this.rate, required this.onChanged});

  @override
  State<_ZeroPriceTvaField> createState() => _ZeroPriceTvaFieldState();
}

class _ZeroPriceTvaFieldState extends State<_ZeroPriceTvaField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.rate));

  static String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: ListTile(
        leading: const Icon(Icons.percent),
        title: Text(l10n.translate('zero_price_tva_rate')),
        subtitle: Text(l10n.translate('zero_price_tva_rate_subtitle')),
        trailing: SizedBox(
          width: 90,
          child: AdaptiveKeyboardTextField(
            controller: _controller,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              suffixText: '%',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (text) {
              final v = double.tryParse(text.replaceAll(',', '.'));
              widget.onChanged(v ?? 0);
            },
          ),
        ),
      ),
    );
  }
}
