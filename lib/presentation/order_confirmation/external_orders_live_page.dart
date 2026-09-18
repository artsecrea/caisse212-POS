import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils/customer_display.dart';
import '../../providers/external_orders_live_provider.dart';
import '../../providers/network_provider.dart';
import '../widgets/order_source_badge.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// Orders already accepted from a platform, and what to do with them next.
///
/// The incoming queue answers "should we take this job?". This page answers
/// "is it done?" — it is the counter's view while food is being made, and the
/// place the kitchen tells the platform an order is waiting.
class ExternalOrdersLivePage extends ConsumerStatefulWidget {
  const ExternalOrdersLivePage({super.key});

  @override
  ConsumerState<ExternalOrdersLivePage> createState() =>
      _ExternalOrdersLivePageState();
}

class _ExternalOrdersLivePageState
    extends ConsumerState<ExternalOrdersLivePage> {
  /// Orders being signalled right now, so a second tap cannot fire a second
  /// call while the first is in flight.
  final Set<int> _signalling = {};

  /// Hide handed-over orders by default: the counter cares about what is still
  /// owed, and a day of completed deliveries buries it.
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final async = ref.watch(liveExternalOrdersProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorText(e, l10n))),
      data: (all) {
        final open = all.where((o) => !o.isReadySignalled && !o.isCancelled);
        final done = all.where((o) => o.isReadySignalled || o.isCancelled);
        final shown = [...open, if (_showDone) ...done];

        return Column(
          children: [
            _buildHeader(theme, l10n, open.length, done.length),
            Expanded(
              child: shown.isEmpty
                  ? _buildEmpty(theme, l10n)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: shown.length,
                      itemBuilder: (context, i) =>
                          _buildOrderCard(theme, l10n, shown[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(
      ThemeData theme, AppLocalizations l10n, int openCount, int doneCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '$openCount ${l10n.translate('awaiting_pickup')}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          if (doneCount > 0)
            TextButton.icon(
              onPressed: () => setState(() => _showDone = !_showDone),
              icon: Icon(
                  _showDone ? Icons.visibility_off_outlined : Icons.history,
                  size: 16),
              label: Text(
                _showDone
                    ? l10n.translate('hide_done')
                    : '${l10n.translate('show_done')} ($doneCount)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(
            l10n.translate('no_orders_in_progress'),
            style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(
      ThemeData theme, AppLocalizations l10n, LiveExternalOrder o) {
    final formatter = ref.watch(currencyFormatterProvider);
    final order = o.order;
    final busy = _signalling.contains(order.id);

    final accent = o.isCancelled
        ? theme.colorScheme.error
        : (o.isReadySignalled ? Colors.green.shade600 : theme.colorScheme.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OrderSourceBadge(source: order.source, size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // The courier asks for the platform's code, not ours.
                        order.externalOrderCode?.isNotEmpty == true
                            ? order.externalOrderCode!
                            : order.code,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${o.itemCount} ${l10n.translate('items')}'
                        '  ·  ${formatter.format(o.total)}'
                        '  ·  ${_timeAgo(order.date, l10n)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                _statusChip(theme, l10n, o),
              ],
            ),
            const Divider(height: 18),
            ...o.lines.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${_qty(l.quantity)}x',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.productNames[l.productId] ??
                                'Product #${l.productId}'),
                            if (l.note != null && l.note!.isNotEmpty)
                              Text(
                                l.note!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            if (order.note?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              _infoLine(theme, Icons.sticky_note_2_outlined, order.note!),
            ],
            if (o.customer != null)
              _infoLine(theme, Icons.person_outline,
                  '${o.customer!.displayLabel}'
                  '${o.customer!.phone != null ? ' · ${o.customer!.phone}' : ''}'),
            if (order.address?.isNotEmpty == true)
              _infoLine(theme, Icons.place_outlined, order.address!),
            if (order.courierName?.isNotEmpty == true)
              _infoLine(
                  theme,
                  Icons.delivery_dining,
                  '${order.courierName}'
                  '${order.courierPhone != null ? ' · ${order.courierPhone}' : ''}'),
            const SizedBox(height: 10),
            _buildAction(theme, l10n, o, busy),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(ThemeData theme, AppLocalizations l10n,
      LiveExternalOrder o, bool busy) {
    if (o.isCancelled) {
      return Text(
        l10n.translate('order_cancelled'),
        style: TextStyle(
            color: theme.colorScheme.error, fontWeight: FontWeight.w600),
      );
    }
    if (o.isReadySignalled) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Text(
            l10n.translate('platform_notified'),
            style: TextStyle(
                color: Colors.green.shade700, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    // The signal has no offline queue by design, so the button says why it is
    // unavailable rather than failing after the tap.
    final online = ref.watch(lastKnownOnlineStatusProvider);

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.icon(
        onPressed: busy || !online ? null : () => _markReady(o),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.room_service_outlined, size: 18),
        label: Text(online
            ? l10n.translate('mark_ready_for_pickup')
            : l10n.translate('error_offline')),
      ),
    );
  }

  Future<void> _markReady(LiveExternalOrder o) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _signalling.add(o.order.id));
    try {
      final signalled = await ref.read(signalReadyProvider)(o.order);
      if (!mounted) return;
      if (signalled) {
        SnackBarHelper.success(context, l10n.translate('platform_notified'));
      } else {
        // False is either "not synced yet" or "network died". Both leave the
        // platform uninformed, which is the only thing the counter needs told.
        SnackBarHelper.error(context, l10n.translate('ready_signal_failed'));
      }
    } catch (e) {
      if (mounted) SnackBarHelper.failure(context, e);
    } finally {
      if (mounted) setState(() => _signalling.remove(o.order.id));
    }
  }

  Widget _statusChip(
      ThemeData theme, AppLocalizations l10n, LiveExternalOrder o) {
    final (label, color) = o.isCancelled
        ? (l10n.translate('cancelled'), theme.colorScheme.error)
        : o.isReadySignalled
            ? (l10n.translate('ready'), Colors.green.shade600)
            : (l10n.translate('preparing'), Colors.orange.shade700);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _infoLine(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

  String _timeAgo(DateTime? dt, AppLocalizations l10n) {
    if (dt == null) return '';
    final minutes = DateTime.now().difference(dt).inMinutes;
    if (minutes < 1) return l10n.translate('just_now');
    if (minutes < 60) return '$minutes min';
    return '${(minutes / 60).floor()}h';
  }
}
