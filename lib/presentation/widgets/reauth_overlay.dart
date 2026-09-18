import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/reauth_provider.dart';
import '../../utils/app_localizations.dart';

/// Full-screen, non-dismissible re-authentication gate. Shown app-wide (from
/// `main.dart`'s builder, above the Navigator) whenever
/// [reauthRequiredProvider] is true — i.e. the terminal's session (refresh)
/// token is expired/about to expire, or was rejected by the server.
///
/// It re-authenticates the TENANT/terminal (username + posName are known and
/// shown read-only; only the password is asked) via [ApiService.login], which
/// mints fresh tokens. On success the gate clears and the app resumes exactly
/// where it was — no navigation, no lost state. A "Sign out" escape delegates
/// to [onSignOut] (main.dart owns the navigator).
class ReauthOverlay extends ConsumerStatefulWidget {
  final Future<void> Function() onSignOut;
  const ReauthOverlay({super.key, required this.onSignOut});

  @override
  ConsumerState<ReauthOverlay> createState() => _ReauthOverlayState();
}

class _ReauthOverlayState extends ConsumerState<ReauthOverlay> {
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _reauthenticate() async {
    final api = ref.read(apiServiceProvider);
    final username = api.getUsername();
    final posName = api.getPosName();
    final password = _passwordCtrl.text;
    if (password.isEmpty || username == null || posName == null) {
      setState(() => _error =
          AppLocalizations.of(context)?.translate('reauth_failed') ??
              'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.login(
          username: username, password: password, posName: posName);
      _passwordCtrl.clear();
      // Success mints fresh tokens → clears the gate, and closes the dialog
      // when it was opened early rather than forced.
      ref.read(reauthRequiredProvider.notifier).reevaluate();
      ref.read(reauthVoluntaryProvider.notifier).state = false;
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            AppLocalizations.of(context)?.translate('reauth_failed') ??
                'Re-authentication failed. Check your password.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final required = ref.watch(reauthRequiredProvider);
    final voluntary = ref.watch(reauthVoluntaryProvider);
    if (!required && !voluntary) return const SizedBox.shrink();

    // Opened early, of the operator's own accord: nothing is broken yet, so
    // there has to be a way out that is not signing out of the terminal.
    final dismissible = !required;

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final api = ref.read(apiServiceProvider);

    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_clock_outlined,
                          size: 34, color: cs.primary),
                      const SizedBox(height: 12),
                      Text(
                        dismissible
                            ? (l10n?.translate('reauth_title_early') ??
                                'Renew this till\'s sign-in')
                            : (l10n?.translate('reauth_title') ??
                                'Session expired — re-authenticate'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        dismissible
                            ? (l10n?.translate('reauth_message_early') ??
                                'Renewing early keeps the till working. Enter the password to continue — nothing is lost.')
                            : (l10n?.translate('reauth_message') ??
                                'Your terminal session needs renewing to keep syncing. Enter the password to continue — your work is preserved.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 18),
                      _readOnlyRow(cs, Icons.point_of_sale,
                          api.getPosName() ?? '—'),
                      const SizedBox(height: 8),
                      _readOnlyRow(
                          cs, Icons.person_outline, api.getUsername() ?? '—'),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        enabled: !_busy,
                        autofocus: true,
                        onSubmitted: (_) => _busy ? null : _reauthenticate(),
                        decoration: InputDecoration(
                          labelText: l10n?.translate('reauth_password') ??
                              'Password',
                          prefixIcon: const Icon(Icons.password),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: TextStyle(color: cs.error, fontSize: 12.5)),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _reauthenticate,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: Text(l10n?.translate('reauth_button') ??
                            'Re-authenticate'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (dismissible)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => ref
                                  .read(reauthVoluntaryProvider.notifier)
                                  .state = false,
                          child: Text(l10n?.translate('later') ?? 'Later'),
                        )
                      else
                        TextButton(
                          onPressed: _busy ? null : () => widget.onSignOut(),
                          child: Text(l10n?.translate('reauth_signout') ??
                              'Sign out'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readOnlyRow(ColorScheme cs, IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
