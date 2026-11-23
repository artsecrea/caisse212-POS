import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/diagnostics_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../widgets/adaptive_text_field.dart';
import 'diagnostics_controller.dart';
import 'diagnostics_panel.dart';

IconData kindIcon(DeviceKind k) => switch (k) {
      DeviceKind.thisPos => Icons.point_of_sale,
      DeviceKind.router => Icons.router,
      DeviceKind.caisse => Icons.tablet_mac,
      DeviceKind.printer => Icons.print,
      DeviceKind.camera => Icons.videocam,
      DeviceKind.computer => Icons.computer,
      DeviceKind.phone => Icons.smartphone,
      DeviceKind.media => Icons.tv,
      DeviceKind.unknown => Icons.devices_other,
    };

/// One fixed colour per device kind, so the IP map reads the same in both
/// themes.
Color kindColor(DeviceKind k) => switch (k) {
      DeviceKind.thisPos => const Color(0xFF1E88E5),
      DeviceKind.router => const Color(0xFF6D4C41),
      DeviceKind.caisse => const Color(0xFF3949AB),
      DeviceKind.printer => const Color(0xFF00897B),
      DeviceKind.camera => const Color(0xFFD81B60),
      DeviceKind.computer => const Color(0xFF7CB342),
      DeviceKind.phone => const Color(0xFFFB8C00),
      DeviceKind.media => const Color(0xFF8E24AA),
      DeviceKind.unknown => const Color(0xFF757575),
    };

String kindLabel(AppLocalizations l, DeviceKind k) => l.translate('diag_kind_${k.name}');

/// Scan button, subnet picker and progress, shared by the pages that need a
/// fresh scan.
class ScanBar extends StatelessWidget {
  final DiagnosticsController c;
  const ScanBar({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (c.scanTargets.isNotEmpty)
            DropdownButton<ScanTarget>(
              value: c.scanTarget,
              onChanged: c.scanning ? null : c.selectTarget,
              items: [
                for (final t in c.scanTargets)
                  DropdownMenuItem(value: t, child: Text('${t.subnet}  (${t.adapter})')),
              ],
            )
          else
            Text(l.translate('diag_no_network_address'), style: TextStyle(color: scheme.error)),
          c.scanning
              ? OutlinedButton.icon(
                  onPressed: () => c.cancelScan = true,
                  icon: const Icon(Icons.stop),
                  label: Text(l.translate('diag_stop')),
                )
              : FilledButton.icon(
                  onPressed: c.scanTarget == null || c.identifying ? null : c.scan,
                  icon: const Icon(Icons.radar),
                  label: Text(l.translate(c.hosts == null ? 'diag_scan' : 'diag_rescan')),
                ),
          if (c.identifying)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text(l.translate('diag_identifying')),
            ]),
          if (c.scannedAt != null && !c.scanning)
            Text(
                l.translate('diag_last_run').replaceAll(
                    '{time}', TimeOfDay.fromDateTime(c.scannedAt!).format(context)),
                style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
      if (c.scanning) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: c.scanTotal == 0 ? null : c.scanDone / c.scanTotal),
        const SizedBox(height: 4),
        Text('${c.scanDone} / ${c.scanTotal}'),
      ],
    ]);
  }
}

// ----------------------------------------------------------------- devices

class DevicesPage extends StatefulWidget {
  final DiagnosticsController c;
  const DevicesPage({super.key, required this.c});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  DeviceKind? _filter;
  String _search = '';
  final Map<String, double?> _pings = {};

  DiagnosticsController get c => widget.c;

  Future<void> _ping(String ip) async {
    setState(() => _pings[ip] = -1);
    final ms = await DiagnosticsService.pingOnce(ip);
    if (mounted) setState(() => _pings[ip] = ms);
  }

