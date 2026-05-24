import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/external_order_models.dart';
import '../../providers/external_order_provider.dart';
import '../../utils/app_localizations.dart';
import '../order_confirmation/order_confirmation_screen.dart';

/// Tab content showing pending external orders (DealUp / WhatsApp).
/// Displayed as the second tab in OrdersManagementScreen.
class ExternalOrdersTab extends ConsumerWidget {
  const ExternalOrdersTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(externalOrderProvider);
    final l10n = AppLocalizations.of(context)!;

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Error banner
        if (state.error != null)
          _ErrorBanner(
            message: state.error!,
            onDismiss: () =>
                ref.read(externalOrderProvider.notifier).load(),
          ),

        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                '${state.items.length} pending',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l10n.translate('refresh'),
                onPressed: () =>
                    ref.read(externalOrderProvider.notifier).load(),
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: state.items.isEmpty
              ? _EmptyView(l10n: l10n)
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: state.items.length,
                  itemBuilder: (context, index) {
                    final item = state.items[index];
                    return _QueueItemCard(
                      key: ValueKey(item.id),
                      item: item,
                      onReview: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              const OrderConfirmationScreen(initialTab: 1),
                        ));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _QueueItemCard extends StatelessWidget {
  final ExternalQueueItem item;
  final VoidCallback onReview;

  const _QueueItemCard({
    super.key,
    required this.item,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = item.order;
    final timeAgo = _formatTimeAgo(item.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: source badge + code + time + confirm button
            Row(
              children: [
                _SourceBadge(source: item.source),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.orderCode,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                _TypeChip(type: order.type),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: onReview,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Review',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Customer info
            if (order.customerName != null || order.customerPhone != null) ...[
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 15,
                      color: Colors.grey),
                  const SizedBox(width: 5),
                  if (order.customerName != null)
                    Text(order.customerName!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  if (order.customerPhone != null) ...[
                    const SizedBox(width: 8),
                    Text(order.customerPhone!,
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 6),
            ],

            // Items
            ...order.items.map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '${it.quantity}×',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Product #${it.productId}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      if (it.components.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(+${it.components.length} comp.)',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 11),
                        ),
                      ],
                      if (it.note != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '— ${it.note}',
                          style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 11,
                              fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                )),

            // Note
            if (order.note != null && order.note!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.notes, size: 14, color: Colors.orange[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.note!,
                      style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (source.toUpperCase()) {
      'DEALUP' => (Colors.deepPurple, Icons.local_offer),
      'WHATSAPP' => (Colors.green[700]!, Icons.chat),
      _ => (Colors.blueGrey, Icons.cloud),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            ExternalQueueItem(
              id: 0,
              orderCode: '',
              source: source,
              status: '',
              order: ExternalQueueOrder(type: '', items: []),
              createdAt: DateTime.now(),
            ).sourceLabel,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      'DELIVERY' => 'Delivery',
      'TAKE_AWAY' => 'Take Away',
      'DINE_IN' => 'Dine In',
      _ => type,
    };
    final color = switch (type) {
      'DELIVERY' => Colors.orange,
      'TAKE_AWAY' => Colors.blue,
      _ => Colors.teal,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyView({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            'No pending external orders',
            style: TextStyle(color: Colors.grey[500], fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'DealUp / WhatsApp orders will appear here',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Retry',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
