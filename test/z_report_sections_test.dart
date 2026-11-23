import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/z_report_sections.dart';
import 'package:caisse212/services/daily_summary_service.dart';
import 'package:caisse212/services/printing_service.dart';

/// An admin can switch bands off the X / Z ticket; what is left must still be
/// numbered 1..n with no gap where the hidden band used to be.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PrintingService service;
  final captured = <int>[];

  Future<String> printZ(List<String> hidden) async {
    SharedPreferences.setMockInitialValues(
        {kZReportHiddenSectionsKey: hidden});
    await service.saveConfig(
        await SharedPreferences.getInstance(), const PrinterConfig());
    final now = DateTime.now();
    final report = await DailySummaryService(db).generateReport(
      startDate: now.subtract(const Duration(hours: 8)),
      endDate: now,
      sessionIds: const [],
    );
    captured.clear();
    final ok = await service.printDailySummaryReport(
        report: report, reportType: 'Z');
    expect(ok, isTrue);
    return String.fromCharCodes(captured);
  }

  setUp(() {
    service = PrintingService();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service.dispatchForTesting = (_, bytes) => captured.addAll(bytes);
    service.databaseForTesting = db;
  });
  tearDown(() async {
    service.dispatchForTesting = null;
    service.databaseForTesting = null;
    await db.close();
  });

  test('every band prints by default', () async {
    final out = await printZ(const []);
    // Annulments and outstanding only print when non-empty, so an empty day
    // carries the eight unconditional bands.
    expect(out, contains('8) '));
    expect(out, isNot(contains('9) ')));
  });

  test('hidden bands are left out and the rest renumber', () async {
    final out = await printZ([
      ZReportSection.families.name,
      ZReportSection.topArticles.name,
    ]);
    expect(out, contains('6) '));
    expect(out, isNot(contains('7) ')));
  });

  test('an unknown hidden name is ignored', () async {
    final out = await printZ(const ['noSuchBand']);
    expect(out, contains('8) '));
  });

  Future<String> printReport(String type, Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await service.saveConfig(await SharedPreferences.getInstance(),
        const PrinterConfig(printingLanguage: 'en'));
    final now = DateTime.now();
    final report = await DailySummaryService(db).generateReport(
      startDate: now.subtract(const Duration(hours: 8)),
      endDate: now,
      sessionIds: const [],
    );
    captured.clear();
    final ok =
        await service.printDailySummaryReport(report: report, reportType: type);
    expect(ok, isTrue);
    return String.fromCharCodes(captured);
  }

  final briefHidden = [
    for (final b in ZReportSection.values)
      if (!kBriefXSections.contains(b)) b.name,
  ];

  test('the X follows the Z bands until it has its own', () async {
    final out = await printReport('X', {kZReportHiddenSectionsKey: briefHidden});
    expect(out, contains('3) '));
    expect(out, isNot(contains('4) ')));
  });

  test('the X has its own bands, leaving the Z alone', () async {
    final prefs = <String, Object>{kXReportHiddenSectionsKey: briefHidden};
    final x = await printReport('X', prefs);
    expect(x, contains('3) '));
    expect(x, isNot(contains('4) ')));
    final z = await printReport('Z', prefs);
    expect(z, contains('8) '));
  });

  test('skip-zero drops zero lines but keeps the totals', () async {
    final full = await printReport('X', const {});
    expect(full, contains('Gross sales'));
    expect(full, contains('Opening float'));

    final brief = await printReport('X', {kXReportSkipZeroKey: true});
    expect(brief, isNot(contains('Gross sales')));
    expect(brief, isNot(contains('Opening float')));
    expect(brief, contains('TOTAL NET'));
    expect(brief, contains('TOTAL PAYMENTS'));
    expect(brief.length, lessThan(full.length));

    // The Z has its own switch.
    final z = await printReport('Z', {kXReportSkipZeroKey: true});
    expect(z, contains('Gross sales'));
  });

  test('the tag band prints only once switched on', () async {
    final off = await printReport('Z', const {});
    expect(off, isNot(contains('SUMMARY BY TAG')));

    final on = await printReport('Z', {
      kZReportHiddenSectionsKey: [ZReportSection.byTag.optInShownToken],
    });
    expect(on, contains('SUMMARY BY TAG'));
    expect(on, contains('Tagged orders'));
    expect(on, contains('9) '));
  });

  test('the tag band is off on the X too, and has its own X tick', () async {
    expect(await printReport('X', const {}),
        isNot(contains('SUMMARY BY TAG')));

    final prefs = <String, Object>{
      kXReportHiddenSectionsKey: [ZReportSection.byTag.optInShownToken],
    };
    expect(await printReport('X', prefs), contains('SUMMARY BY TAG'));
    expect(await printReport('Z', prefs), isNot(contains('SUMMARY BY TAG')));
  });
}