  String _portLabel(int port) => port == c.lanPort
      ? 'caisse212 ($port)'
      : '${DiagnosticsController.portNames[port] ?? ''} $port'.trim();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final hosts = c.hosts;
    final q = _search.toLowerCase();
    final shown = (hosts ?? const <LanHost>[])
        .where((h) => _filter == null || h.kind == _filter)
        .where((h) =>
            q.isEmpty ||
            '${h.ip} ${h.mac ?? ''} ${h.vendor ?? ''} ${h.hostname ?? ''} ${h.banner ?? ''}'
                .toLowerCase()
                .contains(q))
        .toList();
    final counts = <DeviceKind, int>{};
    for (final h in hosts ?? const <LanHost>[]) {
      counts[h.kind] = (counts[h.kind] ?? 0) + 1;
    }
    final free = c.freeForStatic();
    return DiagPageScaffold(
      title: l.translate('diag_page_devices'),
      subtitle: l.translate('diag_scan_hint'),
      children: [
        DiagSection(icon: Icons.radar, title: l.translate('diag_lan_scan'), child: ScanBar(c: c)),
        PageIssues(c: c, page: DiagPage.devices),
        if (hosts != null) ...[
          DiagSection(
            icon: Icons.grid_view,
            title: l.translate('diag_ip_map'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 32, runSpacing: 8, children: [
                DiagMetric(
                    icon: Icons.lan,
                    label: l.translate('diag_ips_used'),
                    value: '${hosts.length} / 254',
                    large: true),
                DiagMetric(
                    icon: Icons.check_box_outline_blank,
                    label: l.translate('diag_ips_free'),
                    value: '${254 - hosts.length}',
                    large: true),
                if (c.newDevices.isNotEmpty)
                  DiagMetric(
                      icon: Icons.fiber_new,
                      label: l.translate('diag_new_devices'),
                      value: '${c.newDevices.length}',
                      large: true),
              ]),
              const SizedBox(height: 16),
              _IpMap(prefix: c.subnetPrefix, hosts: hosts, highlight: _filter),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final k in DeviceKind.values)
                  if ((counts[k] ?? 0) > 0)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: kindColor(k), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 4),
                      Text('${kindLabel(l, k)} ${counts[k]}', style: const TextStyle(fontSize: 12)),
                    ]),
              ]),
              if (free.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('${l.translate('diag_free_for_static')} ${free.join(', ')}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ]),
          ),
          DiagSection(
            icon: Icons.list,
            title: l.translate('diag_devices_found').replaceAll('{count}', '${hosts.length}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 220,
                  child: AdaptiveKeyboardTextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: l.translate('search'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                ChoiceChip(
                  label: Text('${l.translate('diag_all')} (${hosts.length})'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final k in DeviceKind.values)
                  if ((counts[k] ?? 0) > 0)
                    ChoiceChip(
                      avatar: Icon(kindIcon(k), size: 16, color: kindColor(k)),
                      label: Text('${kindLabel(l, k)} (${counts[k]})'),
                      selected: _filter == k,
                      onSelected: (_) => setState(() => _filter = _filter == k ? null : k),
                    ),
              ]),
              const SizedBox(height: 8),
              for (final h in shown) _hostTile(l, scheme, h),
            ]),
          ),
        ],
        _ConflictsSection(c: c),
      ],
    );
  }

  Widget _hostTile(AppLocalizations l, ColorScheme scheme, LanHost h) {
    final k = h.kind;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: kindColor(k).withValues(alpha: 0.15),
        child: Icon(kindIcon(k), size: 18, color: kindColor(k)),
      ),
      title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(h.ip, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(kindLabel(l, k), style: TextStyle(color: kindColor(k))),
        if (h.hostname != null) Text('— ${h.hostname}'),
        if (c.newDevices.contains(c.keyOf(h)))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(l.translate('diag_new'),
                style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer)),
          ),
      ]),
      subtitle: Text([
        if (h.vendor != null) h.vendor!,
        if (h.banner != null) h.banner!,
        if (h.mac != null) h.mac!,
        if (h.privateMac) l.translate('diag_private_mac'),
        if (h.latencyMs != null) '${h.latencyMs} ms',
        ...h.openPorts.map(_portLabel),
      ].join('  ·  ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_pings.containsKey(h.ip))
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _pings[h.ip] == -1
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _pings[h.ip] == null
                        ? l.translate('diag_no_reply')
                        : '${_pings[h.ip]!.toStringAsFixed(0)} ms',
                    style: TextStyle(color: _pings[h.ip] == null ? scheme.error : null)),
          ),
        if (h.openPorts.contains(80) || h.openPorts.contains(8080))
          IconButton(
            tooltip: l.translate('diag_open_web'),
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => DiagnosticsService.openUrl(
                'http://${h.ip}${h.openPorts.contains(80) ? '' : ':8080'}/'),
          ),
        IconButton(
          tooltip: l.translate('diag_ping'),
          icon: const Icon(Icons.network_ping),
          onPressed: () => _ping(h.ip),
        ),
        IconButton(
          tooltip: l.translate('diag_copy_ip'),
          icon: const Icon(Icons.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: h.ip));
            SnackBarHelper.showToast(h.ip, kind: ToastKind.neutral);
          },
        ),
      ]),
    );
  }
}

