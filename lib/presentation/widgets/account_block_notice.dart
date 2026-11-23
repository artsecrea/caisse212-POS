import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/account_status.dart';
import '../../providers/database_providers.dart';
import '../../services/api_service.dart';
import '../../utils/app_localizations.dart';

/// Login-screen lock card shown while the tenant, business or terminal is
/// deactivated in the back office. Sign-in stays disabled until it clears.
///
/// The till asks the server when the screen opens, every minute while the card
/// is up, and on "Check again". Only a definite answer from the server unlocks
/// it. Being offline keeps the lock, so pulling the cable is no way around it.
class AccountBlockNotice extends ConsumerStatefulWidget {
  const AccountBlockNotice({super.key});

  @override
  ConsumerState<AccountBlockNotice> createState() => _AccountBlockNoticeState();
}

class _AccountBlockNoticeState extends ConsumerState<AccountBlockNotice> {
  static const _pollEvery = Duration(seconds: 60);

  Timer? _poll;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(accountBlockProvider) != null) unawaited(_check());
    });
    _poll = Timer.periodic(_pollEvery, (_) {
      if (!mounted || _checking) return;
      if (ref.read(accountBlockProvider) != null) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<AccountCheck> _check() async {
    setState(() => _checking = true);
    final result = await ref.read(apiServiceProvider).checkAccountStatus();
    if (mounted) setState(() => _checking = false);
    return result;
  }

  Future<void> _checkAgain() async {
    final result = await _check();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final msg = switch (result) {
      AccountCheck.active => l10n?.translate('account_reactivated') ??
          'The account is active again. You can sign in.',
      AccountCheck.blocked => l10n?.translate('account_still_disabled') ??
          'The account is still deactivated.',
      AccountCheck.unknown => l10n?.translate('subscription_check_failed') ??
          'Could not reach the server. Check the connection and try again.',
    };
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final block = ref.watch(accountBlockProvider);
    if (block == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tone = cs.error;

    final title = switch (block.scope) {
      AccountBlockScope.tenant =>
        l10n?.translate('account_disabled_tenant') ?? 'This account is deactivated',
      AccountBlockScope.business =>
        l10n?.translate('account_disabled_business') ?? 'This business is deactivated',
      AccountBlockScope.terminal =>
        l10n?.translate('account_disabled_terminal') ?? 'This till is deactivated',
      AccountBlockScope.unknown =>
        l10n?.translate('account_disabled_tenant') ?? 'This account is deactivated',
    };
    final body = l10n?.translate('account_disabled_body') ??
        'Sign-in is locked. Contact your administrator. The till unlocks by itself once the account is reactivated.';
    final since = (l10n?.translate('account_disabled_since') ?? 'Since {date}')
        .replaceAll('{date}', DateFormat('dd/MM/yyyy HH:mm').format(block.since));

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: tone, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        fontSize: 14, color: cs.onSurfaceVariant, height: 1.35)),
                if (block.message != null) ...[
                  const SizedBox(height: 6),
                  Text(block.message!,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
                if (block.reasonCode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                      (l10n?.translate('account_block_code') ?? 'Code: {code}')
                          .replaceAll('{code}', block.reasonCode!),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 4),
                Text(since,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: cs.error, foregroundColor: cs.onError),
                    onPressed: _checking ? null : _checkAgain,
                    icon: _checking
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onError))
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                        l10n?.translate('subscription_check_again') ?? 'Check again'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
