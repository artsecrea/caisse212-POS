import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';

import '../../services/diagnostics_service.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import 'devices_pages.dart';
import 'diagnostics_controller.dart';
import 'diagnostics_panel.dart';

class PrintersPage extends StatelessWidget {
  final DiagnosticsController c;
  const PrintersPage({super.key, required this.c});

  Future<void> _testPrint(BuildContext context, PrinterCheck p) async {
    final l = AppLocalizations.of(context)!;
    final ok = p.pooled != null
        ? await c.printing.testPoolPrinter(p.pooled!)
        : await c.printing.printTestPage(p.purpose!);
    SnackBarHelper.showToast(
        l.translate(ok ? 'diag_test_print_sent' : 'diag_test_print_failed'),
        kind: ok ? ToastKind.success : ToastKind.error);
  }

  Future<void> _label(BuildContext context, String ip, int port, String name) async {
    final l = AppLocalizations.of(context)!;
    final ok = await DiagnosticsService.printAddressLabel(ip, port, [
      name,
      'Port $port',
      formatDateTime(DateTime.now()),
    ]);
    SnackBarHelper.showToast(
        l.translate(ok ? 'diag_test_print_sent' : 'diag_test_print_failed'),
        kind: ok ? ToastKind.success : ToastKind.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final s = c.snap;
    final osPrinters = s?.printers.where((p) => !p.isVirtual).toList() ?? const [];
    final moves = c.printerMoves;
    final found = (c.hosts ?? const <LanHost>[]).where((h) => h.kind == DeviceKind.printer).toList();
    return DiagPageScaffold(
      title: l.translate('diag_page_printers'),
      subtitle: l.translate('diag_printers_hint'),
      actions: [
        FixButton(c: c, labelKey: 'diag_clear_queues', run: DiagnosticsService.clearPrintQueues),
        FixButton(c: c, labelKey: 'diag_restart_spooler', run: DiagnosticsService.restartSpooler),
        TextButton.icon(
          onPressed: () => DiagnosticsService.openSettings(SettingsPage.printers),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.translate('diag_open_settings')),
        ),
      ],
      children: [
        PageIssues(c: c, page: DiagPage.printers),
        if (moves.isNotEmpty)
          DiagSection(
            icon: Icons.move_down,
            iconColor: scheme.error,
            title: l.translate('diag_printer_moved_title'),
            child: Column(children: [
              for (final m in moves)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.print),
                  title: Text(m.printer.label),
                  subtitle: Text('${m.printer.host} → ${m.newIp}  ·  '
                      '${l.translate('diag_printer_moved_hint')}'),
                  trailing: FilledButton(
                    onPressed: c.fixing != null
                        ? null
                        : () => runFix(
                            context,
                            () => c.fix('diag_update_pos_printer',
                                () => c.retargetPrinter(m.printer.host, m.newIp), l)),
                    child: Text(l.translate('diag_update_pos_printer')),
                  ),
                ),
            ]),
          ),
        DiagSection(
          icon: Icons.point_of_sale,
          title: l.translate('diag_pos_printers'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (c.printers.isEmpty)
              Text(c.running ? '…' : l.translate('diag_no_pos_printer'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final p in c.printers) _posPrinterTile(context, l, scheme, p),
          ]),
        ),
        if (osPrinters.isNotEmpty)
          DiagSection(
            icon: Icons.print_outlined,
            title: '${l.translate('diag_os_printers')}'
                '${s?.spoolerRunning == false ? ' — ${l.translate('diag_issue_spooler')}' : ''}',
            child: Column(children: [
              for (final p in osPrinters)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.print_outlined,
                      color: p.problems.isEmpty ? scheme.onSurfaceVariant : scheme.error),
                  title: Text(p.name),
                  subtitle: Text([
                    if (p.port.isNotEmpty) p.port,
                    if (p.driver.isNotEmpty) p.driver,
                    if (p.problems.isNotEmpty) p.problems.map(l.translate).join(', '),
                  ].join('  ·  ')),
                  trailing: Text(
                    l.translate('diag_jobs').replaceAll('{count}', '${p.jobs}'),
                    style: TextStyle(
                        color: p.jobs >= stuckJobs ? scheme.error : scheme.onSurfaceVariant,
                        fontWeight: p.jobs >= stuckJobs ? FontWeight.w600 : null),
                  ),
                ),
            ]),
          ),
        DiagSection(
          icon: Icons.lan,
          title: l.translate('diag_network_printers_found'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (c.hosts == null) ScanBar(c: c),
            if (c.hosts != null && found.isEmpty)
              Text(l.translate('diag_no_network_printer'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            for (final h in found)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.print, color: kindColor(DeviceKind.printer)),
                title: Text(h.ip, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([
                  if (h.vendor != null) h.vendor!,
                  if (h.banner != null) h.banner!,
                  if (h.mac != null) h.mac!,
                  if (c.printers.any((p) => p.host == h.ip)) l.translate('diag_used_by_pos'),
                ].join('  ·  ')),
                trailing: Wrap(spacing: 4, children: [
                  IconButton(
                    tooltip: l.translate('diag_print_address'),
                    icon: const Icon(Icons.receipt_long),
                    onPressed: () => _label(context, h.ip, DiagnosticsService.printerPort,
                        h.vendor ?? 'caisse212'),
                  ),
                  if (h.openPorts.contains(80))
                    IconButton(
                      tooltip: l.translate('diag_open_web'),
                      icon: const Icon(Icons.open_in_browser),
                      onPressed: () => DiagnosticsService.openUrl('http://${h.ip}/'),
                    ),
                  PopupMenuButton<PrinterPurpose>(
                    tooltip: l.translate('diag_use_in_pos'),
                    icon: const Icon(Icons.add_task),
                    onSelected: (purpose) => runFix(
                        context,
                        () => c.fix(
                            'diag_use_in_pos',
                            () => c.usePrinter(
                                h.ip,
                                purpose,
                                purpose == PrinterPurpose.receipt
                                    ? l.translate('diag_receipt_printer')
                                    : l.translate('diag_kitchen_printer')),
                            l)),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: PrinterPurpose.receipt,
                          child: Text(l.translate('diag_use_as_receipt'))),
                      PopupMenuItem(
                          value: PrinterPurpose.kds,
                          child: Text(l.translate('diag_use_as_kitchen'))),
                    ],
                  ),
                ]),
              ),
          ]),
        ),
        _FactorySetup(c: c),
      ],
    );
  }

  Widget _posPrinterTile(
      BuildContext context, AppLocalizations l, ColorScheme scheme, PrinterCheck p) {
    final problems = p.problems;
    final n = p.network;
    final sp = p.spooler;
    final details = <String>[
      p.address,
      if (n != null && n.reachable) '${n.latencyMs} ms',
      if (n != null && n.reachable && !n.statusKnown) l.translate('diag_status_unreported'),
      if (n != null && !n.reachable && n.error != null) n.error!,
      if (sp != null) l.translate('diag_jobs').replaceAll('{count}', '${sp.jobs}'),
      if (p.type == ConnectionType.BLE) 'Bluetooth',
      ...problems.map(l.translate),
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        p.type == ConnectionType.NETWORK
            ? Icons.lan
            : (p.type == ConnectionType.USB ? Icons.usb : Icons.bluetooth),
        color: problems.isEmpty ? Colors.green.shade600 : scheme.error,
      ),
      title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(details.join('  ·  ')),
      trailing: Wrap(spacing: 4, children: [
        if (p.type == ConnectionType.NETWORK && (n?.reachable ?? false))
          IconButton(
            tooltip: l.translate('diag_print_address'),
            icon: const Icon(Icons.receipt_long),
            onPressed: () => _label(context, p.host, p.port, p.label),
          ),
        OutlinedButton(
          onPressed: () => _testPrint(context, p),
          child: Text(l.translate('diag_test_print')),
        ),
      ]),
    );
  }
}

