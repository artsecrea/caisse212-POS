import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../domain/models/app_settings.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/daily_summary_service.dart';
import '../../services/unpaid_orders_service.dart';
import '../../utils/app_localizations.dart';

/// One selectable person in a staff picker. `id == null` is the "everyone"
/// entry, which is the default and prints the full breakdown.
typedef StaffChoice = ({int? id, String name});

/// Which end-of-shift documents to print, and for whom.
///
/// The Z dialog and the session-close dialog offer the same set — a manager
/// closing a till wants the same papers whether they reach them from one
/// place or the other — so the choice, the UI and the printing live here once
/// rather than in two copies that drift.
///
/// The Z *totals* ticket is deliberately NOT part of this: it is the summary
/// itself, and each host prints its own (an X on close, a Z from the dialog)
/// with its own heading and its own scope.
class ReportDocuments {
  bool orders;
  bool products;

  /// Shapes the products ticket rather than adding one — only meaningful
  /// alongside [products].
  bool byCategory;

  bool unpaid;

  /// The reductions ticket: every order something came off, with the amount.
  bool discounts;

  bool byWaiter;
  bool byCashier;

  /// Null = every one of them, which is the default.
  int? waiterId;
  int? cashierId;

  ReportDocuments({
    this.orders = false,
    this.products = false,
    this.byCategory = true,
    this.unpaid = false,
    this.discounts = false,
    this.byWaiter = false,
    this.byCashier = false,
    this.waiterId,
    this.cashierId,
  });

  /// Seeded from the remembered ticks, so a shop that always wants a document
  /// ticks it once.
  factory ReportDocuments.fromSettings(AppSettings s) => ReportDocuments(
        orders: s.printOrdersListOnClose,
        products: s.printProductSummaryOnClose,
        byCategory: s.printProductsByCategoryOnClose,
        unpaid: s.printUnpaidOnClose,
        discounts: s.printDiscountsOnClose,
        byWaiter: s.printSalesByWaiterOnClose,
        byCashier: s.printSalesByCashierOnClose,
      );

  bool get anySelected =>
      orders || products || unpaid || discounts || byWaiter || byCashier;
}

/// The waiters and cashiers a staff picker can offer.
///
/// Loaded once by the host and handed in: both lists are small, and querying
/// them inside a `StatefulBuilder` would hit the database on every rebuild.
class StaffChoices {
  final List<StaffChoice> waiters;
  final List<StaffChoice> cashiers;

  const StaffChoices({required this.waiters, required this.cashiers});

  static Future<StaffChoices> load(
      AppDatabase db, AppLocalizations l10n) async {
    final waiterRows = await db.select(db.waiters).get();
    final userRows = await db.select(db.users).get();
    return StaffChoices(
      waiters: [
        (id: null, name: l10n.translate('all_waiters')),
        for (final w in waiterRows)
          (id: w.id, name: '${w.firstName} ${w.lastName ?? ''}'.trim()),
      ],
      cashiers: [
        (id: null, name: l10n.translate('all_cashiers')),
        for (final u in userRows)
          (
            id: u.id,
            name: '${u.firstName} ${u.lastName}'.trim().isEmpty
                ? u.username
                : '${u.firstName} ${u.lastName}'.trim()
          ),
      ],
    );
  }
}

/// The tick boxes for [ReportDocuments], with the two staff pickers.
///
/// Mutates the [documents] it is given and calls [onChanged] so the host can
/// rebuild and persist — the hosts are `StatefulBuilder`s with their own
/// remembered settings, and handing each one an immutable copy to thread back
/// would be more ceremony than the screen is worth.
class ReportDocumentsPicker extends StatelessWidget {
  final ReportDocuments documents;
  final StaffChoices staff;
  final bool enabled;

  /// Called after any change, with the setting that should be remembered (or
  /// null for the staff pickers, which are a per-print choice).
  final void Function(void Function(SettingsNotifier) persist) onChanged;

