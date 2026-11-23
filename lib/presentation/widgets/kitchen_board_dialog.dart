import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/kitchen_board_service.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

/// Every kitchen line of the open session, live from the till's database —
/// the same rows the KDS bumps over the LAN.
final kitchenBoardProvider =
    StreamProvider.autoDispose<List<KitchenBoardOrder>>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return Stream.value(const []);
  return KitchenBoardService(ref.watch(databaseProvider)).watch(session.id);
});

/// The kitchen as the floor sees it: what is waiting, what is cooking, what
/// is ready to go out, and how long each customer has been waiting against
/// the service target.
Future<void> showKitchenBoardDialog(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const Dialog.fullscreen(child: _KitchenBoard()),
    );

class _KitchenBoard extends ConsumerStatefulWidget {
  const _KitchenBoard();

  @override
  ConsumerState<_KitchenBoard> createState() => _KitchenBoardState();
}

class _KitchenBoardState extends ConsumerState<_KitchenBoard> {
  late final Timer _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // The clocks move without any row changing.
    _tick = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _openActions(int orderId) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => _OrderActionsDialog(orderId: orderId),
    );
    if (open != true || !mounted) return;
    final order = await ref.read(orderRepositoryProvider).getOrderById(orderId);
    if (order == null || !mounted) return;
    ref.read(orderProvider.notifier).loadOrder(order);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final target = ref.watch(settingsProvider).kitchenTargetMinutes;
    final async = ref.watch(kitchenBoardProvider);
    final orders = kitchenBoardView(async.valueOrNull ?? const [], _now);

    int count(bool Function(KitchenBoardOrder) test) =>
        orders.where(test).length;
    final waiting = count((o) => o.stage == KitchenStage.pending);
    final cooking = count((o) => o.stage == KitchenStage.preparing);
    final ready = count((o) => o.stage == KitchenStage.done);
    final late = count((o) =>
        o.stage != KitchenStage.done &&
        o.level(_now, target) == KitchenLevel.late);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('kitchen_board')),
        actions: [
          if (target > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(l10n
                    .translate('kitchen_target_label')
                    .replaceAll('{0}', '$target')),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CountChip(Icons.hourglass_top_rounded,
                    l10n.translate('kitchen_waiting'), waiting),
                _CountChip(Icons.local_fire_department_rounded,
                    l10n.translate('kitchen_cooking'), cooking),
                _CountChip(Icons.check_circle_rounded,
                    l10n.translate('kitchen_ready'), ready),
                _CountChip(Icons.alarm_rounded, l10n.translate('kitchen_late'),
                    late,
                    alert: late > 0),
              ],
            ),
          ),
          Expanded(
            child: async.isLoading && orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? Center(child: Text(l10n.translate('kitchen_empty')))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final o in orders)
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _openActions(o.id),
                                child: _OrderCard(
                                    order: o,
                                    now: _now,
                                    targetMinutes: target),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

String _clock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

Duration _since(DateTime from, DateTime now) {
  final d = now.difference(from);
  return d.isNegative ? Duration.zero : d;
}

class _CountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool alert;

  const _CountChip(this.icon, this.label, this.count, {this.alert = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: alert ? scheme.onError : null),
      label: Text('$label  $count',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: alert ? scheme.onError : null,
          )),
      backgroundColor: alert ? scheme.error : null,
    );
  }
}

class _OrderCard extends StatelessWidget {
  final KitchenBoardOrder order;
  final DateTime now;
  final int targetMinutes;

  const _OrderCard({
    required this.order,
    required this.now,
    required this.targetMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final done = order.stage == KitchenStage.done;
    final level = order.level(now, targetMinutes);
    final accent = done
        ? scheme.secondary
        : switch (level) {
            KitchenLevel.late => scheme.error,
            KitchenLevel.warn => scheme.tertiary,
            KitchenLevel.ok => scheme.outlineVariant,
          };
    final title = order.number != null ? '#${order.number}' : order.code;
    final where = order.table ?? l10n.translate(order.type.toLowerCase());

    return SizedBox(
      width: 300,
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: accent, width: level == KitchenLevel.ok ? 1 : 3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            if (order.rush && !done) ...[
                              const SizedBox(width: 6),
                              _RushBadge(label: l10n.translate('kitchen_rush')),
                            ],
                          ],
                        ),
                        Text(
                            [
                              where,
                              if ((order.reference ?? '').isNotEmpty)
                                order.reference!,
                            ].join(' · '),
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _clock(order.age(now)),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: level == KitchenLevel.ok && !done
                              ? null
                              : accent,
                        ),
                      ),
                      Text(
                        l10n.translate(switch (order.stage) {
                          KitchenStage.pending => 'kitchen_waiting',
                          KitchenStage.preparing => 'kitchen_cooking',
                          KitchenStage.done => 'kitchen_ready',
                        }),
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),
              for (final line in order.lines) _LineRow(line: line, now: now),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  final KitchenBoardLine line;
  final DateTime now;

