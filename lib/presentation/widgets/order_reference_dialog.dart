import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import 'adaptive_text_field.dart';

/// Edit the current order's take-away / delivery reference — the name called
/// out at the pickup, a platform's order number. Cancel leaves it as it was;
/// saving a blank clears it.
Future<void> showOrderReferenceDialog(
    BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final controller =
      TextEditingController(text: ref.read(orderProvider).reference ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l10n.translate('order_reference'),
                style: const TextStyle(fontSize: 22)),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: AdaptiveKeyboardTextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: l10n.translate('order_reference_hint'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              textStyle: const TextStyle(fontSize: 17)),
          child: Text(l10n.translate('skip')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              textStyle: const TextStyle(fontSize: 17)),
          child: Text(l10n.translate('save')),
        ),
      ],
    ),
  );
  if (saved == true) {
    ref.read(orderProvider.notifier).setReference(controller.text);
  }
  controller.dispose();
}
