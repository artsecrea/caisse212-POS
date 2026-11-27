import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/local_returns_service.dart';
import '../../providers/user_provider.dart';
import '../../services/permission_service.dart';
import '../../services/refund_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'order_refunds_panel.dart' show RefundRow;
import 'refund_dialog.dart' show showRefundReceiptDialog;

/// Every refund given, for whoever needs to answer "what went back today?".
///
/// Two views:
/// * **This till** — the local refund records. These are the rows the Z is
///   computed from and the slips were printed from, so they are right even
///   offline, and they show whether each one has reached the server yet.
/// * **All tills** — the server's listing across the business, for a manager
///   checking what other tills refunded. Needs the network and a server that
///   offers the listing; says so plainly when either is missing.
class RefundsScreen extends ConsumerStatefulWidget {
  const RefundsScreen({super.key});

  @override
  ConsumerState<RefundsScreen> createState() => _RefundsScreenState();
}

enum _Period { session, today, week, month }

class _RefundsScreenState extends ConsumerState<RefundsScreen> {
  _Period _period = _Period.today;
  int _tab = 0;

  List<Refund> _local = const [];
  bool _loadingLocal = true;
  int? _printing;

  List<Map<String, dynamic>>? _remote;
  bool _loadingRemote = false;
  String? _remoteError;

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.session => (today, now),
      _Period.today => (today, now),
      _Period.week => (today.subtract(const Duration(days: 6)), now),
      _Period.month => (today.subtract(const Duration(days: 29)), now),
    };
  }

  Future<void> _loadLocal() async {
    setState(() => _loadingLocal = true);
    final returns = ref.read(returnsServiceProvider);
    final List<Refund> rows;
    if (_period == _Period.session) {
      rows = await returns.refunds(
          sessionId: ref.read(currentSessionProvider)?.id);
    } else {
      final (from, _) = _range();
      rows = await returns.refunds(since: from);
    }
    if (mounted) {
      setState(() {
        _local = rows;
        _loadingLocal = false;
      });
    }
  }

  Future<void> _loadRemote() async {
    setState(() {
      _loadingRemote = true;
      _remoteError = null;
    });
    final (from, to) = _range();
    try {
      final page = await ref
          .read(apiServiceProvider)
          .fetchRefundsPage(from: from, to: to, size: 200);
      if (!mounted) return;
      setState(() {
        _remote = page == null
            ? null
            : List<Map<String, dynamic>>.from(page['content'] as List);
        _remoteError = page == null ? 'unsupported' : null;
        _loadingRemote = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _remote = null;
        _remoteError = 'offline';
        _loadingRemote = false;
      });
    }
  }

  void _reload() {
    _loadLocal();
    if (_tab == 1) _loadRemote();
  }

  Future<void> _reprint(Refund r) async {
    setState(() => _printing = r.id);
    try {
      final slip = await ref.read(returnsServiceProvider).slipFor(r);
      await ref.read(printingServiceProvider).printRefundSlip(
            data: slip,
            businessName:
                ref.read(sharedPreferencesProvider).getString('business_name'),
          );
    } finally {
      if (mounted) setState(() => _printing = null);
    }
  }

  Future<void> _showDetails(Refund r) async {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.read(currencySymbolProvider);
    final slip = await ref.read(returnsServiceProvider).slipFor(r);
    final users = ref.read(userRepositoryProvider);
    String? approver;
    if (r.approvedBy != null) {
      final u = await users.getUserById(r.approvedBy!);
      approver = u == null
          ? '#${r.approvedBy}'
          : ('${u.firstName} ${u.lastName}'.trim().isEmpty
              ? u.username
              : '${u.firstName} ${u.lastName}'.trim());
    }
    if (!mounted) return;
    String money(double v) => CurrencyFormatter.formatWithCurrency(v, currency);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.code,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kv(l10n.translate('order'), r.orderCode),
                _kv(l10n.translate('refund_method'), r.method),
                _kv(l10n.translate('cashier'), slip.cashierName ?? '—'),
                if (r.reason != null) _kv(l10n.translate('reason'), r.reason!),
                if (approver != null)
                  _kv(l10n.translate('refund_approved_by'), approver),
                if (r.earlierSale)
                  _kv(l10n.translate('refunds_earlier_sales'), '✓'),
                if ((r.policyFlags ?? '').isNotEmpty)
                  _kv(l10n.translate('refund_policy_flags'), r.policyFlags!),
                const Divider(height: 20),
                for (final line in slip.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${_qty(line.quantity)} × ${line.name}'
                          '${line.serialNumber == null ? '' : '  (${line.serialNumber})'}',
                        ),
                      ),
                      if (!line.restock)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Tooltip(
                            message: l10n.translate('refunds_waste'),
                            child: const Icon(Icons.delete_outline, size: 16),
                          ),
                        ),
                      Text(money(line.amount)),
                    ]),
                  ),
                const Divider(height: 20),
                Row(children: [
                  Expanded(
                    child: Text(l10n.translate('refund_total'),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Text(money(r.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _reprint(r);
            },
            icon: const Icon(Icons.print),
            label: Text(l10n.translate('reprint_slip')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('close')),
          ),
        ],
      ),
    );
  }

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(k,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Expanded(child: Text(v)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencySymbolProvider);
    final permissions = ref.read(permissionServiceProvider);
    final canRefund = permissions.hasPermission(Permissions.ticketsCreate) &&
        permissions.hasRefundPermission(Permissions.refundsCreate);
    String money(double v) => CurrencyFormatter.formatWithCurrency(v, currency);

    final periodLabels = {
      _Period.session: l10n.translate('current_session'),
      _Period.today: l10n.translate('today'),
      _Period.week: l10n.translate('last_7_days'),
      _Period.month: l10n.translate('last_30_days'),
    };

    // Totals of what is on screen.
    final double total;
    final double cash;
    final int count;
    if (_tab == 0) {
      final b = RefundBreakdown.fromRows(_local, const {});
      total = b.total;
      cash = b.cash;
      count = b.count;
    } else {
      final rows = _remote ?? const [];
      double amt(Map<String, dynamic> r) =>
          (r['totalAmount'] as num?)?.toDouble() ?? 0;
      total = rows.fold(0.0, (s, r) => s + amt(r));
      cash = rows
          .where((r) => '${r['method']}'.toUpperCase() == 'CASH')
          .fold(0.0, (s, r) => s + amt(r));
      count = rows.length;
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.translate('refunds')),
          actions: [
            IconButton(
              tooltip: l10n.translate('refresh'),
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
            if (canRefund)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final done = await showRefundReceiptDialog(
                        context: context, ref: ref);
                    if (done) _reload();
                  },
                  icon: const Icon(Icons.assignment_return),
                  label: Text(l10n.translate('refund')),
                ),
              ),
          ],
          bottom: TabBar(
            onTap: (i) {
              setState(() => _tab = i);
              if (i == 1 && _remote == null && _remoteError == null) {
                _loadRemote();
              }
            },
            tabs: [
              Tab(text: l10n.translate('this_till')),
              Tab(text: l10n.translate('all_tills')),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final p in _Period.values)
                    // "Current session" only means something for this till.
                    if (p != _Period.session || _tab == 0)
                      ChoiceChip(
                        label: Text(periodLabels[p]!),
                        selected: _period == p,
                        onSelected: (_) {
                          setState(() => _period = p);
                          _reload();
                        },
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                _Stat(label: l10n.translate('refund_count'), value: '$count'),
                const SizedBox(width: 12),
                _Stat(label: l10n.translate('total_refunds'), value: money(total)),
                const SizedBox(width: 12),
                _Stat(label: l10n.translate('refunds_cash_out'), value: money(cash)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [_buildLocal(l10n, currency), _buildRemote(l10n, money)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocal(AppLocalizations l10n, String currency) {
    if (_loadingLocal) return const Center(child: CircularProgressIndicator());
    if (_local.isEmpty) {
      return Center(child: Text(l10n.translate('no_refunds')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _local.length,
      itemBuilder: (_, i) {
        final r = _local[i];
        return InkWell(
          onTap: () => _showDetails(r),
          child: RefundRow(
            refund: r,
            currency: currency,
            l10n: l10n,
            isPrinting: _printing == r.id,
            onReprint: () => _reprint(r),
            subtitle: r.orderCode,
          ),
        );
      },
    );
  }

  Widget _buildRemote(AppLocalizations l10n, String Function(double) money) {
    if (_loadingRemote) return const Center(child: CircularProgressIndicator());
    if (_remoteError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(_remoteError == 'offline' ? Icons.wifi_off : Icons.cloud_off,
                size: 40),
            const SizedBox(height: 12),
            Text(
              l10n.translate(_remoteError == 'offline'
                  ? 'action_needs_network'
                  : 'refunds_all_tills_unavailable'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
                onPressed: _loadRemote, child: Text(l10n.translate('retry'))),
          ]),
        ),
      );
    }
    final rows = _remote ?? const [];
    if (rows.isEmpty) return Center(child: Text(l10n.translate('no_refunds')));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final r = rows[i];
        final at = DateTime.tryParse('${r['refundedAt']}')?.toLocal();
        final till = r['posTerminalName'] ?? r['posTerminalId'] ?? '—';
        final flags = (r['policyFlags'] as List?)?.join(', ');
        return ListTile(
          leading: const Icon(Icons.assignment_return),
          title: Text('${r['code']}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          subtitle: Text([
            '${r['orderCode'] ?? ''}',
            '${r['method'] ?? ''}',
            '${l10n.translate('till')}: $till',
            if (at != null)
              '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')} '
                  '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
            if (r['refundedByName'] != null) '${r['refundedByName']}',
            if (flags != null && flags.isNotEmpty) flags,
          ].join(' · ')),
          trailing: Text(
            money((r['totalAmount'] as num?)?.toDouble() ?? 0),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
