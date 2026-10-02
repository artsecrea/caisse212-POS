import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_elevation_provider.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart';
import '../services/api_service.dart';
import '../services/data_sync_service.dart';
import 'admin_auth.dart';
import 'app_localizations.dart';
import 'snackbar_helper.dart';

/// Disconnect the terminal from its tenant and wipe the local database.
///
/// This is the destructive one: it clears the stored server credentials (the
/// tenant password hash included) and drops every local table, so the terminal
/// comes back up needing to be re-provisioned. It exists for handing a machine
/// to another shop, or clearing a device before it leaves the premises.
///
/// Lives here rather than on a screen because it is now reachable from
/// Settings, and a copy of a wipe-everything routine is the last thing that
/// should be duplicated. Two confirmations stand in front of it — admin
/// credentials, then an explicit "are you sure" — and both are kept.
///
/// Returns true when the wipe ran. The caller is left on a dead terminal, so it
/// must navigate away; [runFullLogout] does that itself via the root navigator.
Future<bool> runFullLogout(BuildContext context, WidgetRef ref) async {
  final localizations = AppLocalizations.of(context);
  final prefs = ref.read(sharedPreferencesProvider);

  // Require an admin's credentials before wiping local + tenant data.
  final admin = await showAdminCredentialDialog(
    context,
    ref,
    title: localizations?.translate('full_logout') ?? 'Full Logout',
    description: localizations?.translate('full_logout_warning') ??
        'This will clear ALL data and disconnect from the server.',
    confirmLabel:
        localizations?.translate('verify_logout') ?? 'Verify & Logout',
    confirmColor: Colors.red,
  );
  if (admin == null) return false;
  if (!context.mounted) return false;

  // After password verification, an explicit confirmation: the credential
  // dialog proves who is asking, this one proves they meant to ask.
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(localizations?.translate('full_logout') ?? 'Full Logout'),
      content: Text(
        localizations?.translate('full_logout_confirm') ??
            'This will clear all server authentication data and local database.\n\n'
                'You will need to reconnect to the server or use demo mode again.\n\n'
                'Are you sure?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(localizations?.translate('cancel') ?? 'Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text(localizations?.translate('full_logout') ?? 'Full Logout'),
        ),
      ],
    ),
  );

  if (confirm != true) return false;

  try {
    // Clear current user and session.
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(currentSessionProvider.notifier).state = null;
    // Drop the active Z too — clearAllData wipes the zs table, so a lingering
    // in-memory Z would point at a deleted row.
    ref.read(currentZProvider.notifier).state = null;
    // Drop any admin-mode elevation so it doesn't survive a user swap.
    ref.read(adminElevationProvider.notifier).state = null;
    ref.read(orderProvider.notifier).clearOrder();

    final apiService = ApiService(prefs);
    // Best-effort; logs rather than throws if the server is unreachable.
    await apiService.logout();
    // clearAllAuthData, not clearAuthData: a full logout drops the tenant
    // password hash as well, which is what forces re-provisioning.
    await apiService.clearAllAuthData();

    final database = ref.read(databaseProvider);
    final syncService = DataSyncService(database, apiService);
    // Dump first. Anything not yet synced is about to be unrecoverable, and a
    // support case after an accidental wipe has nothing else to work from.
    await syncService.dumpDatabaseBeforeClear();
    await syncService.clearAllData();

    if (context.mounted) {
      SnackBarHelper.showToast(localizations?.translate('full_logout_done') ??
              'Logged out completely. All data cleared.', kind: ToastKind.warning);
      // Unfocus first to prevent AnimatedDefaultTextStyle
      // dirty-widget-in-wrong-scope errors during the route swap.
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context, rootNavigator: true)
              .pushNamedAndRemoveUntil('/tenant_login', (route) => false);
        }
      });
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      SnackBarHelper.showToast('${localizations?.translate('error') ?? 'Error'}: $e', kind: ToastKind.error);
    }
    return false;
  }
}
