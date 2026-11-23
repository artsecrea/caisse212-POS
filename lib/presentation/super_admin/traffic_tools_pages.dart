import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/diagnostics_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../widgets/adaptive_text_field.dart';
import 'diagnostics_controller.dart';
import 'diagnostics_panel.dart';

// ----------------------------------------------------------------- traffic

class TrafficPage extends StatefulWidget {
  const TrafficPage({super.key});

  @override
  State<TrafficPage> createState() => _TrafficPageState();
}

class _TrafficPageState extends State<TrafficPage> {
  static const _history = 90;

  TrafficMonitor? _monitor;
  final Map<String, TrafficSample> _first = {};
  final Map<String, TrafficSample> _last = {};
  DateTime? _lastAt;
  final Map<String, List<(double, double)>> _rates = {};
  String? _adapter;
  List<ProcessConnections>? _connections;
  bool _loadingConnections = false;

  @override
  void dispose() {
    _monitor?.stop();
    super.dispose();
  }

  void _toggle() {
    if (_monitor != null) {
      _monitor!.stop();
      setState(() => _monitor = null);
      return;
    }
    _first.clear();
    _last.clear();
    _rates.clear();
    _lastAt = null;
    final m = TrafficMonitor();
    setState(() => _monitor = m);
    m.start(_onSample);
  }

  void _onSample(DateTime at, List<TrafficSample> samples) {
    if (!mounted) return;
    final seconds = _lastAt == null ? null : at.difference(_lastAt!).inMilliseconds / 1000;
    setState(() {
      for (final s in samples) {
        _first.putIfAbsent(s.adapter, () => s);
        final prev = _last[s.adapter];
        if (prev != null && seconds != null && seconds > 0) {
          final rx = math.max(0, s.rxBytes - prev.rxBytes) / seconds;
          final tx = math.max(0, s.txBytes - prev.txBytes) / seconds;
          final list = _rates.putIfAbsent(s.adapter, () => []);
          list.add((rx, tx));
          if (list.length > _history) list.removeAt(0);
        }
        _last[s.adapter] = s;
      }
      _lastAt = at;
      // Follow the adapter that actually carries traffic.
      if (_adapter == null || !_last.containsKey(_adapter)) {
        final busiest = _last.values.toList()
          ..sort((a, b) => (b.rxBytes + b.txBytes).compareTo(a.rxBytes + a.txBytes));
        _adapter = busiest.firstOrNull?.adapter;
      }
    });
  }

