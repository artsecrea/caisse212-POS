import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../services/activity_log_service.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: ActionChip(
        avatar: const Icon(Icons.shield, size: 18, color: Colors.white),
        backgroundColor: Colors.green.shade600,
        labelStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600),
        label: Text(
          l10n.translate('admin_mode_active')
              .replaceAll('{0}', elevation.adminUsername),
        ),
        onPressed: () => _revoke(context, ref),
      ),
    );
  }

  Future<void> _promptElevate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showAdminCredentialDialog(context, ref);
    if (result == null) return;
    ref.read(adminElevationProvider.notifier).state = result;
    final actor = ref.read(currentUserProvider);
    await ref.read(activityLogServiceProvider).logAdminElevationGranted(
          userId: actor?.id,
          username: actor?.effectiveDisplayName,
          adminUsername: result.adminUsername,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            l10n.translate('admin_mode_active')
                .replaceAll('{0}', result.adminUsername),
          ),
        ),
      );
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    ref.read(adminElevationProvider.notifier).state = null;
    final actor = ref.read(currentUserProvider);
    await ref.read(activityLogServiceProvider).logAdminElevationRevoked(
          userId: actor?.id,
          username: actor?.effectiveDisplayName,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('admin_mode_revoked'))),
      );
    }
  }
}
