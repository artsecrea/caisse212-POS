import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../services/activity_log_service.dart';
import '../../utils/app_localizations.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  // ── Filters ────────────────────────────────────────────────────────────
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ── Pagination state ───────────────────────────────────────────────────
  static const int _pageSize = 50;
  final List<ActivityLog> _logs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  // Bumped on filter changes so a stale in-flight page can be discarded.
  int _loadGen = 0;

  // ── Misc ───────────────────────────────────────────────────────────────
  bool _isExporting = false;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reloadFromStart();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger the next page when within ~400px of the bottom.
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  /// Reset pagination and load the first page (called on filter changes / init).
  void _reloadFromStart() {
    setState(() {
      _logs.clear();
      _offset = 0;
      _hasMore = true;
      _isLoading = false;
      _loadGen++;
    });
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    final gen = _loadGen;
    setState(() => _isLoading = true);

    DateTime? to = _endDate;
    if (to != null) {
      to = DateTime(to.year, to.month, to.day, 23, 59, 59, 999);
    }
    final from = _startDate != null
        ? DateTime(_startDate!.year, _startDate!.month, _startDate!.day)
        : null;

    try {
      final page = await ref.read(activityLogServiceProvider).getLogsPage(
            from: from,
            to: to,
            search: _searchQuery,
            limit: _pageSize,
            offset: _offset,
          );
      // Discard if filters changed during the await.
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _logs.addAll(page);
        _offset += page.length;
        _hasMore = page.length == _pageSize;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      _searchQuery = value;
      _reloadFromStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('activity_logs')),
        actions: [
          IconButton(
            tooltip: l10n.translate('refresh'),
            onPressed: _reloadFromStart,
            icon: const Icon(Icons.refresh),
          ),
          TextButton.icon(
            onPressed: _isExporting ? null : _exportNow,
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(l10n.translate('export_now')),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildFiltersBar(l10n),
          Expanded(child: _buildList(l10n)),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    if (_logs.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_logs.isEmpty) {
      return Center(
        child: Text(l10n.translate('no_logs'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
      );
    }
    // One extra slot at the end for the loading/end indicator.
    final itemCount = _logs.length + 1;
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(8),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        if (i == _logs.length) return _buildFooter();
        return _buildRow(_logs[i]);
      },
    );
  }

  Widget _buildFooter() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore) {
      // End-of-list marker — invisible spacer (avoid a chatty UI).
      return const SizedBox(height: 24);
    }
    return const SizedBox.shrink();
  }

  Widget _buildFiltersBar(AppLocalizations l10n) {
    final hasRange = _startDate != null || _endDate != null;
    String label;
    if (_startDate != null && _endDate != null) {
      label = '${_fmtShort(_startDate!)} - ${_fmtShort(_endDate!)}';
    } else {
      label = l10n.translate('date_range');
    }
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range),
            label: Text(label),
          ),
          if (hasRange)
            IconButton(
              tooltip: l10n.translate('clear_dates'),
              icon: const Icon(Icons.clear),
              onPressed: () {
                _startDate = null;
                _endDate = null;
                _reloadFromStart();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ActivityLog log) {
    return ListTile(
      dense: true,
      leading: _actionChip(log.actionType),
      title: Text(log.phrase),
      subtitle: Text(_fmtFull(log.timestamp), style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _actionChip(String actionType) {
    final isOrder = actionType.startsWith('ORDER');
    final isSession = actionType.startsWith('SESSION');
    final color = actionType == 'PAYMENT'
        ? Colors.green
        : actionType == 'LOGIN' || actionType == 'LOGOUT'
            ? Colors.blueGrey
            : isSession
                ? Colors.orange
                : isOrder
                    ? Colors.indigo
                    : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = actionType == 'PAYMENT'
        ? Icons.payments
        : actionType == 'LOGIN'
            ? Icons.login
            : actionType == 'LOGOUT'
                ? Icons.logout
                : isSession
                    ? Icons.point_of_sale
                    : Icons.receipt_long;
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(icon, size: 16, color: color),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      _startDate = picked.start;
      _endDate = picked.end;
      _reloadFromStart();
    }
  }

  Future<void> _exportNow() async {
    setState(() => _isExporting = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final count = await ref.read(activityLogServiceProvider).exportNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                l10n.translate('logs_exported').replaceAll('{0}', '$count')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  String _fmtFull(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
