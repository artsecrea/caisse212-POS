import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../core/theme/app_theme.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/permission_service.dart';
import '../../domain/models/refund_sync_state.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// Refunds already recorded against an order.
///
/// Refund state lives nowhere else: the order stays COMPLETED and the ticket
/// keeps its original total, so without this panel a refunded order is
/// indistinguishable from an untouched one on screen.
///
/// Reads local rows only. They are the same rows the slip was printed from and
/// the same ones queued for sync, so this is accurate offline — which is when
/// somebody is most likely to be asking "did that refund go through?".
class OrderRefundsPanel extends ConsumerStatefulWidget {
  final int orderId;

  const OrderRefundsPanel({super.key, required this.orderId});

  @override
  ConsumerState<OrderRefundsPanel> createState() => _OrderRefundsPanelState();
}

class _OrderRefundsPanelState extends ConsumerState<OrderRefundsPanel> {
  List<Refund> _refunds = const [];
  bool _loading = true;
  int? _printing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows =
        await ref.read(refundServiceProvider).refundsForOrder(widget.orderId);
    if (mounted) {
      setState(() {
        _refunds = rows;
        _loading = false;
      });
    }
  }

  Future<void> _reprint(Refund refund) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _printing = refund.id);
    try {
      // Rebuilt from stored rows, so a reprint is identical to the original
      // even if the catalogue changed in between.
      final slip = await ref.read(refundServiceProvider).slipFor(refund);
      final ok = await ref.read(printingServiceProvider).printRefundSlip(
            data: slip,
            businessName:
                ref.read(sharedPreferencesProvider).getString('business_name'),
          );
      if (!mounted) return;
      if (ok) {
        SnackBarHelper.success(context, l10n.translate('refund_slip_printed'));
      } else {
        SnackBarHelper.error(context, l10n.translate('print_failed'));
      }
    } catch (e) {
      Logger.instance.error('Refund slip reprint failed: $e');
      if (mounted) SnackBarHelper.error(context, l10n.translate('print_failed'));
    } finally {
      if (mounted) setState(() => _printing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final currency = ref.watch(currencySymbolProvider);

    // Seeing what was refunded is its own permission — it exposes money
    // movements a plain cashier may not be meant to audit.
    final canView = ref
        .read(permissionServiceProvider)
        .hasRefundPermission(Permissions.refundsView);
    if (!canView) return const SizedBox.shrink();

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.assignment_return, size: 18, color: cs.error),
            const SizedBox(width: 8),
            Text(
              l10n.translate('refunds'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_refunds.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.translate('no_refunds'),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          )
        else
          ..._refunds.map((r) => _RefundRow(
                refund: r,
                currency: currency,
                l10n: l10n,
                isPrinting: _printing == r.id,
                onReprint: () => _reprint(r),
              )),
      ],
    );
  }
}

class _RefundRow extends StatelessWidget {
  final Refund refund;
  final String currency;
  final AppLocalizations l10n;
  final bool isPrinting;
  final VoidCallback onReprint;

  const _RefundRow({
    required this.refund,
    required this.currency,
    required this.l10n,
    required this.isPrinting,
    required this.onReprint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parked = refund.syncError != null && !refund.isSynced;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: AppTheme.brSm,
        border: Border.all(
          color: parked ? cs.error : cs.outlineVariant,
          width: parked ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  refund.code,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                CurrencyFormatter.formatWithCurrency(
                    refund.totalAmount, currency),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: cs.error),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${refund.method} · ${_fmtDate(refund.refundedAt)}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              // Sync state matters here more than elsewhere: a refund is money
              // already handed over, so "not on the server yet" is a fact the
              // cashier should be able to see without opening the inspector.
              _SyncBadge(
                synced: refund.isSynced,
                parked: parked,
                refundedAt: refund.refundedAt,
                l10n: l10n,
              ),
              const Spacer(),
              if (isPrinting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: l10n.translate('reprint_slip'),
                  icon: const Icon(Icons.print, size: 18),
                  onPressed: onReprint,
                ),
            ],
          ),
          if (parked) ...[
            const SizedBox(height: 4),
            Text(
              refund.syncError!,
              style: TextStyle(
                  fontSize: 11, color: cs.error, fontFamily: 'monospace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _SyncBadge extends StatelessWidget {
  final bool synced;
  final bool parked;
  final DateTime refundedAt;
  final AppLocalizations l10n;

  const _SyncBadge({
    required this.synced,
    required this.parked,
    required this.refundedAt,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // A refund that has been refused for hours is a different problem from one
    // refused a minute ago, and the terminal retries both identically — so the
    // badge is the only place the difference can show.
    final state = refundSyncState(
      isSynced: synced,
      syncError: parked ? 'refused' : null,
      refundedAt: refundedAt,
      now: DateTime.now(),
    );
    final (IconData icon, Color color, String label) = switch (state) {
      RefundSyncState.stuck => (
          Icons.report_problem_outlined,
          cs.error,
          l10n.translate('sync_stuck')
        ),
      RefundSyncState.failing => (
          Icons.error_outline,
          cs.error,
          l10n.translate('sync_refused')
        ),
      RefundSyncState.synced => (
          Icons.cloud_done,
          Colors.green,
          l10n.translate('synced')
        ),
      RefundSyncState.queued => (
          Icons.cloud_upload_outlined,
          cs.onSurfaceVariant,
          l10n.translate('pending_sync')
        ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}
