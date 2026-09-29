import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../providers/database_providers.dart';
import '../../services/daily_summary_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';

/// Products sold over a chosen period, for the kitchen: which dishes went out
/// and how many, optionally sectioned by category.
///
/// Reached from the Z dialog's reports section, which already cost
/// credentials. Works while a Z is open — unlike the Z report, it is not a
/// closing document, and "what have we sold since Monday" is a mid-week
/// question.
Future<void> showProductsSoldReportDialog(
    BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  var range = DateTimeRange(
    start: DateTime(now.year, now.month, now.day),
    end: DateTime(now.year, now.month, now.day),
  );
  var byCategory = true;
  var sort = ProductsSort.quantity;
  // Off by default: this is the kitchen's paper.
  var showAmounts = false;

  String day(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  String rangeLabel() => range.start == range.end
      ? day(range.start)
      : '${day(range.start)} → ${day(range.end)}';

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(l10n.translate('report_products_sold')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(rangeLabel()),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(now.year, now.month, now.day),
                      initialDateRange: range,
                    );
                    if (picked != null) setLocal(() => range = picked);
                  },
                ),
                const SizedBox(height: 14),
                Text(l10n.translate('report_sort_by'),
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                SegmentedButton<ProductsSort>(
                  segments: [
                    ButtonSegment(
                        value: ProductsSort.quantity,
                        label: Text(l10n.translate('report_sort_quantity'))),
                    ButtonSegment(
                        value: ProductsSort.amount,
                        label: Text(l10n.translate('report_sort_amount'))),
                    ButtonSegment(
                        value: ProductsSort.name,
                        label: Text(l10n.translate('report_sort_name'))),
                  ],
                  selected: {sort},
                  onSelectionChanged: (s) => setLocal(() => sort = s.first),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('report_group_by_category')),
                  value: byCategory,
                  onChanged: (v) => setLocal(() => byCategory = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.translate('report_show_prices')),
                  subtitle: Text(l10n.translate('report_show_prices_hint'),
                      style: const TextStyle(fontSize: 12)),
                  value: showAmounts,
                  onChanged: (v) => setLocal(() => showAmounts = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print),
            label: Text(l10n.translate('print')),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  try {
    final db = ref.read(databaseProvider);
    final summaries = DailySummaryService(db);
    final sessionIds =
        await summaries.sessionIdsForPeriod(range.start, range.end);
    final report = await summaries.generateProductsSummary(
      sessionIds: sessionIds,
      scopeLabel: rangeLabel(),
    );
    if (!context.mounted) return;
    if (report.rows.isEmpty) {
      SnackBarHelper.info(context, l10n.translate('report_no_sales_in_period'));
      return;
    }
    final ok = await ref.read(printingServiceProvider).printProductsSummary(
          report: report,
          businessName:
              ref.read(sharedPreferencesProvider).getString('business_name'),
          groupByCategory: byCategory,
          sort: sort,
          showAmounts: showAmounts,
        );
    if (!context.mounted) return;
    ok
        ? SnackBarHelper.success(
            context, l10n.translate('report_printed_successfully'))
        : SnackBarHelper.error(context, l10n.translate('print_error'));
  } catch (e) {
    Logger.instance.error('Products sold report failed: $e');
    if (context.mounted) {
      SnackBarHelper.error(context, l10n.translate('print_error'));
    }
  }
}
