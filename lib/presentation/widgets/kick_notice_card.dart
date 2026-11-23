import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';

/// Why the back office signed this till out (`force_kick`). Shown on the
/// login screen and on the re-auth gate until the terminal signs in again.
/// Informational only: sign-in is not locked.
class KickNoticeCard extends ConsumerWidget {
  const KickNoticeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kick = ref.watch(kickNoticeProvider);
    if (kick == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final tone = cs.tertiary;

    final codeKey = 'kick_code_${kick.code}';
    final translated = l10n?.translate(codeKey);
    // translate() echoes unknown keys back; a newer server code shows raw.
    final reason =
        translated == null || translated == codeKey ? kick.code : translated;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.55), width: 1.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.logout, color: tone, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    l10n?.translate('kick_title') ??
                        'This till was signed out by the back office',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(reason,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                if (kick.message != null) ...[
                  const SizedBox(height: 4),
                  Text(kick.message!, style: const TextStyle(fontSize: 14)),
                ],
                const SizedBox(height: 4),
                Text(
                    l10n?.translate('kick_body') ??
                        'Your session was paused and nothing was lost. Sign in again to continue.',
                    style: TextStyle(
                        fontSize: 13, color: cs.onSurfaceVariant, height: 1.35)),
                const SizedBox(height: 4),
                Text(
                    '${kick.code} · ${DateFormat('dd/MM/yyyy HH:mm').format(kick.at)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
