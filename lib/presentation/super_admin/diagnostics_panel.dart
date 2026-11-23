import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/diagnostics_service.dart';
import '../../services/network_watch_service.dart';
import '../../services/notification_params.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import 'devices_pages.dart';
import 'diagnostics_controller.dart';
import 'printers_page.dart';
import 'traffic_tools_pages.dart';
import 'watch_page.dart';

/// Super admin "Diagnostics" tab: a menu of pages — overview, clock,
/// network, Wi-Fi, devices, cameras, printers, traffic, tools, watch.
class DiagnosticsPanel extends ConsumerStatefulWidget {
  /// A controller already filled by the caller, which then owns it; the
  /// panel runs its own checks only when it creates one itself.
  final DiagnosticsController? controller;
  const DiagnosticsPanel({super.key, this.controller});

  @override
  ConsumerState<DiagnosticsPanel> createState() => _DiagnosticsPanelState();
}

class _DiagnosticsPanelState extends ConsumerState<DiagnosticsPanel> {
  late final DiagnosticsController _c = widget.controller ??
      DiagnosticsController(
        prefs: ref.read(sharedPreferencesProvider),
        printing: ref.read(printingServiceProvider),
        lanPort: ref.read(settingsProvider).serverPort ?? 8080,
      );
  DiagPage _page = DiagPage.overview;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Addresses first: they are instant, and the scan must not wait for
      // the full check. The check then re-picks the gateway's subnet.
      await _c.loadScanTargets();
      if (!mounted) return;
      await _c.runAll(AppLocalizations.of(context)!);
      _c.pickDefaultTarget();
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _go(DiagPage p) => setState(() => _page = p);

  static IconData iconOf(DiagPage p) => switch (p) {
        DiagPage.overview => Icons.dashboard,
        DiagPage.system => Icons.schedule,
        DiagPage.network => Icons.lan,
        DiagPage.wifi => Icons.wifi_find,
        DiagPage.devices => Icons.radar,
        DiagPage.cameras => Icons.videocam,
        DiagPage.printers => Icons.print,
        DiagPage.traffic => Icons.swap_vert,
        DiagPage.tools => Icons.terminal,
        DiagPage.watch => Icons.monitor_heart,
      };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (!DiagnosticsService.supported) {
      return Center(child: Text(l.translate('os_accounts_unsupported')));
    }
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final issues = _c.issues(l);
        final pages = <DiagPage, Widget>{
          DiagPage.overview: OverviewPage(c: _c, issues: issues, onOpen: _go),
          DiagPage.system: SystemPage(c: _c),
          DiagPage.network: NetworkPage(c: _c),
          DiagPage.wifi: WifiPage(c: _c),
          DiagPage.devices: DevicesPage(c: _c),
          DiagPage.cameras: CamerasPage(c: _c),
          DiagPage.printers: PrintersPage(c: _c),
          DiagPage.traffic: const TrafficPage(),
          DiagPage.tools: ToolsPage(c: _c),
          DiagPage.watch: const WatchPage(),
        };
        final body = IndexedStack(
          index: _page.index,
          children: [for (final p in DiagPage.values) pages[p]!],
        );
        return LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 760;
          final nav = _Nav(
            current: _page,
            issues: issues,
            horizontal: !wide,
            onSelect: _go,
          );
          return wide
              ? Row(children: [
                  nav,
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ])
              : Column(children: [
                  nav,
                  const Divider(height: 1),
                  Expanded(child: body),
                ]);
        });
      },
    );
  }
}

