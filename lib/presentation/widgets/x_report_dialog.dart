import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/daily_summary_service.dart';
import '../../services/permission_service.dart';
import '../../services/unpaid_orders_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// Print an X report for one session, with the optional extra documents the
/// cashier ticks.
///
/// X rather than Z on purpose: this is a read-only snapshot of a shift. It
/// closes nothing, writes nothing, and prints the same whether the session is
/// still open or was closed months ago — so it is safe to fire from a live
/// session. Ending a shift stays with the close-session dialog, which is
/// where a Z belongs.
///
/// Shared by the top bar's "current session" dialog and by Sessions
/// management's per-session dialog, because both offer the same action on the
/// same data and a second copy would drift.
///
/// Each selected document prints separately with its own cut (same shape as
/// session close), and each failure is isolated so one dead document cannot
/// swallow the rest.
///
/// The tick boxes are seeded from the close-time print settings but
/// deliberately do NOT write back to them: this is an ad-hoc reprint, and
/// silently re-configuring what session close does from here would be a
/// surprise. (The Z management dialog does write back — there, ticking is
/// part of configuring the close itself.)
Future<void> showPrintXReportDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CashSession session,
}) async {
  final l10n = AppLocalizations.of(context)!;
  if (!ref
      .read(permissionServiceProvider)
      .hasPermission(Permissions.reportsView)) {
    SnackBarHelper.error(context, l10n.translate('no_permission'));
    return;
  }

  final settings = ref.read(settingsProvider);
  var includeOrders = settings.printOrdersListOnClose;
  var includeProducts = settings.printProductSummaryOnClose;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(l10n.translate('print_x_report')),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${l10n.translate('session')}: ${session.code}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.translate('also_include'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: includeOrders,
                onChanged: (v) => setLocal(() => includeOrders = v ?? false),
                title: Text(l10n.translate('print_orders_list')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: includeProducts,
                onChanged: (v) => setLocal(() => includeProducts = v ?? false),
                title: Text(l10n.translate('print_product_summary')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text(l10n.translate('print')),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  final printingService = ref.read(printingServiceProvider);
  final dailySummary = DailySummaryService(ref.read(databaseProvider));
  final businessName =
      ref.read(sharedPreferencesProvider).getString('business_name');
  final currencyFormatter = ref.read(currencyFormatterProvider);
  var printed = 0;
  var attempted = 0;

  attempted++;
  try {
    final report = await dailySummary.generateSessionReport(session.id);
    // Live, not period: an X is read mid-shift precisely to see where things
    // stand, and where things stand includes the tables nobody has paid yet.
    UnpaidOrdersSummary? outstanding;
    try {
      outstanding =
          await UnpaidOrdersService(ref.read(databaseProvider)).summary();
    } catch (e) {
      Logger.instance.error('X report outstanding lookup failed: $e');
    }
    final ok = await printingService.printDailySummaryReport(
      report: report,
      reportType: 'X',
      l10n: l10n,
      currencyFormatter: currencyFormatter,
      businessName: businessName,
      outstanding: outstanding,
    );
    if (ok) printed++;
  } catch (e) {
    Logger.instance.error('X report print failed: $e');
  }

  if (includeOrders) {
    attempted++;
    try {
      final r = await dailySummary.ordersListForSession(session.id);
      final ok = await printingService.printOrdersList(
          report: r, businessName: businessName);
      if (ok) printed++;
    } catch (e) {
      Logger.instance.error('X report orders list failed: $e');
    }
  }

  if (includeProducts) {
    attempted++;
    try {
      final r = await dailySummary.productsSummaryForSession(session.id);
      final ok = await printingService.printProductsSummary(
          report: r, businessName: businessName);
      if (ok) printed++;
    } catch (e) {
      Logger.instance.error('X report products summary failed: $e');
    }
  }

  if (!context.mounted) return;
  if (printed == attempted) {
    SnackBarHelper.success(context,
        l10n.translate('x_report_printed').replaceAll('{0}', '$printed'));
  } else {
    // Says what actually came out rather than claiming success: a printer that
    // quit after the first of three documents must not read as done.
    SnackBarHelper.error(
        context,
        l10n
            .translate('x_report_printed_partial')
            .replaceAll('{0}', '$printed')
            .replaceAll('{1}', '$attempted'));
  }
}
