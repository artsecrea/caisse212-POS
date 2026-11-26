import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/z_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> session(String status) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S-$status',
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(status),
          ));

  Future<void> z(String status) => db.into(db.zs).insert(ZsCompanion.insert(
        code: 'Z-$status',
        createdBy: 1,
        status: Value(status),
      ));

  test('nothing open: the Z report is allowed', () async {
    await session('ended');
    await z('closed');
    expect(await ZService(db).reportBlockedByOpenShift(), isFalse);
  });

  test('an open Z blocks it', () async {
    await z('open');
    expect(await ZService(db).reportBlockedByOpenShift(), isTrue);
  });

  test('a running session blocks it, even with every Z closed', () async {
    await z('closed');
    await session('active');
    expect(await ZService(db).reportBlockedByOpenShift(), isTrue);
  });

  test('a paused session blocks it', () async {
    await session('paused');
    expect(await ZService(db).reportBlockedByOpenShift(), isTrue);
  });
}