class _Nav extends StatelessWidget {
  final DiagPage current;
  final List<DiagIssue> issues;
  final bool horizontal;
  final ValueChanged<DiagPage> onSelect;
  const _Nav({
    required this.current,
    required this.issues,
    required this.horizontal,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    Widget? badge(DiagPage p) {
      final mine = issues.where((i) => i.page == p).toList();
      if (p == DiagPage.overview || mine.isEmpty) return null;
      final error = mine.any((i) => i.severity == Severity.error);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: error ? scheme.error : Colors.orange.shade700,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('${mine.length}',
            style: TextStyle(
                fontSize: 11,
                color: error ? scheme.onError : Colors.white,
                fontWeight: FontWeight.w700)),
      );
    }

    if (horizontal) {
      return SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final p in DiagPage.values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(_DiagnosticsPanelState.iconOf(p), size: 18),
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(l.translate('diag_page_${p.name}')),
                    if (badge(p) case final b?) ...[const SizedBox(width: 4), b],
                  ]),
                  selected: current == p,
                  onSelected: (_) => onSelect(p),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      width: 220,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        children: [
          for (final p in DiagPage.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: ListTile(
                dense: true,
                minLeadingWidth: 24,
                horizontalTitleGap: 12,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                selected: current == p,
                selectedTileColor: scheme.secondaryContainer,
                selectedColor: scheme.onSecondaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Icon(_DiagnosticsPanelState.iconOf(p)),
                title: Text(l.translate('diag_page_${p.name}'),
                    style: const TextStyle(fontSize: 14)),
                trailing: badge(p),
                onTap: () => onSelect(p),
              ),
            ),
        ],
      ),
    );
  }
}

/// A scrollable page with a title and short explanation on top.
class DiagPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  const DiagPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Text(subtitle!,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                ),
            ]),
            if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 16),
        for (final (i, w) in children.indexed) ...[
          if (i > 0) const SizedBox(height: 12),
          w,
        ],
      ],
    );
  }
}

/// Runs a repair through the controller, with its own spinner.
class FixButton extends StatelessWidget {
  final DiagnosticsController c;
  final String labelKey;
  final Future<void> Function() run;
  final bool tonal;
  const FixButton(
      {super.key, required this.c, required this.labelKey, required this.run, this.tonal = false});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final busy = c.fixing == labelKey;
    final icon = busy
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.build, size: 18);
    final onPressed = c.fixing != null
        ? null
        : () => runFix(context, () => c.fix(labelKey, run, l));
    return tonal
        ? FilledButton.tonalIcon(onPressed: onPressed, icon: icon, label: Text(l.translate(labelKey)))
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: Text(l.translate(labelKey)));
  }
}

/// Runs [action], turning OS refusals into toasts.
Future<bool> runFix(BuildContext context, Future<void> Function() action) async {
  final l = AppLocalizations.of(context)!;
  try {
    await action();
    SnackBarHelper.showToast(l.translate('diag_fix_done'), kind: ToastKind.success);
    return true;
  } on DiagnosticsException catch (e) {
    SnackBarHelper.showToast(e.cancelled ? l.translate('os_admin_refused') : e.message,
        kind: e.cancelled ? ToastKind.warning : ToastKind.error);
  } catch (e) {
    SnackBarHelper.showToast('$e', kind: ToastKind.error);
  }
  return false;
}

// ---------------------------------------------------------------- overview

class OverviewPage extends ConsumerWidget {
  final DiagnosticsController c;
  final List<DiagIssue> issues;
  final ValueChanged<DiagPage> onOpen;
  const OverviewPage({super.key, required this.c, required this.issues, required this.onOpen});

  String _watchSummary(AppLocalizations l, NetworkWatchService w) {
    final b = StringBuffer();
    for (final k in WatchKind.values) {
      final (d, n) = w.downtime(k, const Duration(days: 7));
      if (n == 0) continue;
      b.writeln('${l.translate(watchKindKey(k))}: $n × — ${formatDuration(d)} (7 d)');
    }
    return b.isEmpty ? l.translate('watch_no_outage') : b.toString().trim();
  }