  Future<void> _loadConnections() async {
    setState(() => _loadingConnections = true);
    final c = await DiagnosticsService.connectionsByProcess();
    if (!mounted) return;
    setState(() {
      _connections = c;
      _loadingConnections = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final running = _monitor != null;
    final a = _adapter;
    final rates = a == null ? const <(double, double)>[] : (_rates[a] ?? const []);
    final first = a == null ? null : _first[a];
    final last = a == null ? null : _last[a];
    final now = rates.isEmpty ? null : rates.last;
    final peakRx = rates.fold<double>(0, (m, r) => math.max(m, r.$1));
    final peakTx = rates.fold<double>(0, (m, r) => math.max(m, r.$2));
    final adapters = _last.keys.toList()..sort();
    final connections = _connections;
    return DiagPageScaffold(
      title: l.translate('diag_page_traffic'),
      subtitle: l.translate('diag_traffic_hint'),
      actions: [
        FilledButton.icon(
          onPressed: _toggle,
          icon: Icon(running ? Icons.stop : Icons.play_arrow),
          label: Text(l.translate(running ? 'diag_stop' : 'diag_start')),
        ),
      ],
      children: [
        DiagSection(
          icon: Icons.show_chart,
          title: l.translate('diag_live_traffic'),
          actions: [
            if (adapters.length > 1)
              DropdownButton<String>(
                value: a,
                onChanged: (v) => setState(() => _adapter = v),
                items: [for (final n in adapters) DropdownMenuItem(value: n, child: Text(n))],
              ),
          ],
          child: !running && last == null
              ? Text(l.translate('diag_traffic_press_start'),
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 32, runSpacing: 12, children: [
                    DiagMetric(
                        icon: Icons.download,
                        label: l.translate('diag_speed_download'),
                        value: now == null ? '…' : formatRate(now.$1),
                        large: true),
                    DiagMetric(
                        icon: Icons.upload,
                        label: l.translate('diag_speed_upload'),
                        value: now == null ? '…' : formatRate(now.$2),
                        large: true),
                    DiagMetric(
                        icon: Icons.trending_up,
                        label: l.translate('diag_peak'),
                        value: '↓ ${formatRate(peakRx)}  ↑ ${formatRate(peakTx)}'),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: _RatePainter(
                        rates: rates,
                        slots: _history,
                        rxColor: scheme.primary,
                        txColor: scheme.tertiary,
                        grid: scheme.outlineVariant,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(formatRate(math.max(peakRx, peakTx)),
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 16, children: [
                    _legend(scheme.primary, l.translate('diag_speed_download')),
                    _legend(scheme.tertiary, l.translate('diag_speed_upload')),
                  ]),
                ]),
        ),
        if (last != null)
          DiagSection(
            icon: Icons.data_usage,
            title: l.translate('diag_data_used'),
            child: Wrap(spacing: 32, runSpacing: 12, children: [
              if (first != null)
                DiagMetric(
                    icon: Icons.timer,
                    label: l.translate('diag_since_start'),
                    value: '↓ ${formatBytes(last.rxBytes - first.rxBytes)}  '
                        '↑ ${formatBytes(last.txBytes - first.txBytes)}'),
              DiagMetric(
                  icon: Icons.history,
                  label: l.translate('diag_since_boot'),
                  value: '↓ ${formatBytes(last.rxBytes)}  ↑ ${formatBytes(last.txBytes)}'),
              DiagMetric(
                  icon: Icons.error_outline,
                  label: l.translate('diag_packet_errors'),
                  value: '${last.errors} / ${last.discards}'),
            ]),
          ),
        DiagSection(
          icon: Icons.apps,
          title: l.translate('diag_connections_title'),
          actions: [
            OutlinedButton.icon(
              onPressed: _loadingConnections ? null : _loadConnections,
              icon: _loadingConnections
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              label: Text(l.translate('diag_who_uses_network')),
            ),
          ],
          child: connections == null
              ? Text(l.translate('diag_connections_hint'),
                  style: TextStyle(color: scheme.onSurfaceVariant))
              : connections.isEmpty
                  ? Text(l.translate('diag_no_connections'),
                      style: TextStyle(color: scheme.onSurfaceVariant))
                  : Column(children: [
                      for (final c in connections.take(15))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.memory),
                          title: Text(c.process),
                          subtitle: Text(
                              c.remotes.take(4).join(', ') + (c.remotes.length > 4 ? ' …' : ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: Text(l
                              .translate('diag_connection_count')
                              .replaceAll('{count}', '${c.connections}')),
                        ),
                    ]),
        ),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 3, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

class _RatePainter extends CustomPainter {
  final List<(double, double)> rates;
  final int slots;
  final Color rxColor;
  final Color txColor;
  final Color grid;
  _RatePainter({
    required this.rates,
    required this.slots,
    required this.rxColor,
    required this.txColor,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final g = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    if (rates.length < 2) return;
    final top = rates.fold<double>(1, (m, r) => math.max(m, math.max(r.$1, r.$2)));
    void line(double Function((double, double)) pick, Color c) {
      final path = Path();
      final dx = size.width / (slots - 1);
      final start = slots - rates.length;
      for (var i = 0; i < rates.length; i++) {
        final x = (start + i) * dx;
        final y = size.height - size.height * pick(rates[i]) / top;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }

    line((r) => r.$1, rxColor);
    line((r) => r.$2, txColor);
  }

  @override
  bool shouldRepaint(covariant _RatePainter old) => true;
}

// ------------------------------------------------------------------- tools

class ToolsPage extends StatefulWidget {
  final DiagnosticsController c;
  const ToolsPage({super.key, required this.c});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');
  final _lines = <String>[];
  final _scroll = ScrollController();
  ConsoleRun? _run;
  int _count = 4;
  bool _busy = false;

  @override
  void dispose() {
    _run?.stop();
    _host.dispose();
    _port.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String? _validHost() {
    final h = _host.text.trim();
    if (!DiagnosticsService.hostPattern.hasMatch(h)) {
      SnackBarHelper.showToast(AppLocalizations.of(context)!.translate('diag_invalid_host'),
          kind: ToastKind.warning);
      return null;
    }
    return h;
  }

  void _add(String line) {
    if (!mounted) return;
    setState(() => _lines.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _start(ConsoleTool tool) async {
    final host = _validHost();
    if (host == null) return;
    setState(() {
      _lines
        ..clear()
        ..add('> ${tool.name} $host');
      _busy = true;
    });
    try {
      final run = await DiagnosticsService.startConsole(tool, host, _count, _add);
      setState(() => _run = run);
      await run.exitCode;
    } catch (e) {
      _add('$e');
    }
    if (mounted) {
      setState(() {
        _run = null;
        _busy = false;
      });
    }
  }

  Future<void> _testPort() async {
    final host = _validHost();
    if (host == null) return;
    final l = AppLocalizations.of(context)!;
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      SnackBarHelper.showToast(l.translate('diag_invalid_host'), kind: ToastKind.warning);
      return;
    }
    setState(() {
      _lines
        ..clear()
        ..add('> tcp $host:$port');
      _busy = true;
    });
    final r = await DiagnosticsService.checkTcp(EndpointKind.custom, host, port);
    _add(r.ok
        ? l.translate('diag_port_open').replaceAll('{ms}', '${r.latencyMs}')
        : '${l.translate('diag_port_closed')} — ${r.detail}');
    if (mounted) setState(() => _busy = false);
  }

  void _preset(String host, [String? port]) {
    _host.text = host;
    if (port != null) _port.text = port;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final c = widget.c;
    final gw = c.gateway;
    final printerHosts = {for (final p in c.printers) if (p.address.contains('.')) p.host};
    return DiagPageScaffold(
      title: l.translate('diag_page_tools'),
      subtitle: l.translate('diag_tools_hint'),
      children: [
        DiagSection(
          icon: Icons.terminal,
          title: l.translate('diag_tools'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: AdaptiveKeyboardTextField(
                    controller: _host,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: l.translate('diag_host'),
                      hintText: '192.168.1.100',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _start(ConsoleTool.ping),
                  ),
                ),
                DropdownButton<int>(
                  value: _count,
                  onChanged: _busy ? null : (v) => setState(() => _count = v ?? 4),
                  items: [
                    for (final n in const [4, 10, 30, 100])
                      DropdownMenuItem(value: n, child: Text('× $n')),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _start(ConsoleTool.ping),
                  icon: const Icon(Icons.network_ping),
                  label: Text(l.translate('diag_ping')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _start(ConsoleTool.traceroute),
                  icon: const Icon(Icons.route),
                  label: Text(l.translate('diag_traceroute')),
                ),
                SizedBox(
                  width: 100,
                  child: AdaptiveKeyboardTextField(
                    controller: _port,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l.translate('diag_port'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _testPort,
                  icon: const Icon(Icons.power),
                  label: Text(l.translate('diag_test_port')),
                ),
                if (_run != null)
                  TextButton.icon(
                    onPressed: () => _run?.stop(),
                    icon: Icon(Icons.stop, color: scheme.error),
                    label: Text(l.translate('diag_stop')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (gw != null)
                ActionChip(
                  avatar: const Icon(Icons.router, size: 16),
                  label: Text('${l.translate('diag_gateway')} $gw'),
                  onPressed: _busy ? null : () => _preset(gw, '80'),
                ),
              for (final p in printerHosts)
                ActionChip(
                  avatar: const Icon(Icons.print, size: 16),
                  label: Text(p),
                  onPressed: _busy ? null : () => _preset(p, '9100'),
                ),
              ActionChip(
                  label: const Text('8.8.8.8'),
                  onPressed: _busy ? null : () => _preset('8.8.8.8', '53')),
              ActionChip(
                  label: const Text('google.com'),
                  onPressed: _busy ? null : () => _preset('google.com', '443')),
              ActionChip(
                avatar: const Icon(Icons.point_of_sale, size: 16),
                label: Text('${l.translate('diag_lan_server')} :${c.lanPort}'),
                onPressed: _busy ? null : () => _preset('127.0.0.1', '${c.lanPort}'),
              ),
            ]),
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 300,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: _lines.length,
                    itemBuilder: (_, i) => Text(_lines[i],
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }
}
