import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../providers/admin_elevation_provider.dart';
import '../providers/database_providers.dart';
import '../providers/user_provider.dart';
import 'app_localizations.dart';
import 'user_display.dart';
import '../presentation/widgets/adaptive_text_field.dart';

/// Verifies admin credentials against the local user database.
///
/// Mirrors `profile_dialog._verifyCurrentPassword`:
/// 1. Find a user where `username == [username]` AND `type` (case-insensitive)
///    is `'admin'`.
/// 2. bcrypt-check [password] against that user's stored `password` hash.
/// 3. If that fails, also try `prefs.getString('custom_password_<id>')` —
///    matching how the login screen accepts a per-device custom hash.
///
/// Returns an [AdminElevation] identifying the admin on success, or `null` if
/// no admin user matches.
Future<AdminElevation?> verifyAdminCredentials(
  AppDatabase db,
  SharedPreferences prefs, {
  required String username,
  required String password,
}) async {
  // Defensive: this runs on any text the user types, including weird inputs
  // that have historically broken BCrypt / drift queries. Treat *any* failure
  // as "invalid credentials" rather than letting it bubble into a red screen.
  try {
    final trimmedUser = username.trim();
    final trimmedPw = password;
    if (trimmedUser.isEmpty || trimmedPw.isEmpty) return null;

    // Find any user with this username — then check it's an admin.
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(trimmedUser))
          ..limit(1))
        .getSingleOrNull();
    if (user == null) return null;
    if (user.type.toLowerCase() != 'admin') return null;

    // 1) bcrypt against the synced/DB password.
    try {
      if (BCrypt.checkpw(trimmedPw, user.password)) {
        return AdminElevation(adminId: user.id, adminUsername: user.username);
      }
    } catch (_) {/* malformed hash — fall through */}

    // 2) bcrypt against the per-device custom hash.
    final customHash = prefs.getString('custom_password_${user.id}');
    if (customHash != null && customHash.isNotEmpty) {
      try {
        if (BCrypt.checkpw(trimmedPw, customHash)) {
          return AdminElevation(adminId: user.id, adminUsername: user.username);
        }
      } catch (_) {/* malformed hash — fall through */}
    }

    return null;
  } catch (e, st) {
    debugPrint('verifyAdminCredentials failed: $e\n$st');
    return null;
  }
}

/// Whether a DB [User] row grants [permission] (admin type, exact token, or a
/// `:*` wildcard prefix). Mirrors `PermissionService.hasPermission` for a raw
/// row (no logged-in context).
bool userHasPermission(User user, String permission) {
  if (user.type.toLowerCase() == 'admin') return true;
  final perms = (user.permissions ?? '').split(',').map((p) => p.trim());
  if (perms.contains(permission)) return true;
  for (final p in perms) {
    if (p.endsWith(':*') && permission.startsWith(p.substring(0, p.length - 1))) {
      return true;
    }
  }
  return false;
}

/// Like [verifyAdminCredentials], but authorizes an admin **OR** any user who
/// holds [permission] (used for the login-screen Z gate where a "manager" is a
/// non-admin permission-holder). Returns an [AdminElevation] on success.
Future<AdminElevation?> verifyManagerCredentials(
  AppDatabase db,
  SharedPreferences prefs, {
  required String username,
  required String password,
  required String permission,
}) async {
  try {
    final trimmedUser = username.trim();
    if (trimmedUser.isEmpty || password.isEmpty) return null;
    final user = await (db.select(db.users)
          ..where((u) => u.username.equals(trimmedUser))
          ..limit(1))
        .getSingleOrNull();
    if (user == null) return null;
    if (!userHasPermission(user, permission)) return null;

    try {
      if (BCrypt.checkpw(password, user.password)) {
        return AdminElevation(adminId: user.id, adminUsername: user.username);
      }
    } catch (_) {/* malformed hash */}
    final customHash = prefs.getString('custom_password_${user.id}');
    if (customHash != null && customHash.isNotEmpty) {
      try {
        if (BCrypt.checkpw(password, customHash)) {
          return AdminElevation(adminId: user.id, adminUsername: user.username);
        }
      } catch (_) {/* malformed hash */}
    }
    return null;
  } catch (e, st) {
    debugPrint('verifyManagerCredentials failed: $e\n$st');
    return null;
  }
}

