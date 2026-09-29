import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart' show currentUserProvider;
import '../../services/lan_notification_hub.dart';
import '../../services/waiter_call_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import 'adaptive_text_field.dart';

/// Rings a waiter's phone, optionally with a message.
///
/// The message is optional on purpose — the overwhelmingly common call is
/// "come here", and a dialog that demanded a sentence for it would get used
/// twice and then avoided. The presets exist for the same reason: the
/// second-most-common calls should also be one tap, not typing.
class CallWaiterDialog extends ConsumerStatefulWidget {
  final int waiterId;
  final String waiterName;

  /// The table the call is about, when it started from one. Shown to the
  /// waiter so they know where to go without reading the message.
  final int? tableId;
  final String? tableName;

  const CallWaiterDialog({
    super.key,
    required this.waiterId,
    required this.waiterName,
    this.tableId,
    this.tableName,
  });

  @override
  ConsumerState<CallWaiterDialog> createState() => _CallWaiterDialogState();
}

class _CallWaiterDialogState extends ConsumerState<CallWaiterDialog> {
  final _controller = TextEditingController();
  bool _sending = false;

  /// l10n keys for the one-tap messages. Tapping one fills the field rather
  /// than sending immediately, so a preset can still be edited into something
  /// specific ("customer waiting — table 4 too").
  static const _presetKeys = [
    'call_waiter_preset_come',
    'call_waiter_preset_customer_waiting',
    'call_waiter_preset_order_ready',
    'call_waiter_preset_bill_requested',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);

    final l10n = AppLocalizations.of(context)!;
    final user = ref.read(currentUserProvider);
    final from = (user?.displayName?.trim().isNotEmpty ?? false)
        ? user!.displayName!.trim()
        : '${user?.firstName ?? ''} ${user?.lastName ?? ''}'.trim();

    try {
      final result = await ref.read(waiterCallServiceProvider).call(
            waiterId: widget.waiterId,
            waiterName: widget.waiterName,
            message: _controller.text,
            tableId: widget.tableId,
            tableName: widget.tableName,
            fromUser: from.isEmpty ? l10n.translate('cashier') : from,
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);

      // Tell the cashier whether a phone actually got it. "Sent" alone would
      // be a lie when the waiter is not logged in, and the cashier would stand
      // there waiting instead of walking over.
      if (result.devices > 0) {
        SnackBarHelper.success(
          context,
          l10n
              .translate('call_waiter_sent')
              .replaceAll('{0}', widget.waiterName),
        );
      } else {
        SnackBarHelper.warning(
          context,
          l10n
              .translate('call_waiter_queued')
              .replaceAll('{0}', widget.waiterName),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      SnackBarHelper.error(context, l10n.translate('call_waiter_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    // Live device count: the cashier sees "not connected" before typing a
    // message nobody will read.
    final devices = ref
        .watch(lanNotificationHubProvider)
        .subscriberCount('waiter:${widget.waiterId}');

    return AlertDialog(
      icon: Icon(Icons.notifications_active, color: cs.primary, size: 32),
      title: Text(
        l10n.translate('call_waiter_title').replaceAll('{0}', widget.waiterName),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.tableName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.table_restaurant,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(
                      widget.tableName!,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              children: [
                Icon(
                  devices > 0 ? Icons.smartphone : Icons.mobile_off,
                  size: 16,
                  color: devices > 0 ? cs.primary : cs.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    devices > 0
                        ? l10n
                            .translate('call_waiter_devices')
                            .replaceAll('{0}', '$devices')
                        : l10n.translate('call_waiter_not_connected'),
                    style: TextStyle(
                      fontSize: 12,
                      color: devices > 0 ? cs.onSurfaceVariant : cs.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetKeys.map((key) {
                final text = l10n.translate(key);
                return ActionChip(
                  label: Text(text),
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                            _controller.text = text;
                          }),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            AdaptiveKeyboardTextField(
              controller: _controller,
              autofocus: false,
              maxLines: 2,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.translate('call_waiter_message_optional'),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: cs.surfaceContainerHigh,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.translate('cancel')),
        ),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.campaign),
          label: Text(l10n.translate('call_waiter_send')),
        ),
      ],
    );
  }
}

/// Opens [CallWaiterDialog]. Returns true when a call was actually placed.
Future<bool> showCallWaiterDialog(
  BuildContext context, {
  required int waiterId,
  required String waiterName,
  int? tableId,
  String? tableName,
}) async {
  final sent = await showDialog<bool>(
    context: context,
    builder: (_) => CallWaiterDialog(
      waiterId: waiterId,
      waiterName: waiterName,
      tableId: tableId,
      tableName: tableName,
    ),
  );
  return sent ?? false;
}
