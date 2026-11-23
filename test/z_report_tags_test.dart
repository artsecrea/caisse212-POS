import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/z_report_sections.dart';
import 'package:caisse212/services/cash_report_sections.dart';

/// The opt-in "by tag" band of the X / Z.
///
/// An order with several tags counts in full under each tag, so the rows may
/// add up to more than the takings; the tagged / untagged pair counts every
/// order once and must add back up to the sales.
void main() {
  late AppDatabase db;
  late CashReportBuilder builder;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = CashReportBuilder(db);
  });
  tearDown(() => db.close());

  Future<int> session() => db.into(db.cashSessions).insert(
      CashSessionsCompanion.insert(code: 'S1', cashierId: 1, moneyAtStart: 0));

  Future<void> tag(int id, String label) => db
      .into(db.orderTags)
      .insert(OrderTagsCompanion.insert(id: Value(id), label: label));

  Future<int> order(int sessionId, String code,
          {String? tagIds, String status = 'COMPLETED'}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            status: Value(status),
            sessionId: Value(sessionId),
            tagIds: Value(tagIds),
          ));

  Future<void> line(int orderId,
          {double price = 100, String state = 'PAID'}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: price,
            state: Value(state),
          ));

  test('a multi-tag order counts in full under each tag, once in the totals',
      () async {
    final s = await session();
    await tag(1, 'VIP');
    await tag(2, 'GLOVO');
    await line(await order(s, 'A', tagIds: '1,2'), price: 100);
    await line(await order(s, 'B', tagIds: '1'), price: 50);
    await line(await order(s, 'C'), price: 30);

    final t = (await builder.build(sessionIds: [s])).byTag;

    expect(t.rows.map((r) => r.label), ['VIP', 'GLOVO']);
    expect(t.rows.first.orderCount, 2);
    expect(t.rows.first.amount, 150);
    expect(t.rows.last.orderCount, 1);
    expect(t.rows.last.amount, 100);

    expect(t.taggedOrderCount, 2);
    expect(t.taggedAmount, 150);
    expect(t.untaggedOrderCount, 1);
    expect(t.untaggedAmount, 30);
    expect(t.multiTagOrderCount, 1);
  });

  test('struck lines, cancelled orders and deleted tags', () async {
    final s = await session();
    final a = await order(s, 'A', tagIds: '9');
    await line(a, price: 40);
    await line(a, price: 25, state: 'CANCELED');
    // Every line struck: sold nothing, not in the band.
    await line(await order(s, 'B', tagIds: '9'), state: 'CANCELED');
    await line(await order(s, 'C', tagIds: '9', status: 'CANCELED'));

    final t = (await builder.build(sessionIds: [s])).byTag;

    expect(t.rows.single.label, '#9');
    expect(t.rows.single.orderCount, 1);
    expect(t.rows.single.amount, 40);
    expect(t.untaggedOrderCount, 0);
  });

  group('opt-in band toggle', () {
    test('byTag is off by default, the others on', () {
      expect(zBandShown(ZReportSection.byTag, const []), isFalse);
      expect(zBandShown(ZReportSection.families, const []), isTrue);
    });

    test('switching it on and off round-trips', () {
      var stored = withZBandShown(const ['families'], ZReportSection.byTag, true);
      expect(zBandShown(ZReportSection.byTag, stored), isTrue);
      expect(zBandShown(ZReportSection.families, stored), isFalse);
      stored = withZBandShown(stored, ZReportSection.byTag, false);
      expect(zBandShown(ZReportSection.byTag, stored), isFalse);
      expect(stored, ['families']);
    });
  });
}
