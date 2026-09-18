import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../services/data_sync_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../../data/database/app_database.dart';
import '../../core/theme/app_theme.dart';

class SyncInspectorDialog extends ConsumerStatefulWidget {
  const SyncInspectorDialog({super.key});

  @override
  ConsumerState<SyncInspectorDialog> createState() =>
      _SyncInspectorDialogState();
}

class _SyncInspectorDialogState extends ConsumerState<SyncInspectorDialog> {
  Map<String, String?>? _meta;
  bool _isPulling = false;

  /// Refunds the server refused. They are deliberately never auto-retried —
  /// every rejection reason is deterministic — so this dialog is the only place
  /// they surface. A parked refund means money left the drawer with no server
  /// record, which is exactly the thing that must not sit invisible.
  List<Refund> _parked = const [];

  @override
  void initState() {
    super.initState();
    _loadMeta();
    _loadParked();
  }

  Future<void> _loadParked() async {
    final parked = await _sync().parkedRefunds();
    if (mounted) setState(() => _parked = parked);
  }

  Future<void> _retryParked(Refund refund) async {
    final l10n = AppLocalizations.of(context);
    // Clears the marker and pushes again. Manual on purpose: the cause is
    // usually fixed elsewhere (the order finally synced, a mapping corrected),
    // and a human deciding "try it now" is the signal that changed.
    await _sync().unparkRefund(refund.id);
    await _sync().syncRefundsBulk();
    await _loadParked();
    if (mounted) {
      SnackBarHelper.showSnackBar(context, ref,
          l10n?.translate('refund_retry_queued') ?? 'Retrying…');
    }
  }

  Future<void> _copyCode(String code) async {
    final l10n = AppLocalizations.of(context);
    // Support asks for the refund code, and reading a 20-character string off a
    // till screen over the phone is how digits get transposed.
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      SnackBarHelper.showSnackBar(
          context, ref, l10n?.translate('copied') ?? 'Copied');
    }
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
                  if (_parked.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _SectionHeader(
                        label:
                            '${l10n?.translate('refunds_refused') ?? 'Refused refunds'} (${_parked.length})'),
                    const SizedBox(height: 4),
                    // Capped height: a terminal that has accumulated a dozen of
                    // these must not push the dialog's actions off screen.
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _parked.length,
                        itemBuilder: (context, i) {
                          final r = _parked[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.errorContainer
                                  .withValues(alpha: 0.35),
                              borderRadius: AppTheme.brSm,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r.code,
                                        style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: l10n?.translate('copy_code') ??
                                          'Copy code',
                                      icon: const Icon(Icons.copy, size: 16),
                                      onPressed: () => _copyCode(r.code),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip:
                                          l10n?.translate('retry') ?? 'Retry',
                                      icon: const Icon(Icons.refresh, size: 16),
                                      onPressed: () => _retryParked(r),
                                    ),
                                  ],
                                ),
                                // The server's own words, verbatim — a
                                // paraphrase is useless to whoever has to fix it.
                                Text(
                                  r.syncError ?? '',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.error,
                                      fontFamily: 'monospace'),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
