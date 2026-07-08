import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart' show Value;
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';

/// Profile dialog showing user info and allowing password change.
/// The custom password is stored in SharedPreferences (per user).
/// The user can still log in with the original (server) password OR the custom one.
class ProfileDialog extends ConsumerStatefulWidget {
  const ProfileDialog({super.key});

  @override
  ConsumerState<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends ConsumerState<ProfileDialog> {
  bool _isChangingPassword = false;
  bool _isEditingDisplayName = false;

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _displayNameController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _passwordError;
  bool _isSaving = false;
  bool _isSavingDisplayName = false;

  @override
  void initState() {
    super.initState();
    final currentUser = ref.read(currentUserProvider);
    _displayNameController.text = currentUser?.displayName ?? '';
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDisplayName() async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;
    setState(() => _isSavingDisplayName = true);
    try {
      final db = ref.read(databaseProvider);
      final newName = _displayNameController.text.trim();
      await (db.update(db.users)..where((u) => u.id.equals(currentUser.id)))
          .write(UsersCompanion(displayName: Value(newName.isEmpty ? null : newName)));
      ref.read(currentUserProvider.notifier).state =
          currentUser.copyWith(displayName: newName.isEmpty ? null : newName);
      if (mounted) {
        setState(() {
          _isSavingDisplayName = false;
          _isEditingDisplayName = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSavingDisplayName = false);
    }
  }

  /// Validate the current password against DB hash OR custom SharedPrefs hash
  bool _verifyCurrentPassword(String input) {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return false;

    // Check against DB password (original)
    try {
      if (BCrypt.checkpw(input, currentUser.password)) return true;
    } catch (_) {}

    // Check against custom SharedPrefs password
    final prefs = ref.read(sharedPreferencesProvider);
    final customHash = prefs.getString('custom_password_${currentUser.id}');
    if (customHash != null) {
      try {
        if (BCrypt.checkpw(input, customHash)) return true;
      } catch (_) {}
    }

    return false;
  }

  Future<void> _saveNewPassword() async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    // Validate
    final current = _currentPasswordController.text.trim();
    final newPw = _newPasswordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (current.isEmpty || newPw.isEmpty || confirm.isEmpty) {
      setState(() => _passwordError = l10n.translate('all_fields_required'));
      return;
    }

    if (!_verifyCurrentPassword(current)) {
      setState(() => _passwordError = l10n.translate('current_password_incorrect'));
      return;
    }

    if (newPw.length < 4) {
      setState(() => _passwordError = l10n.translate('password_too_short'));
      return;
    }

    if (newPw != confirm) {
      setState(() => _passwordError = l10n.translate('passwords_do_not_match'));
      return;
    }

    setState(() {
      _isSaving = true;
      _passwordError = null;
    });

    try {
      // Hash the new password and save to SharedPreferences
      final hash = BCrypt.hashpw(newPw, BCrypt.gensalt());
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('custom_password_${currentUser.id}', hash);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isChangingPassword = false;
        });
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('password_changed_successfully')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _passwordError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final currentSession = ref.watch(currentSessionProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final prefs = ref.read(sharedPreferencesProvider);
    final hasCustomPassword = currentUser != null &&
        prefs.getString('custom_password_${currentUser.id}') != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(
                      currentUser?.firstName.substring(0, 1).toUpperCase() ?? 'U',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: theme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentUser?.effectiveDisplayName ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${currentUser?.username ?? ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Info Section
                    _buildInfoRow(
                      icon: Icons.person,
                      label: l10n.translate('username'),
                      value: currentUser?.username ?? '-',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      icon: Icons.badge,
                      label: l10n.translate('role'),
                      value: currentUser?.type ?? '-',
                    ),
                    const SizedBox(height: 12),
                    if (currentSession != null) ...[
                      _buildInfoRow(
                        icon: Icons.access_time,
                        label: l10n.translate('session'),
                        value: '#${currentSession.id} (${currentSession.status})',
                      ),
                      const SizedBox(height: 12),
                    ],
                    _buildInfoRow(
                      icon: Icons.lock,
                      label: l10n.translate('custom_password'),
                      value: hasCustomPassword
                          ? l10n.translate('set')
                          : l10n.translate('not_set'),
                      valueColor: hasCustomPassword ? Colors.green : Colors.grey,
                    ),

                    const Divider(height: 32),

                    // Display Name Section
                    InkWell(
                      onTap: () => setState(() {
                        _isEditingDisplayName = !_isEditingDisplayName;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.badge_outlined, color: theme.primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.translate('display_name'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                            Icon(
                              _isEditingDisplayName ? Icons.expand_less : Icons.expand_more,
                              color: theme.primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_isEditingDisplayName) ...[
                      const SizedBox(height: 12),
                      OnscreenKeyboardTextField(
                        controller: _displayNameController,
                        decoration: InputDecoration(
                          labelText: l10n.translate('display_name'),
                          hintText: currentUser?.effectiveDisplayName,
                          prefixIcon: const Icon(Icons.edit),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => setState(() {
                              _isEditingDisplayName = false;
                              _displayNameController.text =
                                  currentUser?.displayName ?? '';
                            }),
                            child: Text(l10n.translate('cancel')),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isSavingDisplayName ? null : _saveDisplayName,
                            icon: _isSavingDisplayName
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save, size: 18),
                            label: Text(l10n.translate('save')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const Divider(height: 32),

                    // Change Password Section
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isChangingPassword = !_isChangingPassword;
                          _passwordError = null;
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.key, color: theme.primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.translate('change_password'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.primaryColor,
                                ),
                              ),
                            ),
                            Icon(
                              _isChangingPassword
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              color: theme.primaryColor,
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (_isChangingPassword) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('change_password_hint'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Current Password
                      OnscreenKeyboardTextField(
                        controller: _currentPasswordController,
                        obscureText: _obscureCurrent,
                        decoration: InputDecoration(
                          labelText: l10n.translate('current_password'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureCurrent
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscureCurrent = !_obscureCurrent),
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // New Password
                      OnscreenKeyboardTextField(
                        controller: _newPasswordController,
                        obscureText: _obscureNew,
                        decoration: InputDecoration(
                          labelText: l10n.translate('new_password'),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscureNew = !_obscureNew),
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Confirm Password
                      OnscreenKeyboardTextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: l10n.translate('confirm_password'),
                          prefixIcon: const Icon(Icons.lock_clock),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),

                      if (_passwordError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _passwordError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _isChangingPassword = false;
                                _passwordError = null;
                              });
                              _currentPasswordController.clear();
                              _newPasswordController.clear();
                              _confirmPasswordController.clear();
                            },
                            child: Text(l10n.translate('cancel')),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveNewPassword,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 18),
                            label: Text(l10n.translate('save')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),

                      // Remove custom password button
                      if (hasCustomPassword) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(l10n.translate('remove_custom_password')),
                                  content: Text(l10n.translate('remove_custom_password_confirm')),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text(l10n.translate('cancel')),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: Text(l10n.translate('remove')),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final prefs = ref.read(sharedPreferencesProvider);
                                await prefs.remove('custom_password_${currentUser.id}');
                                if (mounted) {
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(l10n.translate('custom_password_removed')),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.red),
                            label: Text(
                              l10n.translate('remove_custom_password'),
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}


