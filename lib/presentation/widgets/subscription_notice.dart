import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/subscription_info.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';

/// Login-screen warning that the shop's subscription ends within two weeks,
/// or already has.
///
/// Warns during the last two weeks, and in red once EXPIRED. It never locks:
/// an expired subscription keeps the till working (user ruling 2026-11-16,
/// replacing the 2026-10-08 lock). Locking belongs to account deactivation,
/// see AccountBlockNotice. "Check again" re-reads the server, because the date
/// held here may be stale.
///
/// Disappears by itself once a renewal reaches the till (daily check, sync,
/// token refresh or an SSE push all update [subscriptionProvider]).
class SubscriptionNotice extends ConsumerStatefulWidget {
  const SubscriptionNotice({super.key});

  @override
  ConsumerState<SubscriptionNotice> createState() => _SubscriptionNoticeState();
}

class _SubscriptionNoticeState extends ConsumerState<SubscriptionNotice> {
  Timer? _ticker;
  bool _checking = false;

  /// "Check again": re-read the subscription now. A renewal unlocks sign-in
  /// at once; anything else says plainly what happened.
  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    final ok = await ref.read(apiServiceProvider).refreshSubscription();
    if (!mounted) return;
    setState(() => _checking = false);
    final l10n = AppLocalizations.of(context);
    final stillExpired =
        subscriptionLevel(ref.read(subscriptionProvider), DateTime.now()) ==
            SubscriptionLevel.expired;
    final msg = !ok
        ? (l10n?.translate('subscription_check_failed') ??
            'Could not reach the server. Check the connection and try again.')
        : stillExpired
            ? (l10n?.translate('subscription_still_expired') ??
                'The subscription is still expired.')
            : (l10n?.translate('subscription_renewed') ??
                'Subscription renewed. You can sign in.');
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    // A till can sit on the login screen overnight: re-evaluate the day count,
    // and run the daily check once the date has rolled over.
    _ticker = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!mounted) return;
      setState(() {});
      unawaited(ref
          .read(apiServiceProvider)
          .refreshSubscription(onlyIfDue: true));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(subscriptionProvider);
    final now = DateTime.now();
    final level = subscriptionLevel(info, now);
    if (level == SubscriptionLevel.none) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final expired = level == SubscriptionLevel.expired;
    // Amber while there is time, like the sign-in notice; red once it lapsed.
    final tone = expired ? cs.error : const Color(0xFFB26A00);

    final end = info!.endsAt;
    // Numeric: needs no per-locale date data and reads the same in AR/FR/EN.
    final dateText = end == null ? '' : DateFormat('dd/MM/yyyy').format(end);

    final String title;
    if (expired) {
      title = l10n?.translate('subscription_expired_title') ??
          'Your subscription has expired';
    } else {
      final days = subscriptionDaysLeft(end!, now);
      title = switch (days) {
        0 => l10n?.translate('subscription_ends_today') ??
            'Your subscription ends today',
        1 => l10n?.translate('subscription_ends_tomorrow') ??
            'Your subscription ends tomorrow',
        _ => (l10n?.translate('subscription_ends_in') ??
                'Your subscription ends in {days} days')
            .replaceAll('{days}', '$days'),
      };
    }

    final body = expired
        ? (l10n?.translate('subscription_expired_body') ??
            'It ended on {date}. Renew it to avoid an interruption of service.')
        : (l10n?.translate('subscription_ending_body') ??
            'It ends on {date}. Renew it to keep this till working without interruption.');

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.45), width: 1.4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(expired ? Icons.error_outline : Icons.event_busy,
              color: tone, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  body.replaceAll('{date}', dateText),
                  style: TextStyle(
                      fontSize: 14, color: cs.onSurfaceVariant, height: 1.35),
                ),
                // After paying, this re-reads it so the card goes away.
                if (expired) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: cs.error,
                          foregroundColor: cs.onError),
                      onPressed: _checking ? null : _checkAgain,
                      icon: _checking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: cs.onError))
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(l10n?.translate('subscription_check_again') ??
                          'Check again'),
                    ),
                  ),
                ],
                if (info.contact != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${l10n?.translate('subscription_contact') ?? 'Contact'}: ${info.contact}',
                    style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
