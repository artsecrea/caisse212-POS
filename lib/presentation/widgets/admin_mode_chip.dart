import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../services/activity_log_service.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

/// A small AppBar chip that lets a non-admin temporarily elevate to admin
/// privileges by entering an admin's username + password. While elevated,
/// every `PermissionService.hasPermission` check returns true. Tap again to
/// drop. Both transitions are recorded in the activity log.
class AdminModeChip extends ConsumerWidget {
  const AdminModeChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final elevation = ref.watch(adminElevationProvider);
    final currentUser = ref.watch(currentUserProvider);
    // The chip is meaningless for admins — they already bypass every check.
    // Only hide when nothing has been elevated, so an in-flight elevation
    // session still renders a way to revoke.
    if (elevation == null &&
        currentUser != null &&
        currentUser.type.toLowerCase() == 'admin') {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;

    if (elevation == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: ActionChip(
          avatar: const Icon(Icons.shield_outlined, size: 18),
          label: Text(l10n.translate('admin_mode')),
          onPressed: () => _promptElevate(context, ref),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final master = elevation.viaMasterPassword;
    final fg = master ? scheme.onTertiary : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: ActionChip(
        avatar: Icon(master ? Icons.admin_panel_settings : Icons.shield,
            size: 18, color: fg),
        backgroundColor: master ? scheme.tertiary : Colors.green.shade600,
        labelStyle: TextStyle(color: fg, fontWeight: FontWeight.w600),
        label: Text(
          l10n.translate(master ? 'master_password_active' : 'admin_mode_active')
              .replaceAll('{0}', elevation.adminUsername),
        ),
        onPressed: () => _revoke(context, ref),
      ),
    );
  }

  Future<void> _promptElevate(BuildContext context, WidgetRef ref) async {
    // Resolve everything that depends on `context` BEFORE any await or
    // provider mutation. Flipping `adminElevationProvider` rebuilds this
    // chip in place, which can leave the captured BuildContext attached to
    // a now-deactivated InheritedElement chain and trip a
    // _dependents.isEmpty assertion the next frame.
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showAdminCredentialDialog(context, ref);
    if (result == null) return;

    // Defer the provider flip until after the dialog's frame has fully
    // committed — same workaround the top_bar logout path uses to avoid
    // AnimatedDefaultTextStyle dirty-widget-in-wrong-scope crashes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminElevationProvider.notifier).state = result;
      final actor = ref.read(currentUserProvider);
      // Fire-and-forget the audit log — we don't want to await it while the
      // tree is mid-rebuild.
      ref.read(activityLogServiceProvider).logAdminElevationGranted(
            userId: actor?.id,
            username: actor?.effectiveDisplayName,
            adminUsername: result.adminUsername,
          );
      SnackBarHelper.showToast(l10n.translate('admin_mode_active')
                .replaceAll('{0}', result.adminUsername), kind: ToastKind.success);
    });
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(adminElevationProvider.notifier).state = null;
      final actor = ref.read(currentUserProvider);
      ref.read(activityLogServiceProvider).logAdminElevationRevoked(
            userId: actor?.id,
            username: actor?.effectiveDisplayName,
          );
      SnackBarHelper.showToast(l10n.translate('admin_mode_revoked'), kind: ToastKind.info);
    });
  }
}