class _ConflictsSection extends StatelessWidget {
  final DiagnosticsController c;
  const _ConflictsSection({required this.c});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final taken = c.printerAddressTaken;
    final nothing = c.conflictEvents.isEmpty && c.ipChanges.isEmpty && taken.isEmpty;
    return DiagSection(
      icon: Icons.compare_arrows,
      title: l.translate('diag_ip_conflicts'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.translate('diag_ip_conflicts_hint'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        if (nothing)
          Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(l.translate(c.hosts == null ? 'diag_conflicts_need_scan' : 'diag_no_conflict')),
          ]),
        for (final e in c.conflictEvents)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.error, color: scheme.error),
            title: Text('${l.translate('diag_conflict_windows')} — ${formatDateTime(e.at)}'),
            subtitle: Text(e.message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        for (final (p, h) in taken)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.print_disabled, color: scheme.error),
            title: Text('${p.label} — ${p.host}'),
            subtitle: Text(l
                .translate('diag_conflict_printer_ip')
                .replaceAll('{device}',
                    '${kindName(l, h)}${h.vendor != null ? ' (${h.vendor})' : ''}${h.mac != null ? ' ${h.mac}' : ''}')),
          ),
        for (final ch in c.ipChanges)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.swap_horiz, color: Colors.orange.shade700),
            title: Text(ch.ip),
            subtitle: Text(l
                .translate('diag_conflict_changed')
                .replaceAll('{before}', ch.before)
                .replaceAll('{now}', ch.now)),
          ),
      ]),
    );
  }
}

/// The 254 addresses of the subnet as squares: grey = free, coloured =
/// taken, by device kind.
class _IpMap extends StatelessWidget {
  final String prefix;
  final List<LanHost> hosts;
  final DeviceKind? highlight;
  const _IpMap({required this.prefix, required this.hosts, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final byIp = {for (final h in hosts) h.ip: h};
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 1; i < 255; i++)
          Builder(builder: (_) {
            final h = byIp['$prefix$i'];
            final k = h?.kind;
            final dim = highlight != null && k != highlight;
            return Tooltip(
              message: h == null
                  ? '$prefix$i — ${l.translate('diag_free')}'
                  : '$prefix$i — ${kindLabel(l, k!)}'
                      '${h.vendor != null ? ' · ${h.vendor}' : ''}'
                      '${h.hostname != null ? ' · ${h.hostname}' : ''}',
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: h == null
                      ? scheme.surfaceContainerHighest
                      : kindColor(k!).withValues(alpha: dim ? 0.25 : 1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: i % 50 == 0 || i == 1
                    ? Text('$i',
                        style: TextStyle(
                            fontSize: 7,
                            color: h == null ? scheme.onSurfaceVariant : Colors.white))
                    : null,
              ),
            );
          }),
      ],
    );
  }
}

// ----------------------------------------------------------------- cameras

class CamerasPage extends StatefulWidget {
  final DiagnosticsController c;
  const CamerasPage({super.key, required this.c});

  @override
  State<CamerasPage> createState() => _CamerasPageState();
}

class _CamerasPageState extends State<CamerasPage> {
  final _manualIp = TextEditingController();
  final List<String> _manual = [];
  String? _selected;

