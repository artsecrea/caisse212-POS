import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/session_expiry.dart';
import '../../providers/database_providers.dart';
import '../../providers/reauth_provider.dart';
import '../../utils/app_localizations.dart';

/// Advance warning, on the login screen, that this till's sign-in runs out
/// soon.
///
/// Deliberately says nothing about tokens, sessions or refreshes. The person
/// reading it is opening a till, not debugging one, and the only thing they
/// need to know is that a manager has to sign in before a date — and what
/// happens if nobody does. The detail is one tap away for whoever wants it.
///
/// Shows nothing inside the last day: the app blocks on its own by then, and a
/// warning next to a blocking dialog is just noise.
class SessionExpiryNotice extends ConsumerStatefulWidget {
  const SessionExpiryNotice({super.key});

  @override
  ConsumerState<SessionExpiryNotice> createState() =>
      _SessionExpiryNoticeState();
}

class _SessionExpiryNoticeState extends ConsumerState<SessionExpiryNotice> {
  Timer? _ticker;
  StreamSubscription<void>? _expirySub;

  @override
  void initState() {
    super.initState();
    // Redraw the moment the expiry moves — a re-auth should clear the notice
    // now, not at the next tick.
    _expirySub = ref.read(apiServiceProvider).expiryChanges.listen((_) {
      if (mounted) setState(() {});
    });
    // A till can sit on the login screen all night. Without this the day count
    // would be whatever it was when the screen opened.
    _ticker = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _expirySub?.cancel();
    super.dispose();
  }

  void _explain(int days, DateTime expiresAt) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n?.translate('session_expiry_more_title') ??
            'Why is this asking for a sign-in?'),
        content: SizedBox(
          width: 460,
          child: Text(
            l10n?.translate('session_expiry_more_body') ??
                'For security, this till stays signed in to the shop only for '
                    'a limited time. When that runs out the till locks itself '
                    'until a manager signs in again.\n\n'
                    'Nothing is lost when it locks: every order already taken '
                    'is saved and will be sent once the till is unlocked. But '
                    'no new orders can be rung up until then, so it is worth '
                    'doing this before a busy service rather than during one.\n\n'
                    'Any manager account for this shop can do it, on this till, '
                    'in a few seconds.',
            style: const TextStyle(fontSize: 15, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n?.translate('close') ?? 'Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(reauthVoluntaryProvider.notifier).state = true;
            },
            icon: const Icon(Icons.login),
            label: Text(l10n?.translate('session_expiry_renew') ?? 'Sign in now'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiresAt = ref.watch(apiServiceProvider).getRefreshExpiresAt();
    final level = sessionExpiryLevel(expiresAt, DateTime.now());
    if (level != SessionExpiryLevel.notice) return const SizedBox.shrink();

    final days = sessionDaysLeft(expiresAt!, DateTime.now());
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;

    // Amber, not red: nothing is wrong yet, and a red banner on every login
    // for a week would be ignored by the third day.
    const amber = Color(0xFFB26A00);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: amber, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.translate('session_expiry_title') ??
                          'A manager needs to sign in soon',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _message(l10n, days),
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurfaceVariant, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _explain(days, expiresAt),
                child: Text(
                    l10n?.translate('session_expiry_more') ?? 'See more'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: () =>
                    ref.read(reauthVoluntaryProvider.notifier).state = true,
                icon: const Icon(Icons.login, size: 18),
                label: Text(l10n?.translate('session_expiry_renew') ??
                    'Sign in now'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "in 6 days" / "tomorrow" — a deadline, not a timestamp.
  String _message(AppLocalizations? l10n, int days) {
    final template = days == 1
        ? (l10n?.translate('session_expiry_body_one') ??
            'This till stops working tomorrow unless a manager signs in here.')
        : (l10n?.translate('session_expiry_body') ??
            'This till stops working in {days} days unless a manager signs in here.');
    return template.replaceAll('{days}', '$days');
  }
}
