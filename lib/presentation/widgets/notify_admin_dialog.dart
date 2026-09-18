import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../services/notification_params.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import './adaptive_text_field.dart';

/// Send a free-form `GENERAL` notification from the terminal to the admin
/// devices — "power outage, closing early", "card machine down".
///
/// This is the POS side of the `GENERAL` notification type, which the contract
/// lists as POS-sent but which previously had no sender at all.
///
/// Distinct from Report Issue: that files a support ticket via `/pos/issues`
/// for someone to work through later. This pushes a notification to the owner's
/// phone now.
Future<void> showNotifyAdminDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final titleCtrl = TextEditingController();
  final bodyCtrl = TextEditingController();
  var busy = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final cs = Theme.of(ctx).colorScheme;

      Future<void> send() async {
        if (titleCtrl.text.trim().isEmpty) {
          SnackBarHelper.error(ctx, l10n.translate('title_required'));
          return;
        }
        setLocal(() => busy = true);
        try {
          final api = ref.read(apiServiceProvider);
          await api.postNotification(
            type: 'GENERAL',
            params: NotificationParams.general(
              terminalName: api.getPosName() ?? '',
              title: titleCtrl.text,
              body: bodyCtrl.text,
            ),
          );
          if (ctx.mounted) {
            Navigator.pop(ctx);
            SnackBarHelper.success(ctx, l10n.translate('message_sent'));
          }
        } catch (e) {
          setLocal(() => busy = false);
          if (ctx.mounted) {
            // Explicitly NOT queued for retry: a "closing early" message
            // delivered tomorrow is worse than not delivered — the cashier
            // needs to know now so they can phone instead.
            SnackBarHelper.error(ctx, l10n.translate('message_send_failed'));
          }
        }
      }

      return AlertDialog(
        title: Row(children: [
          Icon(Icons.campaign_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.translate('notify_admin'))),
        ]),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.translate('notify_admin_hint'),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              AdaptiveKeyboardTextField(
                controller: titleCtrl,
                // Hard caps matching the contract, so the push title can't be
                // silently truncated somewhere downstream.
                maxLength: NotificationParams.generalTitleMax,
                decoration: InputDecoration(
                  labelText: l10n.translate('title'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.title),
                ),
                onChanged: (_) => setLocal(() {}),
              ),
              const SizedBox(height: 8),
              AdaptiveKeyboardTextField(
                controller: bodyCtrl,
                maxLines: 3,
                maxLength: NotificationParams.generalBodyMax,
                decoration: InputDecoration(
                  labelText: l10n.translate('message_optional'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.notes),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: busy || titleCtrl.text.trim().isEmpty ? null : send,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(l10n.translate('send')),
          ),
        ],
      );
    }),
  );

  titleCtrl.dispose();
  bodyCtrl.dispose();
}
