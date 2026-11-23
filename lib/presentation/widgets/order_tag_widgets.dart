import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' show OrderTag;
import '../../domain/models/order_tag_codec.dart';
import '../../providers/database_providers.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

/// A tag's color, or the theme's when the back office set none.
Color orderTagColor(BuildContext context, OrderTag tag) {
  final argb = parseTagColor(tag.color);
  return argb == null ? Theme.of(context).colorScheme.secondary : Color(argb);
}

/// Text that stays readable on [background].
Color _onColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

/// One tag as a small colored chip.
class OrderTagChip extends StatelessWidget {
  final OrderTag tag;
  final bool dense;
  const OrderTagChip({super.key, required this.tag, this.dense = true});

  @override
  Widget build(BuildContext context) {
    final bg = orderTagColor(context, tag);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 6 : 10, vertical: dense ? 1 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag.label,
        style: TextStyle(
          color: _onColor(bg),
          fontSize: dense ? 11 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The tags of an order as chips. Ids the catalogue no longer has (deleted in
/// the back office) are simply not shown.
class OrderTagChips extends ConsumerWidget {
  final List<int> tagIds;
  final bool dense;

  /// One line (a Row) instead of wrapping — for inside a Row, where a Wrap
  /// has no width to wrap against.
  final bool inline;
  const OrderTagChips(
      {super.key, required this.tagIds, this.dense = true, this.inline = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tagIds.isEmpty) return const SizedBox.shrink();
    final catalogue = ref.watch(orderTagsProvider).valueOrNull ?? const [];
    final byId = {for (final t in catalogue) t.id: t};
    final tags = [
      for (final id in tagIds)
        if (byId[id] != null) byId[id]!
    ];
    if (tags.isEmpty) return const SizedBox.shrink();
    if (inline) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        for (final t in tags) ...[
          OrderTagChip(tag: t, dense: dense),
          const SizedBox(width: 4),
        ],
      ]);
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final t in tags) OrderTagChip(tag: t, dense: dense)],
    );
  }
}

/// Pick the tags of an order. Returns the new set, or null when cancelled.
Future<List<int>?> showOrderTagPicker({
  required BuildContext context,
  required WidgetRef ref,
  required List<int> initial,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final selected = <int>{...initial};

  return showDialog<List<int>>(
    context: context,
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final catalogue = ref.watch(orderTagsProvider).valueOrNull ?? const [];
      return StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.label_outline),
            const SizedBox(width: 8),
            Text(l10n.translate('order_tags')),
          ]),
          content: SizedBox(
            width: 460,
            child: catalogue.isEmpty
                ? Text(l10n.translate('order_tags_none_defined'))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in catalogue)
                        FilterChip(
                          label: Text(t.label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700)),
                          selected: selected.contains(t.id),
                          selectedColor: orderTagColor(ctx, t)
                              .withValues(alpha: 0.35),
                          avatar: CircleAvatar(
                              backgroundColor: orderTagColor(ctx, t),
                              radius: 7),
                          onSelected: (on) => setLocal(() {
                            if (!on) {
                              selected.remove(t.id);
                            } else if (selected.length >= kMaxOrderTags) {
                              SnackBarHelper.showToast(
                                  l10n
                                      .translate('order_tags_max')
                                      .replaceAll('{n}', '$kMaxOrderTags'),
                                  kind: ToastKind.warning);
                            } else {
                              selected.add(t.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            if (selected.isNotEmpty)
              TextButton(
                onPressed: () => setLocal(selected.clear),
                child: Text(l10n.translate('order_tags_clear')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.translate('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, [
                // Back-office order, not tap order.
                for (final t in catalogue)
                  if (selected.contains(t.id)) t.id,
              ]),
              child: Text(l10n.translate('save')),
            ),
          ],
        );
      });
    }),
  );
}
