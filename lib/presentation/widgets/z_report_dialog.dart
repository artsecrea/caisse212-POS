import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/daily_summary_service.dart';
import 'report_documents.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

/// One trading day that has something to report on, with what it holds.
///
/// Built from cash sessions rather than from the `zs` table on purpose: a shop
/// that never switched Z tracking on has no Z rows at all, and its days are
/// exactly as reportable. When a Z does exist for the day its code and number
/// ride along for the ticket header.
class ZDayOption {
  final DateTime day;
  final List<int> sessionIds;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;

  const ZDayOption({
    required this.day,
    required this.sessionIds,
    required this.sessionCodes,
    this.zCode,
    this.zNumber,
  });

  String get label {
    final d = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    if (zNumber != null) return '$d  ·  Z$zNumber';
    if (zCode != null) return '$d  ·  $zCode';
    return d;
  }
}

/// Every day that has at least one cash session, newest first.
///
/// Capped because this feeds a dropdown, not an archive browser; a shop
/// wanting an older day has the sessions screen. The cap is generous enough
/// to cover a quarter of trading.
Future<List<ZDayOption>> loadZDayOptions(AppDatabase db,
    {int limitDays = 120}) async {
  final sessions = await (db.select(db.cashSessions)
        ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
      .get();

  final byDay = <DateTime, List<CashSession>>{};
  for (final s in sessions) {
    final d = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
    byDay.putIfAbsent(d, () => []).add(s);
  }

  // Z rows are matched by the day they opened on, which is how a session's
  // z-day is derived everywhere else (see `zDayForSession`).
  final zs = await db.select(db.zs).get();
  final zByDay = <DateTime, Z>{};
  for (final z in zs) {
    final d = DateTime(z.startedAt.year, z.startedAt.month, z.startedAt.day);
    zByDay.putIfAbsent(d, () => z);
  }

  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days.take(limitDays))
      ZDayOption(
        day: day,
        sessionIds: [for (final s in byDay[day]!) s.id],
        sessionCodes: [for (final s in byDay[day]!) s.code],
        zCode: zByDay[day]?.code,
        zNumber: zDetailNumber(zByDay[day]),
      ),
  ];
}

/// The Z number stashed in the row's JSON `details` blob — see
/// [ZService.ensureOpenZ], which puts it there so the number reaches the
/// backend without a schema change.
int? zDetailNumber(Z? z) {
  final raw = z?.details;
  if (raw == null || raw.isEmpty) return null;
  try {
    final match = RegExp(r'"number"\s*:\s*(\d+)').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(1)!);
  } catch (_) {
    return null;
  }
}

/// Print a Z report for a chosen trading day, picking the documents freely.
///
/// Deliberately independent of the `zTrackingEnabled` setting. That switch
/// governs whether the terminal RUNS a Z shift lifecycle (opening, closing,
/// day locks); it has never had anything to do with whether a manager may
/// read a day's totals back, and gating this on it left an admin unable to
/// see their own trading figures on a terminal that simply closes sessions.
///
/// The caller is responsible for establishing who is asking — the top bar and
/// the login screen both put [showAdminCredentialDialog] in front of this.
///
/// Each ticked document prints separately with its own cut, and each failure
/// is isolated so one dead document cannot swallow the rest — same shape as
/// [showPrintXReportDialog], which this is the day-level counterpart to.
Future<void> showPrintZReportDialog({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final db = ref.read(databaseProvider);

  final days = await loadZDayOptions(db);
  if (!context.mounted) return;
  if (days.isEmpty) {
    SnackBarHelper.error(context, l10n.translate('no_z_days_to_report'));
    return;
  }

  var selected = days.first;
  var includeTotals = true;
  final documents = ReportDocuments.fromSettings(ref.read(settingsProvider));
  final staff = await StaffChoices.load(db, l10n);
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
      final report = await DailySummaryService(db).generateReport(
        startDate: scope.day,
        endDate: scope.day,
        sessionIds: scope.sessionIds,
      );
      final ok = await ref.read(printingServiceProvider).printDailySummaryReport(
        report: report,
        reportType: 'Z',
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