  const _LineRow({required this.line, required this.now});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String label) = line.isDone
        ? (Icons.check_circle_rounded, scheme.secondary,
            l10n.translate('kitchen_ready'))
        : line.isPreparing
            ? (Icons.local_fire_department_rounded, scheme.primary,
                l10n.translate('kitchen_cooking'))
            : (Icons.hourglass_top_rounded, scheme.outline,
                l10n.translate('kitchen_waiting'));
    // Waiting counts from arrival, cooking from when the kitchen started.
    final clock = line.isDone
        ? null
        : _since(
            line.isPreparing ? (line.preparingAt ?? line.kitchenAt) : line.kitchenAt,
            now);
    final qty = line.quantity == line.quantity.roundToDouble()
        ? line.quantity.toStringAsFixed(0)
        : line.quantity.toStringAsFixed(3);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(message: label, child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$qty × ${line.name}',
                  style: TextStyle(
                    decoration:
                        line.isDone ? TextDecoration.lineThrough : null,
                    color: line.isDone ? scheme.onSurfaceVariant : null,
                  ),
                ),
                if (line.station != null || (line.note ?? '').isNotEmpty)
                  Text(
                    [
                      if (line.station != null) line.station!,
                      if ((line.note ?? '').isNotEmpty) line.note!,
                    ].join(' · '),
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (clock != null)
            Text(
              _clock(clock),
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _RushBadge extends StatelessWidget {
  final String label;

  const _RushBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.error,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.priority_high_rounded, size: 14, color: scheme.onError),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: scheme.onError)),
        ],
      ),
    );
  }
}

/// What the till can do with one order from the kitchen board: hurry the
/// kitchen, move its lines (exactly as a KDS bump would — the KDS follows on
/// its next poll), or open it in the cart. Pops `true` for "open".
class _OrderActionsDialog extends ConsumerStatefulWidget {
  final int orderId;

  const _OrderActionsDialog({required this.orderId});

  @override
  ConsumerState<_OrderActionsDialog> createState() =>
      _OrderActionsDialogState();
}

class _OrderActionsDialogState extends ConsumerState<_OrderActionsDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) SnackBarHelper.failure(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLines(Iterable<KitchenBoardLine> lines, String state) =>
      _run(() async {
        final server = ref.read(serverServiceProvider);
        for (final l in lines) {
          await server.applyKitchenLineState(l.id, state);
        }
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final orders = ref.watch(kitchenBoardProvider).valueOrNull ?? const [];
    final order = orders.where((o) => o.id == widget.orderId).firstOrNull;
    if (order == null) {
      return AlertDialog(
        content: Text(l10n.translate('kitchen_empty')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.translate('close')),
          ),
        ],
      );
    }
    final canAct = ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ordersUpdate);
    final cartEmpty = ref.watch(orderProvider).items.isEmpty;
    final open = order.lines.where((l) => !l.isDone);
    final title = order.number != null
        ? '#${order.number} · ${order.code}'
        : order.code;

    Widget stateChip(KitchenBoardLine line, String state, String labelKey,
        IconData icon) {
      final selected = switch (state) {
        'PENDING' => line.isPending,
        'PREPARING' => line.isPreparing,
        _ => line.isDone,
      };
      return ChoiceChip(
        avatar: Icon(icon, size: 16),
        label: Text(l10n.translate(labelKey)),
        selected: selected,
        onSelected: !canAct || selected || _busy
            ? null
            : (_) => _setLines([line], state),
      );
    }

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(title)),
          if (order.rush && order.stage != KitchenStage.done)
            _RushBadge(label: l10n.translate('kitchen_rush')),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if ((order.reference ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${l10n.translate('order_reference')}: ${order.reference}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final line in order.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${line.quantity == line.quantity.roundToDouble() ? line.quantity.toStringAsFixed(0) : line.quantity.toStringAsFixed(3)} × ${line.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          stateChip(line, 'PENDING', 'kitchen_waiting',
                              Icons.hourglass_top_rounded),
                          stateChip(line, 'PREPARING', 'kitchen_cooking',
                              Icons.local_fire_department_rounded),
                          stateChip(line, 'COMPLETED', 'kitchen_ready',
                              Icons.check_circle_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: order.rush ? null : scheme.error,
                      foregroundColor: order.rush ? null : scheme.onError,
                    ),
                    icon: Icon(order.rush
                        ? Icons.notifications_off_outlined
                        : Icons.notification_important_rounded),
                    label: Text(l10n.translate(
                        order.rush ? 'kitchen_rush_clear' : 'kitchen_rush_send')),
                    onPressed: !canAct || _busy || open.isEmpty
                        ? null
                        : () => _run(() => ref
                            .read(serverServiceProvider)
                            .setOrderRush(order.id, !order.rush)),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.local_fire_department_rounded),
                    label: Text(l10n.translate('kitchen_start_all')),
                    onPressed: !canAct ||
                            _busy ||
                            !order.lines.any((l) => l.isPending)
                        ? null
                        : () => _setLines(
                            order.lines.where((l) => l.isPending), 'PREPARING'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded),
                    label: Text(l10n.translate('kitchen_all_ready')),
                    onPressed: !canAct || _busy || open.isEmpty
                        ? null
                        : () => _setLines(open, 'COMPLETED'),
                  ),
                ],
              ),
              if (!canAct)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(l10n.translate('no_permission'),
                      style: TextStyle(color: scheme.error, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('close')),
        ),
        Tooltip(
          // Loading it would replace whatever is being rung up.
          message: cartEmpty ? '' : l10n.translate('kitchen_open_cart_busy'),
          child: FilledButton.icon(
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(l10n.translate('kitchen_open_order')),
            onPressed: cartEmpty ? () => Navigator.pop(context, true) : null,
          ),
        ),
      ],
    );
  }
}