/// Show a modal that asks for an admin username + password and verifies them.
/// Used by the "Admin mode" chip and by sensitive gates that previously asked
/// for the tenant password (full logout, "show all orders" toggle).
///
/// Returns the matched [AdminElevation] on success, or `null` if the user
/// cancels or the credentials don't match.
///
/// This helper does NOT set [adminElevationProvider] — call sites decide what
/// to do with the result (the chip stores it; gates just use it as a yes/no).
Future<AdminElevation?> showAdminCredentialDialog(
  BuildContext context,
  WidgetRef ref, {
  String? title,
  String? description,
  String? confirmLabel,
  Color? confirmColor,
  // When set, authorizes an admin OR any user holding this permission (the pool
  // broadens accordingly). Null = admin-only (default).
  String? permission,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final passwordCtrl = TextEditingController();
  bool obscure = true;
  String? errorMessage;
  bool busy = false;
  AdminElevation? result;

  // Load the authorization pool. Admin-only by default; when a permission is
  // required, include every user (admin or not) who holds it. The dropdown
  // auto-selects when there's exactly one candidate.
  List<User> admins = const [];
  try {
    if (permission == null) {
      admins = await ref.read(userRepositoryProvider).getUsersByType('admin');
    } else {
      final all = await ref.read(databaseProvider).select(
            ref.read(databaseProvider).users,
          ).get();
      admins = all.where((u) => userHasPermission(u, permission)).toList();
    }
  } catch (e, st) {
    debugPrint('Auth user list load failed: $e\n$st');
  }
  int? selectedUserId =
      admins.length == 1 ? admins.first.id : null;

  if (!context.mounted) return null;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final selectedUser = selectedUserId == null
              ? null
              : admins.firstWhere(
                  (u) => u.id == selectedUserId,
                  orElse: () => admins.first,
                );

          Future<void> trySubmit() async {
            if (busy) return;
            if (selectedUser == null) return;
            setLocal(() {
              busy = true;
              errorMessage = null;
            });
            AdminElevation? r;
            try {
              final db = ref.read(databaseProvider);
              final prefs = ref.read(sharedPreferencesProvider);
              r = permission == null
                  ? await verifyAdminCredentials(
                      db,
                      prefs,
                      username: selectedUser.username,
                      password: passwordCtrl.text,
                    )
                  : await verifyManagerCredentials(
                      db,
                      prefs,
                      username: selectedUser.username,
                      password: passwordCtrl.text,
                      permission: permission,
                    );
            } catch (e, st) {
              debugPrint('Admin verify error: $e\n$st');
              r = null;
            }
            if (r == null) {
              if (ctx.mounted) {
                setLocal(() {
                  busy = false;
                  errorMessage = l10n.translate('invalid_admin_credentials');
                });
              }
              return;
            }
            result = r;
            FocusManager.instance.primaryFocus?.unfocus();
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

          final noAdmins = admins.isEmpty;
          final dropdownDisabled = noAdmins || admins.length == 1;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.shield, color: Colors.green),
                const SizedBox(width: 8),
                Text(title ?? l10n.translate('admin_mode')),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    description ?? l10n.translate('enter_admin_credentials'),
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (noAdmins)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.translate('no_admin_users'),
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: selectedUserId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.translate('admin_username'),
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                      ),
                      items: admins
                          .map((u) => DropdownMenuItem<int>(
                                value: u.id,
                                child: Text(
                                  u.displayLabel,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: dropdownDisabled || busy
                          ? null
                          : (v) => setLocal(() => selectedUserId = v),
                    ),
                  const SizedBox(height: 12),
                  AdaptiveKeyboardTextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: l10n.translate('admin_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(obscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setLocal(() => obscure = !obscure),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => trySubmit(),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(errorMessage!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 13)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(ctx).pop();
                      },
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: (busy || noAdmins || selectedUser == null)
                    ? null
                    : trySubmit,
                style: confirmColor != null
                    ? ElevatedButton.styleFrom(
                        backgroundColor: confirmColor,
                        foregroundColor: Colors.white,
                      )
                    : null,
                child: Text(confirmLabel ?? l10n.translate('confirm')),
              ),
            ],
          );
        },
      );
    },
  );

  passwordCtrl.dispose();
  return result;
}
