import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/kds_stats_provider.dart';
import '../../services/kds_stats_service.dart';

/// Read-only kitchen analytics for the current shift (LAN/local only).
/// Reads [kdsSessionStatsProvider]; pull-to-refresh via the header button
/// since KDS states change out-of-band through the LAN endpoints.
Future<void> showKdsStatsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: _KdsStatsView()),
  );
}

class _KdsStatsView extends ConsumerWidget {
  const _KdsStatsView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(kdsSessionStatsProvider);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
            child: Row(
              children: [
                Icon(Icons.insights, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text('Kitchen stats — current shift',
                    style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.invalidate(kdsSessionStatsProvider),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Failed to load stats:\n$e',
                    style: TextStyle(color: theme.colorScheme.error)),
              ),
              data: (s) => _StatsBody(stats: s),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  final KdsSessionStats stats;
  const _StatsBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (!stats.hasData) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Text('No kitchen activity in the current session yet.',
              textAlign: TextAlign.center),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Avg prep time',
              value: _fmtDur(stats.avgPrepTime),
              sub: '${stats.prepSampleCount} items',
              icon: Icons.timer_outlined,
            ),
            _MetricCard(
              label: 'Median prep',
              value: _fmtDur(stats.medianPrepTime),
              sub: 'ready − preparing',
              icon: Icons.speed,
            ),
            _MetricCard(
              label: 'Avg pickup wait',
              value: _fmtDur(stats.avgPickupWait),
              sub: '${stats.pickupSampleCount} items',
              icon: Icons.room_service_outlined,
            ),
            _MetricCard(
              label: 'Items served',
              value: '${stats.itemsServed}',
              sub: 'this shift',
              icon: Icons.check_circle_outline,
            ),
            _MetricCard(
              label: 'Live backlog',
              value: '${stats.liveBacklog}',
              sub: 'in kitchen now',
              icon: Icons.pending_actions,
            ),
            _MetricCard(
              label: 'Kitchen cancels',
              value: '${stats.kitchenCancels}',
              sub: 'after firing',
              icon: Icons.cancel_outlined,
            ),
          ],
        ),
        if (stats.throughputByStation.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Throughput by station',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...stats.throughputByStation.map((t) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restaurant),
                title: Text(t.stationName),
                trailing: Text(
                  '${t.itemsServed} items · ${_fmtQty(t.quantityServed)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )),
        ],
      ],
    );
  }

  static String _fmtDur(Duration? d) {
    if (d == null) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  static String _fmtQty(double q) {
    final r = q.roundToDouble();
    return r == q ? '${r.toInt()} qty' : '${q.toStringAsFixed(2)} qty';
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 148,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: theme.textTheme.labelMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(sub,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