  @override
  void dispose() {
    _manualIp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final c = widget.c;
    final cams = (c.hosts ?? const <LanHost>[]).where((h) => h.kind == DeviceKind.camera).toList();
    final ips = [...cams.map((h) => h.ip), ..._manual.where((m) => !cams.any((h) => h.ip == m))];
    final selected = _selected != null && ips.contains(_selected) ? _selected : ips.firstOrNull;
    final host = cams.where((h) => h.ip == selected).firstOrNull;
    return DiagPageScaffold(
      title: l.translate('diag_page_cameras'),
      subtitle: l.translate('diag_cameras_hint'),
      children: [
        if (c.hosts == null)
          DiagSection(icon: Icons.radar, title: l.translate('diag_lan_scan'), child: ScanBar(c: c)),
        DiagSection(
          icon: Icons.videocam,
          title: l.translate('diag_cameras_found').replaceAll('{count}', '${cams.length}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (ips.isEmpty)
              Text(l.translate(c.hosts == null ? 'diag_conflicts_need_scan' : 'diag_no_camera'),
                  style: TextStyle(color: scheme.onSurfaceVariant)),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final ip in ips)
                ChoiceChip(
                  avatar: const Icon(Icons.videocam, size: 16),
                  label: Text([
                    ip,
                    if (cams.where((h) => h.ip == ip).firstOrNull?.vendor case final v?)
                      v.split(' ').take(2).join(' '),
                  ].join(' · ')),
                  selected: ip == selected,
                  onSelected: (_) => setState(() => _selected = ip),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(
                width: 200,
                child: AdaptiveKeyboardTextField(
                  controller: _manualIp,
                  decoration: InputDecoration(
                    labelText: l.translate('diag_add_camera_ip'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final ip = _manualIp.text.trim();
                  if (!DiagnosticsService.hostPattern.hasMatch(ip)) return;
                  setState(() {
                    _manual.add(ip);
                    _selected = ip;
                    _manualIp.clear();
                  });
                },
              ),
            ]),
          ]),
        ),
        if (selected != null)
          _CameraViewer(
            key: ValueKey(selected),
            ip: selected,
            hint: '${host?.vendor ?? ''} ${host?.banner ?? ''}',
          ),
      ],
    );
  }
}

class _CameraViewer extends StatefulWidget {
  final String ip;
  final String hint;
  const _CameraViewer({super.key, required this.ip, required this.hint});

  @override
  State<_CameraViewer> createState() => _CameraViewerState();
}

class _CameraViewerState extends State<_CameraViewer> {
  late CameraBrand _brand = CameraSettings.guessBrand(widget.hint);
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _path = TextEditingController(text: '/snapshot.jpg');
  int _channel = 1;
  Uint8List? _image;
  String? _error;
  bool _live = false;
  DateTime? _at;
  String? _vlc;

  @override
  void initState() {
    super.initState();
    DiagnosticsService.findVlc().then((v) {
      if (mounted) setState(() => _vlc = v);
    });
  }

  @override
  void dispose() {
    _live = false;
    _user.dispose();
    _password.dispose();
    _path.dispose();
    super.dispose();
  }

  CameraSettings get _settings => CameraSettings(
        ip: widget.ip,
        brand: _brand,
        user: _user.text.trim(),
        password: _password.text,
        channel: _channel,
        customPath: _path.text.trim(),
      );

