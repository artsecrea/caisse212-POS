import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import 'adaptive_text_field.dart';

/// Who may open printer setup.
///
/// Settings-grade on purpose: printer setup decides what every ticket says,
/// where each station's food prints, and the business identity on the
/// customer's receipt. It used to sit behind `devicesView` — held by anyone
/// who can look at the KDS list — so a cashier locked out of Settings could
/// still walk in and re-point the receipt printer.
///
/// Either the settings permission or the dedicated one, which exists for the
/// shop that wants a technician who sets printers up and has no business in
/// Settings. Admins pass both by being admins.
///
/// Pure, so the rule can be exercised without a widget tree.
bool printerSetupAllowed(PermissionService permissions) =>
    permissions.hasPermission(Permissions.settingsView) ||
    permissions.hasPermission(Permissions.printersManage);

/// Shortest and longest settings pin.
///
/// Four was the only allowed length; shops asked for longer because a 4-digit
/// code on a till the whole floor can see is shoulder-surfed in a shift. Eight
/// is the ceiling because the unlock field is shared with the master code,
/// which is `yyyymmdd`.
const int kSettingsPinMinLength = 4;
const int kSettingsPinMaxLength = 8;

/// Whether [pin] is an acceptable settings pin: digits only, 4 to 8 of them.
///
/// Pure, so the rule is testable and so the set-pin dialog and anything that
/// later writes a pin cannot disagree about what is valid.
bool isValidSettingsPin(String pin) {
  final p = pin.trim();
  if (p.length < kSettingsPinMinLength || p.length > kSettingsPinMaxLength) {
    return false;
  }
  return RegExp(r'^\d+$').hasMatch(p);
}

/// The code that opens Settings on any terminal, whatever pin is configured.
///
/// It is today's date as `yyyymmdd` — a value the owner can always work out
/// and nobody has to write down, which is the point: a forgotten 4-digit pin
/// would otherwise lock the owner out of their own till with no way back in
/// short of clearing app data.
///
/// It changes every midnight, so a code a cashier watched being typed stops
/// working the next day. It is NOT a secret in the cryptographic sense —
/// anyone who knows the scheme can open any terminal running this build.
String settingsMasterCode(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}'
    '${now.month.toString().padLeft(2, '0')}'
    '${now.day.toString().padLeft(2, '0')}';

/// Whether [code] opens Settings given the configured [pin].
///
/// [now] is injected rather than read here so the rule stays testable.
bool settingsCodeAccepted(String code, {required String pin, required DateTime now}) {
  final entered = code.trim();
  if (entered.isEmpty) return false;
  if (entered == settingsMasterCode(now)) return true;
  return pin.isNotEmpty && entered == pin;
}

/// Pin prompt shown before Settings opens.
///
/// Call [unlock] rather than showing this directly — it short-circuits when
/// the lock is off, so call sites do not each repeat that check.
class SettingsLockDialog extends ConsumerStatefulWidget {
  const SettingsLockDialog({super.key});

  /// Returns true when Settings may open: either the lock is off, or the
  /// operator typed the pin (or the master code). Returns false when they
  /// cancelled or got it wrong.
  /// Whether the current user may reach printer setup at all, before the PIN
  /// is asked. See [printerSetupAllowed] for the rule itself.
  static bool canOpenPrinters(WidgetRef ref) =>
      printerSetupAllowed(ref.read(permissionServiceProvider));

  /// The full gate for printer setup: permission, then the settings PIN.
  ///
  /// Both halves matter and neither is enough alone — the PIN is what stops
  /// the cashier at an unattended till, the permission is what stops the
  /// wrong staff member entirely. Complains on screen when refused, because a
  /// menu item that silently does nothing reads as a broken build.
  static Future<bool> unlockPrinters(
      BuildContext context, WidgetRef ref) async {
    if (!canOpenPrinters(ref)) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n?.translate('no_permission') ?? 'No permission'),
        backgroundColor: Colors.red,
      ));
      return false;
    }
    return unlock(context, ref);
  }

  static Future<bool> unlock(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    // An armed lock with no pin cannot be satisfied — treat it as off rather
    // than as a wall. `setSettingsLock` refuses to create this state, but a
    // hand-edited prefs file or a half-finished migration still could.
    if (!settings.settingsLockEnabled || settings.settingsPin.isEmpty) {
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SettingsLockDialog(),
    );
    return ok ?? false;
  }

  @override
  ConsumerState<SettingsLockDialog> createState() => _SettingsLockDialogState();
}

class _SettingsLockDialogState extends ConsumerState<SettingsLockDialog> {
  final _controller = TextEditingController();
  bool _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final accepted = settingsCodeAccepted(
      _controller.text,
      pin: ref.read(settingsProvider).settingsPin,
      now: DateTime.now(),
    );
    if (!accepted) {
      setState(() {
        _wrong = true;
        _controller.clear();
      });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      icon: const Icon(Icons.lock_outline, size: 32),
      title: Text(l10n.translate('settings_locked_title')),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('settings_locked_prompt'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            AdaptiveKeyboardTextField(
              controller: _controller,
              autofocus: true,
              obscureText: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              // The master code is 8 digits and a pin may now be up to 8 too,
              // so the field caps at 8 either way.
              maxLength: kSettingsPinMaxLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 28, letterSpacing: 12),
              decoration: InputDecoration(
                counterText: '',
                border: const OutlineInputBorder(),
                errorText: _wrong ? l10n.translate('wrong_code') : null,
              ),
              onChanged: (value) {
                if (_wrong) setState(() => _wrong = false);
                // A pin submits itself the moment it matches — the usual till
                // behaviour, and now length-agnostic: hard-coding 4 meant a
                // 6-digit pin typed correctly just sat there waiting for a
                // keypress the cashier had no reason to make.
                //
                // Matched on equality, not on length alone, so a WRONG entry
                // of the right length still waits for Enter/OK rather than
                // flashing "wrong code" mid-type. The master code (8 digits,
                // and not the pin) falls through to the same wait.
                final pin = ref.read(settingsProvider).settingsPin;
                if (pin.isNotEmpty && value == pin) {
                  _submit();
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.translate('unlock')),
        ),
      ],
    );
  }
}