  const ReportDocumentsPicker({
    super.key,
    required this.documents,
    required this.staff,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    Widget check({
      required bool value,
      required String title,
      String? subtitle,
      required void Function(bool) set,
      double indent = 0,
      bool? enabledOverride,
    }) {
      final on = enabledOverride ?? enabled;
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: value,
          onChanged: on ? (v) => set(v ?? false) : null,
          title: Text(
            title,
            style: TextStyle(
              color: on ? null : scheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: const TextStyle(fontSize: 11)),
        ),
      );
    }

    Widget picker({
      required String label,
      required List<StaffChoice> choices,
      required int? value,
      required bool on,
      required void Function(int?) set,
    }) {
      final selected = choices.firstWhere((c) => c.id == value,
          orElse: () => choices.first);
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 0, 8),
        child: DropdownButtonFormField<StaffChoice>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            enabled: on,
          ),
          items: [
            for (final c in choices)
              DropdownMenuItem(
                value: c,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: on ? (v) => set(v?.id) : null,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        check(
          value: documents.orders,
          title: l10n.translate('print_orders_list'),
          set: (v) => onChanged((s) {
            documents.orders = v;
            s.setPrintOrdersListOnClose(v);
          }),
        ),
        check(
          value: documents.products,
          title: l10n.translate('print_product_summary'),
          set: (v) => onChanged((s) {
            documents.products = v;
            s.setPrintProductSummaryOnClose(v);
          }),
        ),
        // Shapes the products ticket rather than adding one, so it sits under
        // it and greys out with it instead of reading as a fourth document.
        check(
          indent: 32,
          enabledOverride: enabled && documents.products,
          value: documents.byCategory,
          title: l10n.translate('group_by_category'),
          set: (v) => onChanged((s) {
            documents.byCategory = v;
            s.setPrintProductsByCategoryOnClose(v);
          }),
        ),
        check(
          value: documents.unpaid,
          title: l10n.translate('print_unpaid_orders'),
          subtitle: l10n.translate('outstanding_at_print'),
          set: (v) => onChanged((s) {
            documents.unpaid = v;
            s.setPrintUnpaidOnClose(v);
          }),
        ),
        check(
          value: documents.discounts,
          title: l10n.translate('print_discounted_orders'),
          subtitle: l10n.translate('print_discounted_orders_hint'),
          set: (v) => onChanged((s) {
            documents.discounts = v;
            s.setPrintDiscountsOnClose(v);
          }),
        ),
        check(
          value: documents.byWaiter,
          title: l10n.translate('sales_by_waiter'),
          set: (v) => onChanged((s) {
            documents.byWaiter = v;
            s.setPrintSalesByWaiterOnClose(v);
          }),
        ),
        picker(
          label: l10n.translate('waiter'),
          choices: staff.waiters,
          value: documents.waiterId,
          on: enabled && documents.byWaiter,
          set: (v) => onChanged((_) => documents.waiterId = v),
        ),
        check(
          value: documents.byCashier,
          title: l10n.translate('sales_by_cashier'),
          set: (v) => onChanged((s) {
            documents.byCashier = v;
            s.setPrintSalesByCashierOnClose(v);
          }),
        ),
        picker(
          label: l10n.translate('cashier'),
          choices: staff.cashiers,
          value: documents.cashierId,
          on: enabled && documents.byCashier,
          set: (v) => onChanged((_) => documents.cashierId = v),
        ),
      ],
    );
  }
}

/// How a run of documents went — what was attempted and what actually came
/// out, so a caller can tell "all printed" from "the printer quit after two".
typedef PrintRun = ({int printed, int attempted});

/// Print every ticked document for one scope.
///
/// Each prints separately with its own cut, and each failure is isolated: one
/// dead document must not swallow the rest, and the caller is told what
/// actually came out rather than being handed a bare success.
///
/// [scopeLabel] heads each ticket — a session code on close, a day on the Z.
/// The unpaid sheet ignores the scope on purpose: an unpaid table is unpaid
/// NOW, whatever period is being reported on, and the sheet says so.
Future<PrintRun> printReportDocuments({
  required WidgetRef ref,
  required ReportDocuments documents,
  required List<int> sessionIds,
  required String scopeLabel,
  required AppLocalizations l10n,
  List<String> sessionCodes = const [],
  String? zCode,
  int? zNumber,
}) async {
  final db = ref.read(databaseProvider);
  final printing = ref.read(printingServiceProvider);
  final summaries = DailySummaryService(db);
  final businessName =
      ref.read(sharedPreferencesProvider).getString('business_name');

  var printed = 0;
  var attempted = 0;

  Future<void> run(String what, Future<bool> Function() job) async {
    attempted++;
    try {
      if (await job()) printed++;
    } catch (e) {
      Logger.instance.error('Report document "$what" failed: $e');
    }
  }

  if (documents.orders) {
    await run('orders', () async {
      final r = await summaries.generateOrdersList(
        sessionIds: sessionIds,
        scopeLabel: scopeLabel,
        sessionCodes: sessionCodes,
        zCode: zCode,
        zNumber: zNumber,
      );
      return printing.printOrdersList(report: r, businessName: businessName);
    });
  }

  if (documents.products) {
    await run('products', () async {
      final r = await summaries.generateProductsSummary(
        sessionIds: sessionIds,
        scopeLabel: scopeLabel,
        sessionCodes: sessionCodes,
        zCode: zCode,
        zNumber: zNumber,
      );
      return printing.printProductsSummary(
        report: r,
        businessName: businessName,
        groupByCategory: documents.byCategory,
      );
    });
  }

  if (documents.unpaid) {
    await run('unpaid', () async {
      final summary = await UnpaidOrdersService(db).summary();
      return printing.printUnpaidOrders(
          summary: summary, businessName: businessName);
    });
  }

  if (documents.discounts) {
    await run('discounts', () async {
      final r = await summaries.generateOrdersList(
        sessionIds: sessionIds,
        scopeLabel: scopeLabel,
        sessionCodes: sessionCodes,
        zCode: zCode,
        zNumber: zNumber,
        discountedOnly: true,
      );
      return printing.printOrdersList(report: r, businessName: businessName);
    });
  }

  Future<void> staffTicket(StaffGrouping grouping, int? onlyStaffId) =>
      run('staff:$grouping', () async {
        final r = await summaries.generateStaffSales(
          sessionIds: sessionIds,
          scopeLabel: scopeLabel,
          grouping: grouping,
          onlyStaffId: onlyStaffId,
          unassignedLabel: l10n.translate('unassigned'),
          sessionCodes: sessionCodes,
          zCode: zCode,
          zNumber: zNumber,
        );
        return printing.printStaffSales(
            report: r, businessName: businessName);
      });

  if (documents.byWaiter) {
    await staffTicket(StaffGrouping.waiter, documents.waiterId);
  }
  if (documents.byCashier) {
    await staffTicket(StaffGrouping.cashier, documents.cashierId);
  }

  return (printed: printed, attempted: attempted);
}