  Future<void> _save(BuildContext context, String text) async {
    final l = AppLocalizations.of(context)!;
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'caisse212-diagnostic-${now.year}${two(now.month)}${two(now.day)}'
        '-${two(now.hour)}${two(now.minute)}.txt';
    final bytes = utf8.encode(text);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: l.translate('diag_save_report'),
      fileName: name,
      bytes: bytes,
    );
    if (path == null) return;
    try {
      await File(path).writeAsBytes(bytes);
      SnackBarHelper.showToast(l.translate('diag_report_saved'), kind: ToastKind.success);
    } catch (e) {
      SnackBarHelper.showToast('$e', kind: ToastKind.error);
    }
  }

  Future<void> _sendToOwner(WidgetRef ref, AppLocalizations l) async {
    try {
      final api = ref.read(apiServiceProvider);
      final body = issues.isEmpty
          ? l.translate('diag_no_problem_hint')
          : issues.map((i) => l.translate(i.titleKey)).join(' · ');
      await api.postNotification(
        type: 'GENERAL',
        params: NotificationParams.general(
          terminalName: api.getPosName() ?? '',
          title: l.translate('diag_owner_title').replaceAll('{count}', '${issues.length}'),
          body: body,
        ),
      );
      SnackBarHelper.showToast(l.translate('message_sent'), kind: ToastKind.success);
    } catch (_) {
      SnackBarHelper.showToast(l.translate('message_send_failed'), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final watch = ref.watch(networkWatchProvider);
    String report() => c.report(l, watchSummary: _watchSummary(l, watch));
    final s = c.snap;
    final internet = c.endpoints.where((e) => e.kind == EndpointKind.internet).firstOrNull;
    final wifi = s?.wifi;
    final printersOk = c.printers.where((p) => p.problems.isEmpty).length;
    return ListenableBuilder(
      listenable: watch,
      builder: (context, _) {
        final (down24, n24) = watch.downtime(WatchKind.internet, const Duration(hours: 24));
        return DiagPageScaffold(
          title: l.translate('diag_page_overview'),
          subtitle: c.ranAt == null
              ? null
              : l.translate('diag_last_run').replaceAll(
                  '{time}', TimeOfDay.fromDateTime(c.ranAt!).format(context)),
          actions: [
            FilledButton.icon(
              onPressed: c.running ? null : () => c.runAll(l),
              icon: c.running
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.health_and_safety),
              label: Text(l.translate(c.running ? 'diag_checking' : 'diag_run_all')),
            ),
            MenuAnchor(
              builder: (context, menu, _) => OutlinedButton.icon(
                onPressed: s == null ? null : () => menu.isOpen ? menu.close() : menu.open(),
                icon: const Icon(Icons.ios_share),
                label: Text(l.translate('diag_share_report')),
              ),
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.copy_all),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: report()));
                    SnackBarHelper.showToast(l.translate('diag_report_copied'),
                        kind: ToastKind.success);
                  },
                  child: Text(l.translate('diag_copy_report')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.save_alt),
                  onPressed: () => _save(context, report()),
                  child: Text(l.translate('diag_save_report')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.chat),
                  onPressed: () {
                    final text = report();
                    // wa.me links stop working past a few thousand characters.
                    final cut = text.length > 1800 ? '${text.substring(0, 1800)}\n…' : text;
                    DiagnosticsService.openUrl(
                        'https://wa.me/?text=${Uri.encodeComponent(cut)}');
                  },
                  child: Text(l.translate('diag_send_whatsapp')),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.notifications_active),
                  onPressed: () => _sendToOwner(ref, l),
                  child: Text(l.translate('diag_send_owner')),
                ),
              ],
            ),
          ],
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatusTile(
                  icon: Icons.public,
                  title: l.translate('diag_internet'),
                  value: internet == null
                      ? '…'
                      : internet.ok
                          ? '${internet.latencyMs} ms'
                          : l.translate('diag_offline'),
                  good: internet?.ok,
                  onTap: () => onOpen(DiagPage.network),
                ),
                _StatusTile(
                  icon: Icons.wifi,
                  title: 'Wi-Fi',
                  value: wifi == null
                      ? (s == null ? '…' : l.translate('diag_cable'))
                      : wifi.connected
                          ? '${wifi.signalPercent ?? '?'}% · ${wifi.ssid}'
                          : l.translate('diag_wifi_disconnected'),
                  good: wifi == null
                      ? (s == null ? null : true)
                      : wifi.connected && (wifi.signalPercent ?? 0) >= 50,
                  onTap: () => onOpen(DiagPage.wifi),
                ),
                _StatusTile(
                  icon: Icons.schedule,
                  title: l.translate('diag_clock_offset'),
                  value: c.clock == null
                      ? (c.clockChecked ? l.translate('diag_unknown') : '…')
                      : formatSkew(c.clock!.skew),
                  good: c.clock == null
                      ? null
                      : c.clock!.skew.abs() <= const Duration(seconds: 30),
                  onTap: () => onOpen(DiagPage.system),
                ),
                _StatusTile(
                  icon: Icons.print,
                  title: l.translate('diag_printers'),
                  value: c.ranAt == null
                      ? '…'
                      : c.printers.isEmpty
                          ? '—'
                          : '$printersOk / ${c.printers.length} OK',
                  good: c.ranAt == null || c.printers.isEmpty
                      ? null
                      : printersOk == c.printers.length,
                  onTap: () => onOpen(DiagPage.printers),
                ),
                _StatusTile(
                  icon: Icons.radar,
                  title: l.translate('diag_ips_used'),
                  value: c.hosts == null
                      ? l.translate('diag_not_scanned')
                      : '${c.hosts!.length} / 254',
                  good: null,
                  onTap: () => onOpen(DiagPage.devices),
                ),
                _StatusTile(
                  icon: Icons.monitor_heart,
                  title: l.translate('diag_outages_24h'),
                  value: !watch.settings.enabled
                      ? l.translate('diag_off')
                      : n24 == 0
                          ? '0'
                          : '$n24 · ${formatDuration(down24)}',
                  good: !watch.settings.enabled ? null : n24 == 0,
                  onTap: () => onOpen(DiagPage.watch),
                ),
              ],
            ),
            DiagSection(
              icon: issues.isEmpty && c.ranAt != null ? Icons.check_circle : Icons.report_problem,
              iconColor: c.ranAt == null
                  ? null
                  : issues.isEmpty
                      ? Colors.green.shade600
                      : (issues.any((i) => i.severity == Severity.error)
                          ? scheme.error
                          : Colors.orange.shade700),
              title: c.ranAt == null
                  ? l.translate('diag_problems')
                  : issues.isEmpty
                      ? l.translate('diag_no_problem')
                      : l
                          .translate('diag_problems_found')
                          .replaceAll('{count}', '${issues.length}'),
              child: c.ranAt == null
                  ? (c.running
                      ? const LinearProgressIndicator()
                      : Text(l.translate('diag_not_run')))
                  : issues.isEmpty
                      ? Text(l.translate('diag_no_problem_hint'))
                      : Column(children: [
                          for (final i in issues) IssueRow(c: c, issue: i, onOpen: onOpen),
                        ]),
            ),
          ],
        );
      },
    );
  }
}

