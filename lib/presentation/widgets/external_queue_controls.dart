import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/external_order_provider.dart';
import '../../utils/app_localizations.dart';

/// Touch-screen filter bar and pager for the external (online) order queue.
///
/// Extracted so the queue's controls live in one place: they are used by the
/// external tab of the order-confirmation screen, which is where the cashier
/// works the queue from. Kept out of that screen's own file because these are
/// self-contained, stateless-over-the-provider widgets with no dependency on
/// the confirm screen's selection state.

/// Source + status filters with live totals.
///
/// Built for a touch screen: controls are >=42px tall, and the chip rows scroll
/// horizontally instead of wrapping — a row that reflows when counts change
/// moves the target out from under a finger mid-tap. Each chip carries its own
/// count so the cashier can see where the work is before committing to a tap.
class ExternalQueueFilterBar extends ConsumerWidget {
  final ExternalOrderState state;
  final AppLocalizations l10n;

  const ExternalQueueFilterBar(
      {super.key, required this.state, required this.l10n});

  static const _statuses = [
    'PENDING',
    'CONFIRMED',
    'ACKNOWLEDGED',
    'CANCELLED',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(externalOrderProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_download_outlined, size: 20, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                // The honest headline: what THIS filter holds, from the
                // server's own totalElements rather than the page length.
                child: Text(
                  state.totalElements == 1
                      ? l10n.translate('one_online_order')
                      : l10n
                          .translate('n_online_orders')
                          .replaceAll('{0}', state.totalElements.toString()),
                  style:
                      const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                iconSize: 26,
                tooltip: l10n.translate('refresh'),
                onPressed: state.isLoading ? null : notifier.load,
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Status: a small fixed set, so chips beat a dropdown — one tap, and
          // the current state is visible without opening anything.
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final st in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                          l10n.translate('queue_status_${st.toLowerCase()}')),
                      selected: state.statusFilter == st,
                      onSelected: state.isLoading
                          ? null
                          : (_) => notifier.setStatus(st),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Sources rendered FROM THE SERVER'S COUNT MAP, not a hardcoded list,
          // so a platform added server-side shows up without a client release.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _SourceChip(
                  label: l10n.translate('all'),
                  count: state.counts.total,
                  selected: state.sourceFilter == null,
                  onTap:
                      state.isLoading ? null : () => notifier.setSource(null),
                ),
                for (final key in state.counts.bySource.keys)
                  _SourceChip(
                    label: _sourceLabel(key, l10n),
                    count: state.counts.countFor(key),
                    selected: state.sourceFilter == key,
                    // A zero-count chip stays tappable: filtering to an empty
                    // platform is a valid way to confirm nothing is waiting.
                    onTap: state.isLoading
                        ? null
                        : () => notifier.setSource(key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _sourceLabel(String key, AppLocalizations l10n) {
    switch (key.toUpperCase()) {
      case 'WEB':
        return l10n.translate('source_web');
      case 'GLOVO':
        return 'Glovo';
      case 'KOOUL':
        return 'Kooul';
      case 'OTHER':
        return l10n.translate('source_other');
      default:
        return key;
    }
  }
}

class _SourceChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  const _SourceChip({
    required this.label,
    required this.count,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? cs.primary : cs.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 84),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: selected ? cs.primary : cs.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected ? cs.onPrimary : cs.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.onPrimary.withValues(alpha: 0.25)
                        : cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? cs.onPrimary : cs.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Server-side pager.
///
/// Big arrows rather than numbered page links: on a touch screen a row of small
/// digits is a poor target, and the job here is "work through the queue", not
/// "jump to page 7". Hidden entirely on a single page, so the common case
/// carries no chrome at all.
class ExternalQueuePager extends ConsumerWidget {
  final ExternalOrderState state;
  final AppLocalizations l10n;

  const ExternalQueuePager(
      {super.key, required this.state, required this.l10n});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.displayTotalPages <= 1) return const SizedBox.shrink();
    final notifier = ref.read(externalOrderProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          _PagerButton(
            icon: Icons.chevron_left,
            label: l10n.translate('previous'),
            onTap: (state.isFirstPage || state.isLoading)
                ? null
                : notifier.previousPage,
          ),
          Expanded(
            child: Center(
              child: Text(
                l10n
                    .translate('page_x_of_y')
                    .replaceAll('{0}', '${state.displayPage}')
                    .replaceAll('{1}', '${state.displayTotalPages}'),
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          _PagerButton(
            icon: Icons.chevron_right,
            label: l10n.translate('next'),
            trailingIcon: true,
            onTap:
                (state.isLastPage || state.isLoading) ? null : notifier.nextPage,
          ),
        ],
      ),
    );
  }
}

class _PagerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool trailingIcon;
  final VoidCallback? onTap;

  const _PagerButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.trailingIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48, // full touch target
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!trailingIcon) Icon(icon),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (trailingIcon) Icon(icon),
          ],
        ),
      ),
    );
  }
}
