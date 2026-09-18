import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import './adaptive_text_field.dart';

/// The notes a kitchen gets when nobody has written their own: short,
/// repetitive, and the same in every restaurant. Translated, unlike the
/// shop's own presets, which are whatever the shop typed.
const _builtInNotePresets = [
  'allergy',
  'no_cutlery',
  'serve_together',
  'rush_order',
  'takeaway_box',
];

/// Edit the order-level kitchen note.
///
/// Returns:
///   * `null` — cancelled, leave the note alone;
///   * `''`   — the cashier cleared it;
///   * text   — the new note.
///
/// The empty-string-vs-null distinction matters: `CurrentOrder.copyWith` treats
/// null as "keep", so "cancelled" and "cleared" cannot be the same value.
Future<String?> showOrderNoteDialog({
  required BuildContext context,
  required WidgetRef ref,
  String? currentNote,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: currentNote ?? '');

  // The shop's own presets win; the built-ins fill in for a till nobody has
  // customised. Clearing the list in settings is how you get them back.
  final custom = ref.read(settingsProvider).notePresets;
  final presets = custom.isNotEmpty
      ? custom
      : [for (final key in _builtInNotePresets) l10n.translate('note_preset_$key')];

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final media = MediaQuery.of(ctx).size;

      return StatefulBuilder(builder: (ctx, setLocal) {
        // Presets append rather than replace: a note is usually two or three
        // of these together ("no cutlery · rush"), and re-typing the first one
        // because the second overwrote it is exactly the friction this is for.
        void append(String text) {
          final existing = controller.text.trim();
          controller.text = existing.isEmpty ? text : '$existing · $text';
          controller.selection =
              TextSelection.collapsed(offset: controller.text.length);
          setLocal(() {});
        }

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(children: [
            Icon(Icons.sticky_note_2_outlined, color: cs.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.translate('order_note'),
                  style: const TextStyle(fontSize: 22)),
            ),
          ]),
          content: SizedBox(
            // Wide enough that the presets sit in two or three rows a thumb
            // can hit without hunting, capped so it never fills a desktop.
            width: media.width * 0.72 > 820 ? 820 : media.width * 0.72,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdaptiveKeyboardTextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 18),
                    decoration: InputDecoration(
                      hintText: l10n.translate('order_note_hint'),
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.edit_note),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 16),
                  if (presets.isEmpty)
                    Text(
                      l10n.translate('note_presets_empty'),
                      style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final preset in presets)
                          ActionChip(
                            label: Text(preset,
                                style: const TextStyle(fontSize: 17)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            onPressed: () => append(preset),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  textStyle: const TextStyle(fontSize: 17)),
              child: Text(l10n.translate('cancel')),
            ),
            // Only offered when there is something to clear, so the common case
            // isn't cluttered by a dead button.
            if (controller.text.trim().isNotEmpty)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    textStyle: const TextStyle(fontSize: 17)),
                child: Text(l10n.translate('clear')),
              ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                  textStyle: const TextStyle(fontSize: 17)),
              child: Text(l10n.translate('save')),
            ),
          ],
        );
      });
    },
  );

  controller.dispose();
  return result;
}