class IssueRow extends StatelessWidget {
  final DiagnosticsController c;
  final DiagIssue issue;
  final ValueChanged<DiagPage>? onOpen;
  const IssueRow({super.key, required this.c, required this.issue, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final a = issue.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(issue.severity == Severity.error ? Icons.error : Icons.warning_amber,
            color: issue.severity == Severity.error ? scheme.error : Colors.orange.shade700),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.translate(issue.titleKey), style: const TextStyle(fontWeight: FontWeight.w600)),
            if (issue.detail.isNotEmpty)
              Text(issue.detail, style: TextStyle(color: scheme.onSurfaceVariant)),
          ]),
        ),
        if (a != null) ...[
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: c.fixing != null ? null : () => runFix(context, a.run),
            icon: c.fixing == a.labelKey
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.build, size: 18),
            label: Text(l.translate(a.labelKey)),
          ),
        ],
        if (onOpen != null)
          IconButton(
            tooltip: l.translate('diag_page_${issue.page.name}'),
            icon: const Icon(Icons.chevron_right),
            onPressed: () => onOpen!(issue.page),
          ),
      ]),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool? good;
  final VoidCallback onTap;
  const _StatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.good,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = good == null
        ? scheme.onSurfaceVariant
        : good!
            ? Colors.green.shade600
            : scheme.error;
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis),
                  Text(value,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: good == false ? color : null),
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The issues belonging to one page, shown on top of it.
class PageIssues extends StatelessWidget {
  final DiagnosticsController c;
  final DiagPage page;
  const PageIssues({super.key, required this.c, required this.page});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final mine = c.issues(l).where((i) => i.page == page).toList();
    if (mine.isEmpty) return const SizedBox.shrink();
    return DiagSection(
      icon: Icons.report_problem,
      iconColor: mine.any((i) => i.severity == Severity.error)
          ? Theme.of(context).colorScheme.error
          : Colors.orange.shade700,
      title: l.translate('diag_problems'),
      child: Column(children: [for (final i in mine) IssueRow(c: c, issue: i)]),
    );
  }
}

// ------------------------------------------------------------------ system

