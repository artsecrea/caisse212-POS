import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../services/data_sync_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

class SyncInspectorDialog extends ConsumerStatefulWidget {
  const SyncInspectorDialog({super.key});

  @override
  ConsumerState<SyncInspectorDialog> createState() =>
      _SyncInspectorDialogState();
}

class _SyncInspectorDialogState extends ConsumerState<SyncInspectorDialog> {
  Map<String, String?>? _meta;
  bool _isPulling = false;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final database = ref.read(databaseProvider);
    final apiService = ref.read(apiServiceProvider);
    final syncService = DataSyncService(database, apiService);
    final meta = await syncService.getDeltaSyncMeta(prefs);
    if (mounted) setState(() => _meta = meta);
  }

  DataSyncService _sync() {
    final database = ref.read(databaseProvider);
    final apiService = ref.read(apiServiceProvider);
    return DataSyncService(database, apiService);
  }

  Future<void> _resetOrdersCursor() async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(sharedPreferencesProvider);
    await _sync().resetOrdersCursor(prefs);
    await _loadMeta();
    if (mounted) {
      SnackBarHelper.showSnackBar(
          context, ref, l10n?.translate('sync_cursor_reset') ?? 'Cursor reset');
    }
  }

  Future<void> _resetPaymentsCursor() async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(sharedPreferencesProvider);
    await _sync().resetPaymentsCursor(prefs);
    await _loadMeta();
    if (mounted) {
      SnackBarHelper.showSnackBar(
          context, ref, l10n?.translate('sync_cursor_reset') ?? 'Cursor reset');
    }
  }

  Future<void> _forceFullPull() async {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.read(sharedPreferencesProvider);
    final syncService = _sync();
    setState(() => _isPulling = true);
    try {
      await syncService.resetOrdersCursor(prefs);
      await syncService.resetPaymentsCursor(prefs);
      await syncService.pullAllDeltas(prefs);
      await _loadMeta();
      if (mounted) {
        SnackBarHelper.showSnackBar(context, ref,
            l10n?.translate('sync_force_full_pull_done') ?? 'Full re-pull done');
      }
    } finally {
      if (mounted) setState(() => _isPulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n?.translate('sync_inspector_title') ?? 'Sync inspector'),
      content: SizedBox(
        width: 440,
        child: _meta == null
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StreamSection(
                    label: l10n?.translate('sync_stream_orders') ??
                        'Orders stream',
                    cursor: _meta!['ordersCursor'],
                    lastSync: _meta!['ordersLastSync'],
                    onReset: _resetOrdersCursor,
                    l10n: l10n,
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 12),
                  _StreamSection(
                    label: l10n?.translate('sync_stream_payments') ??
                        'Payments stream',
                    cursor: _meta!['paymentsCursor'],
                    lastSync: _meta!['paymentsLastSync'],
                    onReset: _resetPaymentsCursor,
                    l10n: l10n,
                    colorScheme: colorScheme,
                  ),
                  if (_meta!['lastError'] != null) ...[
                    const SizedBox(height: 12),
                    _SectionHeader(
                        label: l10n?.translate('sync_last_error') ??
                            'Last error'),
                    const SizedBox(height: 4),
                    Text(
                      _meta!['lastError']!,
                      style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.error,
                          fontFamily: 'monospace'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        if (_isPulling)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        TextButton(
          onPressed: _isPulling ? null : _forceFullPull,
          child: Text(l10n?.translate('sync_force_full_pull') ??
              'Force full re-pull'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n?.translate('close') ?? 'Close'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) => Text(
        '── $label ──',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      );
}

class _StreamSection extends StatelessWidget {
  final String label;
  final String? cursor;
  final String? lastSync;
  final VoidCallback onReset;
  final AppLocalizations? l10n;
  final ColorScheme colorScheme;

  const _StreamSection({
    required this.label,
    required this.cursor,
    required this.lastSync,
    required this.onReset,
    required this.l10n,
    required this.colorScheme,
  });

  String _truncate(String s) =>
      s.length > 38 ? '${s.substring(0, 35)}…' : s;

  @override
  Widget build(BuildContext context) {
    final noCursor = l10n?.translate('sync_no_cursor') ?? '(none)';
    final never = l10n?.translate('sync_never') ?? 'never';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: label),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '${l10n?.translate('sync_cursor') ?? 'Cursor'}: ',
              style: const TextStyle(fontSize: 12),
            ),
            Expanded(
              child: Text(
                cursor != null ? _truncate(cursor!) : noCursor,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: cursor != null
                      ? colorScheme.onSurface
                      : colorScheme.outline,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (cursor != null)
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                tooltip: l10n?.translate('sync_cursor_copy') ?? 'Copy cursor',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cursor!));
                },
              ),
          ],
        ),
        Text(
          '${l10n?.translate('sync_last_sync') ?? 'Last sync'}: ${lastSync ?? never}',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.restart_alt, size: 14),
          label: Text(
              l10n?.translate('sync_reset_cursor') ?? 'Reset cursor',
              style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}
