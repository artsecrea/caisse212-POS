import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/network_watch_service.dart';
import '../../utils/app_localizations.dart';
import 'diagnostics_controller.dart';
import 'diagnostics_panel.dart';

String watchKindKey(WatchKind k) => switch (k) {
      WatchKind.internet => 'diag_internet',
      WatchKind.backend => 'diag_backend',
      WatchKind.router => 'diag_gateway',
      WatchKind.printer => 'diag_printers',
    };

IconData _icon(WatchKind k) => switch (k) {
      WatchKind.internet => Icons.public,
      WatchKind.backend => Icons.cloud,
      WatchKind.router => Icons.router,
      WatchKind.printer => Icons.print,
    };

class WatchPage extends ConsumerWidget {
  const WatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(networkWatchProvider);
    return ListenableBuilder(listenable: w, builder: (context, _) => _build(context, w));
  }

  Widget _build(BuildContext context, NetworkWatchService w) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final s = w.settings;
    final events = w.events;
    return DiagPageScaffold(
      title: l.translate('diag_page_watch'),
      subtitle: l.translate('diag_watch_hint'),
      actions: [
        FilledButton.icon(
          onPressed: w.checking || !s.enabled ? null : w.checkNow,
          icon: w.checking
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
          label: Text(l.translate('diag_check_now')),
        ),
      ],
      children: [
        DiagSection(
          icon: Icons.tune,
          title: l.translate('diag_watch_settings'),
          child: Column(children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.translate('diag_watch_enabled')),
              subtitle: Text(l.translate('diag_watch_enabled_hint')),
              value: s.enabled,
              onChanged: (v) => w.updateSettings(s.copyWith(enabled: v)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: s.enabled,
              title: Text(l.translate('diag_watch_interval')),
              trailing: DropdownButton<int>(
                value: s.intervalMinutes,
                onChanged: !s.enabled
                    ? null
                    : (v) => w.updateSettings(s.copyWith(intervalMinutes: v)),
                items: [
                  for (final m in const [1, 2, 5, 10, 15])
                    DropdownMenuItem(value: m, child: Text('$m min')),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.translate('diag_watch_toast')),
              value: s.alertOnTill,
              onChanged: !s.enabled ? null : (v) => w.updateSettings(s.copyWith(alertOnTill: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.translate('diag_watch_notify')),
              subtitle: Text(l.translate('diag_watch_notify_hint')),
              value: s.notifyOwner,
              onChanged: !s.enabled ? null : (v) => w.updateSettings(s.copyWith(notifyOwner: v)),
            ),
          ]),
        ),
        DiagSection(
          icon: Icons.sensors,
          title: l.translate('diag_watch_now'),
          child: w.status.isEmpty
              ? Text(
                  l.translate(s.enabled ? 'diag_watch_waiting' : 'diag_off'),
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (w.lastCheck != null)
                    Text(
                        l.translate('diag_last_run').replaceAll(
                            '{time}', TimeOfDay.fromDateTime(w.lastCheck!).format(context)),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final e in w.status.entries)
                      Chip(
                        avatar: Icon(e.value ? Icons.check_circle : Icons.cancel,
                            size: 18, color: e.value ? Colors.green.shade600 : scheme.error),
                        label: Text('${w.labelOf(e.key)}'
                            '${e.key.startsWith('printer|') ? ' (${e.key.substring(8)})' : ''}'),
                      ),
                  ]),
                ]),
        ),
        DiagSection(
          icon: Icons.insights,
          title: l.translate('diag_watch_week'),
          child: Wrap(spacing: 32, runSpacing: 12, children: [
            for (final k in WatchKind.values)
              () {
                final (d, n) = w.downtime(k, const Duration(days: 7));
                final pct = 100 - d.inSeconds / const Duration(days: 7).inSeconds * 100;
                return DiagMetric(
                  icon: _icon(k),
                  label: l.translate(watchKindKey(k)),
                  value: n == 0
                      ? '100%'
                      : '${pct.toStringAsFixed(pct > 99.9 ? 2 : 1)}% · $n× · ${formatDuration(d)}',
                  large: true,
                );
              }(),
          ]),
        ),
        DiagSection(
          icon: Icons.history,
          title: l.translate('diag_watch_history'),
          actions: [
            if (events.any((e) => e.up != null))
              TextButton.icon(
                onPressed: w.clearHistory,
                icon: const Icon(Icons.delete_sweep, size: 18),
                label: Text(l.translate('diag_clear_history')),
              ),
          ],
          child: events.isEmpty
              ? Text(l.translate('watch_no_outage'),
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(children: [
                  for (final e in events.take(100))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_icon(e.kind),
                          color: e.up == null ? scheme.error : scheme.onSurfaceVariant),
                      title: Text(e.kind == WatchKind.printer
                          ? '${e.label} (${e.address})'
                          : l.translate(watchKindKey(e.kind))),
                      subtitle: Text(e.up == null
                          ? '${formatDateTime(e.down)} → ${l.translate('diag_still_down')}'
                          : '${formatDateTime(e.down)} → ${formatDateTime(e.up!)}'),
                      trailing: Text(formatDuration(e.duration()),
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: e.up == null ? scheme.error : null)),
                    ),
                ]),
        ),
      ],
    );
  }
}