class SystemPage extends StatelessWidget {
  final DiagnosticsController c;
  const SystemPage({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final s = c.snap;
    final clock = c.clock;
    final skewBad = clock != null && clock.skew.abs() > const Duration(seconds: 30);
    return DiagPageScaffold(
      title: l.translate('diag_page_system'),
      subtitle: l.translate('diag_system_hint'),
      actions: [
        FixButton(c: c, labelKey: 'diag_sync_clock', run: DiagnosticsService.syncClock, tonal: true),
        TextButton.icon(
          onPressed: () => DiagnosticsService.openSettings(SettingsPage.time),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.translate('diag_open_settings')),
        ),
      ],
      children: [
        PageIssues(c: c, page: DiagPage.system),
        DiagSection(
          icon: Icons.schedule,
          title: l.translate('diag_clock'),
          child: s == null
              ? const LinearProgressIndicator()
              : KeyValues(rows: [
                  (l.translate('diag_local_time'), null),
                  (l.translate('diag_timezone'),
                      '${s.tzName.isNotEmpty ? s.tzName : s.tzId}  (UTC${formatOffset(DateTime.now().timeZoneOffset)})'),
                  (
                    l.translate('diag_clock_offset'),
                    clock != null
                        ? '${formatSkew(clock.skew)}  — ${clock.source}'
                        : (c.clockChecked ? l.translate('diag_unknown') : '…')
                  ),
                  if (s.timeServiceRunning != null)
                    (
                      l.translate('diag_time_service'),
                      s.timeServiceRunning!
                          ? '${l.translate('diag_running')}${s.ntpSource.isNotEmpty && !s.ntpSource.contains('0x8') ? ' — ${s.ntpSource}' : ''}'
                          : l.translate('diag_stopped')
                    ),
                ], valueOverrides: const {
                  0: LiveClock(),
                }, highlight: {
                  if (skewBad) 2: scheme.error,
                  if (s.timeServiceRunning == false) 3: scheme.error,
                }),
        ),
        DiagSection(
          icon: Icons.computer,
          title: l.translate('diag_os'),
          child: s == null
              ? const LinearProgressIndicator()
              : KeyValues(rows: [
                  (l.translate('diag_hostname'), s.hostname),
                  (l.translate('diag_os'), s.os),
                  if (s.bootTime != null)
                    (l.translate('diag_uptime'),
                        formatUptime(DateTime.now().difference(s.bootTime!))),
                ]),
        ),
        if (s != null && s.disks.isNotEmpty)
          DiagSection(
            icon: Icons.storage,
            title: l.translate('diag_disk'),
            child: Column(children: [
              for (final d in s.disks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    SizedBox(
                        width: 60,
                        child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 1 - d.freeFraction,
                          minHeight: 10,
                          color: d.freeFraction < 0.1 ? scheme.error : scheme.primary,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${formatBytes(d.freeBytes)} ${l.translate('diag_free_of')} '
                        '${formatBytes(d.sizeBytes)}'),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- network

/// Factory sign-ins printed in router manuals. The sticker under the
/// router is the real reference: operators change them.
const _routerLogins = [
  ('TP-Link', 'admin', 'admin'),
  ('Huawei', 'admin', 'admin'),
  ('ZTE', 'admin', 'admin'),
  ('Tenda', 'admin', 'admin'),
  ('Sagemcom', 'admin', 'admin'),
  ('D-Link', 'admin', '—'),
  ('Netgear', 'admin', 'password'),
  ('Linksys', 'admin', 'admin'),
  ('MikroTik', 'admin', '—'),
  ('Ubiquiti', 'ubnt', 'ubnt'),
];

class NetworkPage extends StatelessWidget {
  final DiagnosticsController c;
  const NetworkPage({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final s = c.snap;
    final speed = c.speed;
    final gw = c.gateway;
    final gwHost = gw == null ? null : c.hosts?.where((h) => h.ip == gw).firstOrNull;
    final brandText = '${gwHost?.vendor ?? ''} ${gwHost?.banner ?? ''}'.toLowerCase();
    return DiagPageScaffold(
      title: l.translate('diag_page_network'),
      subtitle: l.translate('diag_network_hint'),
      actions: [
        FixButton(c: c, labelKey: 'diag_flush_dns', run: DiagnosticsService.flushDns),
        FixButton(c: c, labelKey: 'diag_renew_ip', run: DiagnosticsService.renewIp),
        TextButton.icon(
          onPressed: () => DiagnosticsService.openSettings(SettingsPage.network),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.translate('diag_open_settings')),
        ),
      ],
      children: [
        PageIssues(c: c, page: DiagPage.network),
        DiagSection(
          icon: Icons.wifi,
          title: 'Wi-Fi',
          child: s == null ? const LinearProgressIndicator() : WifiTile(wifi: s.wifi),
        ),
        DiagSection(
          icon: Icons.settings_ethernet,
          title: l.translate('diag_adapters'),
          child: s == null
              ? const LinearProgressIndicator()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final a in s.physicalAdapters)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(a.wireless ? Icons.wifi : Icons.settings_ethernet,
                          color: a.up ? Colors.green.shade600 : scheme.outline),
                      title: Text(a.name),
                      subtitle: Text([
                        a.up ? l.translate('diag_connected') : a.status,
                        if (a.linkSpeed.isNotEmpty && a.up) a.linkSpeed,
                        ...(s.addresses[a.name] ?? const []),
                        if (a.mac.isNotEmpty) a.mac,
                        if (a.description.isNotEmpty) a.description,
                      ].join('  ·  ')),
                    ),
                  const SizedBox(height: 8),
                  KeyValues(rows: [
                    (l.translate('diag_gateway'), s.gateways.isEmpty ? '—' : s.gateways.join(', ')),
                    ('DNS', s.dns.isEmpty ? '—' : s.dns.join(', ')),
                  ]),
                ]),
        ),
        DiagSection(
          icon: Icons.public,
          title: l.translate('diag_connectivity'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (c.endpoints.isEmpty && c.running) const LinearProgressIndicator(),
            for (final e in c.endpoints)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(e.ok ? Icons.check_circle : Icons.cancel,
                    color: e.ok ? Colors.green.shade600 : scheme.error),
                title: Text(l.translate(endpointKey(e.kind))),
                subtitle: Text(e.target, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(
                  e.ok ? '${e.latencyMs} ms' : e.detail,
                  style: TextStyle(
                      color: e.ok
                          ? ((e.latencyMs ?? 0) > 800 ? Colors.orange.shade700 : scheme.onSurface)
                          : scheme.error),
                ),
              ),
          ]),
        ),
        DiagSection(
          icon: Icons.speed,
          title: l.translate('diag_speed_test'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: c.speedPhase != null ? null : c.runSpeedTest,
              icon: const Icon(Icons.play_arrow),
              label: Text(l.translate('diag_start')),
            ),
          ],
          child: c.speedPhase != null
              ? Row(children: [
                  const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('${l.translate('diag_speed_${c.speedPhase}')}'
                      '${c.speedLive != null ? '  ${c.speedLive!.toStringAsFixed(1)} Mbps' : ''}'),
                ])
              : speed == null
                  ? Text(l.translate('diag_speed_hint'),
                      style: TextStyle(color: scheme.onSurfaceVariant))
                  : speed.error != null
                      ? Text(speed.error!, style: TextStyle(color: scheme.error))
                      : Wrap(spacing: 32, runSpacing: 8, children: [
                          DiagMetric(
                              icon: Icons.download,
                              label: l.translate('diag_speed_download'),
                              value: '${speed.downloadMbps!.toStringAsFixed(1)} Mbps',
                              large: true),
                          DiagMetric(
                              icon: Icons.upload,
                              label: l.translate('diag_speed_upload'),
                              value: '${speed.uploadMbps!.toStringAsFixed(1)} Mbps',
                              large: true),
                          DiagMetric(
                              icon: Icons.timer_outlined,
                              label: l.translate('diag_speed_latency'),
                              value: '${speed.latencyMs} ms',
                              large: true),
                        ]),
        ),
        DiagSection(
          icon: Icons.router,
          title: l.translate('diag_router'),
          actions: [
            FilledButton.tonalIcon(
              onPressed: gw == null ? null : () => DiagnosticsService.openUrl('http://$gw/'),
              icon: const Icon(Icons.open_in_browser),
              label: Text(l.translate('diag_open_router')),
            ),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeyValues(rows: [
              (l.translate('diag_gateway'), gw ?? '—'),
              if (gwHost?.vendor != null) (l.translate('diag_maker'), gwHost!.vendor!),
              if (gwHost?.banner != null) ('Web', gwHost!.banner!),
              if (gwHost?.mac != null) ('MAC', gwHost!.mac!),
            ]),
            const SizedBox(height: 12),
            Text(l.translate('diag_router_logins'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(l.translate('diag_router_logins_hint'),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (brand, user, pass) in _routerLogins)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: brandText.contains(brand.toLowerCase())
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$brand — $user / $pass',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: brandText.contains(brand.toLowerCase())
                              ? FontWeight.w700
                              : null)),
                ),
            ]),
          ]),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- widgets

class DiagSection extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget child;
  final List<Widget> actions;
  const DiagSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, color: iconColor ?? scheme.primary),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ]),
                if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class KeyValues extends StatelessWidget {
  final List<(String, String?)> rows;
  final Map<int, Widget> valueOverrides;
  final Map<int, Color> highlight;
  const KeyValues({
    super.key,
    required this.rows,
    this.valueOverrides = const {},
    this.highlight = const {},
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      for (var i = 0; i < rows.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 190,
              child: Text(rows[i].$1, style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
            Expanded(
              child: valueOverrides[i] ??
                  SelectableText(rows[i].$2 ?? '',
                      style: TextStyle(
                          color: highlight[i],
                          fontWeight: highlight[i] != null ? FontWeight.w600 : null)),
            ),
          ]),
        ),
    ]);
  }
}