/// Reaches a printer still on its factory address (another subnet) by
/// lending this PC a temporary address next to it.
class _FactorySetup extends StatefulWidget {
  final DiagnosticsController c;
  const _FactorySetup({required this.c});

  @override
  State<_FactorySetup> createState() => _FactorySetupState();
}

class _FactorySetupState extends State<_FactorySetup> {
  bool _busy = false;
  bool _borrowed = false;
  List<String>? _found;

  String? get _adapter => widget.c.scanTarget?.adapter;

  Future<void> _search() async {
    final adapter = _adapter;
    if (adapter == null) return;
    setState(() => _busy = true);
    final ok = await runFix(context, () async {
      await DiagnosticsService.addTemporaryAddresses(
          adapter, DiagnosticsService.factoryPrinterAddresses);
      _borrowed = true;
      // Windows needs a moment before the new address can be used.
      await Future<void>.delayed(const Duration(seconds: 3));
    });
    final found = ok ? await DiagnosticsService.probeFactoryPrinters() : null;
    if (!mounted) return;
    setState(() {
      _found = found;
      _busy = false;
    });
  }

  Future<void> _done() async {
    final adapter = _adapter;
    if (adapter == null) return;
    setState(() => _busy = true);
    final ok = await runFix(
        context,
        () => DiagnosticsService.removeTemporaryAddresses(
            adapter, DiagnosticsService.factoryPrinterAddresses));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _borrowed = false;
        _found = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final free = widget.c.freeForStatic(3);
    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 11, child: Text('$n', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ]),
        );
    return DiagSection(
      icon: Icons.settings_input_component,
      title: l.translate('diag_printer_setup'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        step(1, l.translate('diag_setup_step1')),
        step(2, l.translate('diag_setup_step2')),
        step(3, l.translate('diag_setup_step3').replaceAll(
            '{ip}', free.isEmpty ? '192.168.1.240' : free.first)),
        step(4, l.translate('diag_setup_step4')),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _busy || _adapter == null ? null : _search,
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(l.translate('diag_search_factory')),
          ),
          if (_borrowed)
            OutlinedButton.icon(
              onPressed: _busy ? null : _done,
              icon: const Icon(Icons.cleaning_services),
              label: Text(l.translate('diag_remove_temp_ip')),
            ),
          if (free.isNotEmpty)
            ActionChip(
              avatar: const Icon(Icons.copy, size: 16),
              label: Text('${l.translate('diag_suggested_ip')} ${free.first}'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: free.first));
                SnackBarHelper.showToast(free.first, kind: ToastKind.neutral);
              },
            ),
        ]),
        Text(
            l.translate('diag_factory_addresses').replaceAll(
                '{list}', DiagnosticsService.factoryPrinterAddresses.join(', ')),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        if (_found != null) ...[
          const SizedBox(height: 8),
          if (_found!.isEmpty)
            Text(l.translate('diag_factory_none'), style: TextStyle(color: scheme.onSurfaceVariant)),
          for (final ip in _found!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.print, color: kindColor(DeviceKind.printer)),
              title: Text(ip, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(l.translate('diag_factory_found_hint')),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  tooltip: l.translate('diag_print_address'),
                  icon: const Icon(Icons.receipt_long),
                  onPressed: () async {
                    final ok = await DiagnosticsService.printAddressLabel(
                        ip, DiagnosticsService.printerPort, [l.translate('diag_factory_address')]);
                    SnackBarHelper.showToast(
                        l.translate(ok ? 'diag_test_print_sent' : 'diag_test_print_failed'),
                        kind: ok ? ToastKind.success : ToastKind.error);
                  },
                ),
                FilledButton.tonalIcon(
                  onPressed: () => DiagnosticsService.openUrl('http://$ip/'),
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(l.translate('diag_open_web')),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
