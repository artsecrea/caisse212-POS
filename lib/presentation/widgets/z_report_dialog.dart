import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../domain/models/z_day_option.dart';
import '../../providers/database_providers.dart';
import '../../providers/floor_repository.dart';
import '../../providers/settings_provider.dart';
import '../../providers/user_provider.dart';
import 'report_documents.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// Print a Z report for a chosen trading day, picking the documents freely.
///
/// The caller is responsible for establishing who is asking — the top bar and
/// the login screen both put [showAdminCredentialDialog] in front of this.
///
/// Each ticked document prints separately with its own cut, and each failure
/// is isolated so one dead document cannot swallow the rest — same shape as
/// [showSessionReportsDialog], which this is the day-level counterpart to.
Future<void> showPrintZReportDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final zService = ref.read(zServiceProvider);

  if (await zService.reportBlockedByOpenShift()) {
    if (context.mounted) {
      SnackBarHelper.error(context, l10n.translate('z_report_blocked_open'));
    }
    return;
  }

  final days = await zService.zDayOptions();
  if (!context.mounted) return;
  if (days.isEmpty) {
    SnackBarHelper.error(context, l10n.translate('no_z_days_to_report'));
    return;
  }

  var selected = days.first;
  var includeTotals = true;
  final documents = ReportDocuments.fromSettings(ref.read(settingsProvider));
  final staff = await StaffChoices.load(ref.read(floorRepositoryProvider),
      ref.read(userRepositoryProvider), l10n);
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(l10n.translate('print_z_report')),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<ZDayOption>(
                    initialValue: selected,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.translate('z_day'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final d in days)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            '${d.label}   (${d.sessionIds.length} '
                            '${l10n.translate('sessions').toLowerCase()})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => selected = v ?? selected),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.translate('documents_to_print'),
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                  // The Z totals ticket is this dialog's own — it is the
                  // summary itself, not one of the extras.
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: includeTotals,
                    onChanged: (v) =>
                        setLocal(() => includeTotals = v ?? false),
                    title: Text(l10n.translate('z_totals')),
                    subtitle: Text(
                      l10n.translate('z_totals_hint'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  // Everything else is the set the session-close dialog offers
                  // too — see [ReportDocumentsPicker].
                  ReportDocumentsPicker(
                    documents: documents,
                    staff: staff,
                    onChanged: (persist) => setLocal(
                        () => persist(ref.read(settingsProvider.notifier))),
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
            ElevatedButton.icon(
              // Nothing ticked would print nothing and report success.
              onPressed: (includeTotals || documents.anySelected)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              icon: const Icon(Icons.print_rounded, size: 18),
              label: Text(l10n.translate('print')),
            ),
          ],
        );
      },
    ),
  );
  if (go != true || !context.mounted) return;

  final scope = selected;
  var printed = 0;
  var attempted = 0;

  if (includeTotals) {
    attempted++;
    try {
      final summaries = ref.read(dailySummaryServiceProvider);
      final report = await summaries.generateReport(
        startDate: scope.day,
        endDate: scope.day,
        sessionIds: scope.sessionIds,
      );
      final ok = await ref.read(printingServiceProvider).printDailySummaryReport(
        report: report,
        reportType: 'Z',
        // Every Z of the day was printed when it closed; this is a copy.
        isReprint: true,
        l10n: l10n,
        currencyFormatter: ref.read(currencyFormatterProvider),
        businessName:
            ref.read(sharedPreferencesProvider).getString('business_name'),
      );
      if (ok) printed++;
    } catch (e) {
      Logger.instance.error('Z totals print failed: $e');
    }
  }

  final run = await printReportDocuments(
    ref: ref,
    documents: documents,
    sessionIds: scope.sessionIds,
    scopeLabel: scope.label,
    l10n: l10n,
    sessionCodes: scope.sessionCodes,
    zCode: scope.zCode,
    zNumber: scope.zNumber,
  );
  printed += run.printed;
  attempted += run.attempted;

  if (!context.mounted) return;
  if (printed == attempted) {
    SnackBarHelper.success(context,
        l10n.translate('z_report_printed').replaceAll('{0}', '$printed'));
  } else {
    // Says what actually came out: a printer that quit after the first of
    // three documents must not read as done.
    SnackBarHelper.error(
        context,
        l10n
            .translate('x_report_printed_partial')
            .replaceAll('{0}', '$printed')
            .replaceAll('{1}', '$attempted'));
  }
}