class LiveClock extends StatefulWidget {
  const LiveClock({super.key});
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return Text(
        '${n.year}-${two(n.month)}-${two(n.day)}  ${two(n.hour)}:${two(n.minute)}:${two(n.second)}',
        style: const TextStyle(
            fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]));
  }
}

class WifiTile extends StatelessWidget {
  final WifiInfo? wifi;
  const WifiTile({super.key, required this.wifi});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final w = wifi;
    if (w == null || !w.connected) {
      return Row(children: [
        Icon(Icons.wifi_off, color: w == null ? scheme.outline : scheme.error),
        const SizedBox(width: 12),
        Text(l.translate(w == null ? 'diag_no_wifi_adapter' : 'diag_wifi_disconnected')),
      ]);
    }
    final signal = w.signalPercent ?? 0;
    final color = signalColor(signal, scheme);
    final quality = l.translate(signal >= 70
        ? 'diag_signal_excellent'
        : signal >= 50
            ? 'diag_signal_good'
            : signal >= 30
                ? 'diag_signal_weak'
                : 'diag_signal_bad');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(signal >= 70 ? Icons.wifi : (signal >= 40 ? Icons.wifi_2_bar : Icons.wifi_1_bar),
            color: color, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w.ssid, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: signal / 100,
                    minHeight: 8,
                    color: color,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('$signal% · $quality',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 24, runSpacing: 8, children: [
        if (w.receiveMbps != null)
          DiagMetric(
              icon: Icons.download,
              label: l.translate('diag_wifi_rx'),
              value: '${w.receiveMbps!.toStringAsFixed(0)} Mbps'),
        if (w.transmitMbps != null)
          DiagMetric(
              icon: Icons.upload,
              label: l.translate('diag_wifi_tx'),
              value: '${w.transmitMbps!.toStringAsFixed(0)} Mbps'),
        if (w.band.isNotEmpty || w.channel != null)
          DiagMetric(
              icon: Icons.settings_input_antenna,
              label: l.translate('diag_wifi_channel'),
              value: [if (w.band.isNotEmpty) w.band, if (w.channel != null) 'ch ${w.channel}']
                  .join(' · ')),
        if (w.radio.isNotEmpty) DiagMetric(icon: Icons.router, label: 'Standard', value: w.radio),
        if (w.security.isNotEmpty)
          DiagMetric(icon: Icons.lock, label: l.translate('diag_wifi_security'), value: w.security),
        if (w.bssid.isNotEmpty) DiagMetric(icon: Icons.memory, label: 'BSSID', value: w.bssid),
      ]),
    ]);
  }
}

Color signalColor(int signal, ColorScheme scheme) => signal >= 70
    ? Colors.green.shade600
    : signal >= 50
        ? Colors.lightGreen.shade700
        : signal >= 30
            ? Colors.orange.shade700
            : scheme.error;

class DiagMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool large;
  const DiagMetric(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      this.large = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: large ? 24 : 18, color: scheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: large ? 20 : null)),
      ]),
    ]);
  }
}
