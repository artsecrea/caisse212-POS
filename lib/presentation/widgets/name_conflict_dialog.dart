import 'package:flutter/material.dart';

import '../../utils/app_localizations.dart';

/// What the cashier picked when an existing local customer shares a
/// phone with the queue item but the names differ.
enum NameConflictChoice {
  /// Reuse the existing local customer as-is; don't override the name.
  keepExisting,

  /// Replace the local name with the value the queue sent (upsert with
  /// the new firstName/lastName).
  useNew,
}

/// Shown when the queue's customerPhone matches an existing local
/// customer **and** the stored name differs from what the queue sent.
/// One-tap resolution between "keep what I have" and "trust the new
/// source". Cancel returns `null` so the review dialog stays open and
/// the cashier can pick a different path.
class NameConflictDialog extends StatelessWidget {
  final String existingName;
  final String newName;
  final String phone;

  const NameConflictDialog({
    super.key,
    required this.existingName,
    required this.newName,
    required this.phone,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    final media = MediaQuery.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        // Cap width for big screens but shrink on phones (no horizontal
        // overflow), and cap height to the visible area minus the keyboard so
        // the content scrolls instead of overflowing.
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: media.size.height - media.viewInsets.bottom - 32,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.warning_amber_rounded,
                      color: Colors.amber.shade800),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('name_conflict_title'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n
                  .translate('conflict_explainer')
                  .replaceAll('{phone}', phone),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Side-by-side cards — existing vs new.
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _nameCard(
                    context,
                    label: l10n.translate('existing'),
                    name: existingName,
                    color: colors.primaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _nameCard(
                    context,
                    label: l10n.translate('from_whatsapp'),
                    name: newName,
                    color: Colors.green.withValues(alpha: 0.15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action buttons — full width each, stacked, so the labels
            // can include the actual names without ellipsis.
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context)
                  .pop(NameConflictChoice.keepExisting),
              icon: const Icon(Icons.lock_outline),
              label: Text(
                '${l10n.translate('keep_existing')}: $existingName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                textStyle: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(NameConflictChoice.useNew),
              icon: const Icon(Icons.swap_horiz),
              label: Text(
                '${l10n.translate('use_new')}: $newName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.translate('cancel')),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameCard(BuildContext context,
      {required String label,
      required String name,
      required Color color}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