  Future<bool> _grab() async {
    try {
      final bytes = await DiagnosticsService.cameraSnapshot(_settings);
      if (!mounted) return false;
      setState(() {
        _image = Uint8List.fromList(bytes);
        _error = null;
        _at = DateTime.now();
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      final l = AppLocalizations.of(context)!;
      setState(() => _error = '$e' == '401'
          ? l.translate('diag_camera_bad_login')
          : '${l.translate('diag_camera_no_picture')} ($e)');
      return false;
    }
  }

  Future<void> _toggleLive() async {
    if (_live) {
      setState(() => _live = false);
      return;
    }
    setState(() => _live = true);
    while (_live && mounted) {
      final ok = await _grab();
      if (!ok) {
        if (mounted) setState(() => _live = false);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return DiagSection(
      icon: Icons.live_tv,
      title: '${l.translate('diag_camera_view')} — ${widget.ip}',
      actions: [
        OutlinedButton.icon(
          onPressed: () => DiagnosticsService.openUrl('http://${widget.ip}/'),
          icon: const Icon(Icons.open_in_browser),
          label: Text(l.translate('diag_open_web')),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<CameraBrand>(
            value: _brand,
            onChanged: (v) => setState(() => _brand = v ?? _brand),
            items: [
              for (final b in CameraBrand.values)
                DropdownMenuItem(
                    value: b,
                    child: Text(b == CameraBrand.custom
                        ? l.translate('diag_camera_other')
                        : '${b.name[0].toUpperCase()}${b.name.substring(1)}')),
            ],
          ),
          SizedBox(
            width: 140,
            child: AdaptiveKeyboardTextField(
              controller: _user,
              decoration: InputDecoration(
                  labelText: l.translate('diag_user'),
                  isDense: true,
                  border: const OutlineInputBorder()),
            ),
          ),
          SizedBox(
            width: 160,
            child: AdaptiveKeyboardTextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                  labelText: l.translate('password'),
                  isDense: true,
                  border: const OutlineInputBorder()),
              onSubmitted: (_) => _grab(),
            ),
          ),
          if (_brand == CameraBrand.custom)
            SizedBox(
              width: 200,
              child: AdaptiveKeyboardTextField(
                controller: _path,
                decoration: InputDecoration(
                    labelText: l.translate('diag_camera_path'),
                    isDense: true,
                    border: const OutlineInputBorder()),
              ),
            ),
          DropdownButton<int>(
            value: _channel,
            onChanged: (v) => setState(() => _channel = v ?? 1),
            items: [
              for (var ch = 1; ch <= 16; ch++)
                DropdownMenuItem(value: ch, child: Text('${l.translate('diag_channel')} $ch')),
            ],
          ),
          FilledButton.icon(
            onPressed: _live ? null : _grab,
            icon: const Icon(Icons.photo_camera),
            label: Text(l.translate('diag_camera_snapshot')),
          ),
          FilledButton.tonalIcon(
            onPressed: _toggleLive,
            icon: Icon(_live ? Icons.stop : Icons.play_arrow),
            label: Text(l.translate(_live ? 'diag_stop' : 'diag_camera_live')),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _settings.rtspUrl));
              SnackBarHelper.showToast(l.translate('diag_rtsp_copied'), kind: ToastKind.neutral);
            },
            icon: const Icon(Icons.link, size: 18),
            label: Text(l.translate('diag_copy_rtsp')),
          ),
          if (_vlc != null)
            TextButton.icon(
              onPressed: () => DiagnosticsService.openInVlc(_vlc!, _settings.rtspUrl),
              icon: const Icon(Icons.smart_display, size: 18),
              label: Text(l.translate('diag_open_vlc')),
            ),
        ]),
        Text(l.translate('diag_camera_password_hint'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: TextStyle(color: scheme.error)),
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 480),
              child: Image.memory(_image!, gaplessPlayback: true, fit: BoxFit.contain),
            ),
          ),
        if (_at != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                '${_at!.hour.toString().padLeft(2, '0')}:${_at!.minute.toString().padLeft(2, '0')}:${_at!.second.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------- wi-fi

class WifiPage extends StatefulWidget {
  final DiagnosticsController c;
  const WifiPage({super.key, required this.c});

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  List<WifiNeighbour>? _nets;
  bool _loading = false;

  Future<void> _load() async {
    setState(() => _loading = true);
    final n = await DiagnosticsService.nearbyWifi();
    if (!mounted) return;
    setState(() {
      _nets = n..sort((a, b) => b.signalPercent.compareTo(a.signalPercent));
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final nets = _nets;
    final own = widget.c.snap?.wifi;
    final ownBssid = own?.connected == true ? own!.bssid : null;
    return DiagPageScaffold(
      title: l.translate('diag_page_wifi'),
      subtitle: l.translate('diag_wifi_neighbours_hint'),
      actions: [
        FilledButton.icon(
          onPressed: _loading ? null : _load,
          icon: _loading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_find),
          label: Text(l.translate('diag_scan')),
        ),
      ],
      children: [
        DiagSection(
          icon: Icons.wifi,
          title: l.translate('diag_your_wifi'),
          child: widget.c.snap == null ? const LinearProgressIndicator() : WifiTile(wifi: own),
        ),
        if (nets == null)
          DiagSection(
            icon: Icons.wifi_find,
            title: l.translate('diag_wifi_neighbours'),
            child: Text(l.translate('diag_wifi_press_scan'),
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else if (nets.isEmpty)
          DiagSection(
            icon: Icons.wifi_find,
            title: l.translate('diag_wifi_neighbours'),
            child: Text(l.translate('diag_wifi_neighbours_empty'),
                style: TextStyle(color: scheme.onSurfaceVariant)),
          )
        else ...[
          for (final five in [false, true])
            if (nets.any((n) => n.channel != null && n.is5GHz == five) ||
                (own?.channel != null && (own!.channel! > 14) == five))
              DiagSection(
                icon: Icons.bar_chart,
                title: '${l.translate('diag_channels')} ${five ? '5 GHz' : '2.4 GHz'}',
                child: _ChannelChart(
                  advice: DiagnosticsService.channelAdvice(nets, fiveGHz: five, ownBssid: ownBssid),
                  ownChannel: own?.connected == true &&
                          own!.channel != null &&
                          (own.channel! > 14) == five
                      ? own.channel
                      : null,
                ),
              ),
          DiagSection(
            icon: Icons.wifi_find,
            title: l.translate('diag_networks_visible').replaceAll('{count}', '${nets.length}'),
            child: Column(children: [
              for (final n in nets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    n.signalPercent >= 60
                        ? Icons.wifi
                        : n.signalPercent >= 35
                            ? Icons.wifi_2_bar
                            : Icons.wifi_1_bar,
                    color: n.bssid.toLowerCase() == ownBssid?.toLowerCase()
                        ? scheme.primary
                        : signalColor(n.signalPercent, scheme),
                  ),
                  title: Text(
                    n.ssid.isEmpty ? l.translate('diag_hidden_network') : n.ssid,
                    style: TextStyle(
                        fontWeight: n.bssid.toLowerCase() == ownBssid?.toLowerCase()
                            ? FontWeight.w700
                            : null),
                  ),
                  subtitle: Text([
                    if (n.channel != null) '${n.is5GHz ? '5 GHz' : '2.4 GHz'} · ch ${n.channel}',
                    if (n.security.isNotEmpty) n.security,
                    n.bssid,
                  ].join('  ·  ')),
                  trailing: SizedBox(
                    width: 120,
                    child: Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: n.signalPercent / 100,
                          color: signalColor(n.signalPercent, scheme),
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${n.signalPercent}%'),
                    ]),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _ChannelChart extends StatelessWidget {
  final ChannelAdvice advice;
  final int? ownChannel;
  const _ChannelChart({required this.advice, required this.ownChannel});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final maxLoad = math.max(1.0, advice.load.values.fold<double>(0, math.max));
    final best = advice.best;
    final tip = best == null
        ? ''
        : ownChannel == null
            ? l.translate('diag_best_channel').replaceAll('{channel}', '$best')
            : (advice.load[ownChannel] ?? 0) <= (advice.load[best] ?? 0) * 1.2 + 5
                ? l.translate('diag_channel_ok').replaceAll('{channel}', '$ownChannel')
                : l
                    .translate('diag_change_channel')
                    .replaceAll('{from}', '$ownChannel')
                    .replaceAll('{to}', '$best');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tip, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final e in advice.load.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Container(
                    height: 4 + 76 * (e.value / maxLoad),
                    decoration: BoxDecoration(
                      color: e.key == ownChannel
                          ? scheme.primary
                          : e.key == best
                              ? Colors.green.shade600
                              : scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${e.key}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              e.key == ownChannel || e.key == best ? FontWeight.w700 : null)),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 4),
      Wrap(spacing: 16, children: [
        _legend(scheme.primary, l.translate('diag_your_channel')),
        _legend(Colors.green.shade600, l.translate('diag_free_channel')),
      ]),
    ]);
  }

  Widget _legend(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}
