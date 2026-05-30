import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../providers/admin_elevation_provider.dart';
import '../providers/database_providers.dart';
import 'app_localizations.dart';

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
  } catch (_) {}

  // 2) bcrypt against the per-device custom hash.
  final customHash = prefs.getString('custom_password_${user.id}');
  if (customHash != null && customHash.isNotEmpty) {
    try {
      if (BCrypt.checkpw(trimmedPw, customHash)) {
        return AdminElevation(adminId: user.id, adminUsername: user.username);
      }
    } catch (_) {}
  }

  return null;
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
}) async {
  final l10n = AppLocalizations.of(context)!;
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  bool obscure = true;
  String? errorMessage;
  bool busy = false;
  AdminElevation? result;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> trySubmit() async {
            if (busy) return;
            setLocal(() {
              busy = true;
              errorMessage = null;
            });
            final db = ref.read(databaseProvider);
            final prefs = ref.read(sharedPreferencesProvider);
            final r = await verifyAdminCredentials(
              db,
              prefs,
              username: usernameCtrl.text,
              password: passwordCtrl.text,
            );
            if (r == null) {
              setLocal(() {
                busy = false;
                errorMessage = l10n.translate('invalid_admin_credentials');
              });
              return;
            }
            result = r;
            if (ctx.mounted) Navigator.of(ctx).pop();
          }

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
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  OnscreenKeyboardTextField(
                    controller: usernameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.translate('admin_username'),
                      prefixIcon: const Icon(Icons.person_outline),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OnscreenKeyboardTextField(
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
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: busy ? null : trySubmit,
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

  usernameCtrl.dispose();
  passwordCtrl.dispose();
  return result;
}
