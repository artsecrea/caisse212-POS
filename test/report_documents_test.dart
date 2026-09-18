import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/app_settings.dart';
import 'package:caisse212/presentation/widgets/report_documents.dart';

/// The session-close dialog and the Z dialog offer the same set of end-of-
/// shift documents. One definition, two hosts — these pin what the shared
/// selection means so a change in one place cannot quietly alter the other.

void main() {
  group('seeded from the remembered ticks', () {
    test('a shop that always wants a document ticks it once', () {
      const s = AppSettings(
        printOrdersListOnClose: true,
        printProductSummaryOnClose: true,
        printUnpaidOnClose: true,
        printSalesByWaiterOnClose: true,
        printSalesByCashierOnClose: true,
      );
      final d = ReportDocuments.fromSettings(s);
      expect(d.orders, isTrue);
      expect(d.products, isTrue);
      expect(d.unpaid, isTrue);
      expect(d.byWaiter, isTrue);
      expect(d.byCashier, isTrue);
    });

    test('the defaults add no paper nobody asked for', () {
      const s = AppSettings();
      final d = ReportDocuments.fromSettings(s);
      expect(d.orders, isFalse);
      expect(d.products, isFalse);
      expect(d.unpaid, isFalse);
      expect(d.byWaiter, isFalse);
      expect(d.byCashier, isFalse);
      expect(d.anySelected, isFalse);
    });

    test('grouping products by category is on by default', () {
      // It shapes the products ticket rather than adding one, so defaulting it
      // on costs nothing when the ticket itself is off.
      expect(ReportDocuments.fromSettings(const AppSettings()).byCategory,
          isTrue);
    });

    test('staff pickers start at everyone', () {
      final d = ReportDocuments.fromSettings(const AppSettings());
      expect(d.waiterId, isNull);
      expect(d.cashierId, isNull);
    });
  });

  group('anySelected — what enables the print button', () {
    test('any one document is enough', () {
      expect(ReportDocuments(orders: true).anySelected, isTrue);
      expect(ReportDocuments(products: true).anySelected, isTrue);
      expect(ReportDocuments(unpaid: true).anySelected, isTrue);
      expect(ReportDocuments(byWaiter: true).anySelected, isTrue);
      expect(ReportDocuments(byCashier: true).anySelected, isTrue);
    });

    test('grouping alone is not a document', () {
      // byCategory only shapes the products ticket; on its own it would print
      // nothing and report success.
      expect(ReportDocuments(byCategory: true).anySelected, isFalse);
    });

    test('a staff pick alone is not a document either', () {
      expect(ReportDocuments(waiterId: 3, cashierId: 4).anySelected, isFalse);
    });
  });
}
