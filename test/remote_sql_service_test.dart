import 'dart:io';

import 'package:caisse212/services/remote_sql_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('remote_sql');
    path = '${dir.path}${Platform.pathSeparator}t.db';
    final db = sqlite3.open(path);
    db.execute('CREATE TABLE orders (id INTEGER PRIMARY KEY, code TEXT, pic BLOB)');
    db.execute('BEGIN');
    final ins = db.prepare('INSERT INTO orders (code, pic) VALUES (?, ?)');
    for (var i = 0; i < 1500; i++) {
      ins.execute(['A$i', i == 0 ? [1, 2, 3] : null]);
    }
    ins.dispose();
    db.execute('COMMIT');
    db.dispose();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, dynamic>> run(String sql,
          {List<Object?> params = const [], int? maxRows, int? timeoutMs}) =>
      RemoteSqlService.run(
          path: path,
          sql: sql,
          params: params,
          maxRows: maxRows,
          timeoutMs: timeoutMs,
          schemaVersion: 66);

  group('validate', () {
    test('accepts reads', () {
      for (final sql in [
        'SELECT 1',
        'select * from orders;',
        'WITH x AS (SELECT 1) SELECT * FROM x',
        'EXPLAIN QUERY PLAN SELECT * FROM orders',
        'PRAGMA table_info(orders)',
        'pragma user_version',
      ]) {
        expect(RemoteSqlService.validate(sql), isNull, reason: sql);
      }
    });

    test('refuses writes and setters', () {
      for (final sql in [
        'DELETE FROM orders',
        'UPDATE orders SET code = 1',
        'SELECT 1; DELETE FROM orders',
        'PRAGMA journal_mode = WAL',
        'PRAGMA journal_mode(WAL)',
        'PRAGMA writable_schema',
        'ATTACH DATABASE "x" AS y',
        '/* hi */ SELECT 1',
        '',
      ]) {
        expect(RemoteSqlService.validate(sql), isNotNull, reason: sql);
      }
    });
  });

  test('returns columns and rows, blobs described', () async {
    final r = await run('SELECT id, code, pic FROM orders WHERE id <= ? ORDER BY id',
        params: [2]);
    expect(r['columns'], ['id', 'code', 'pic']);
    expect(r['rows'], [
      [1, 'A0', '<blob 3 bytes>'],
      [2, 'A1', null],
    ]);
    expect(r['rowCount'], 2);
    expect(r['truncated'], false);
    expect(r['schemaVersion'], 66);
  });

  test('integers past 2^53 travel as strings', () async {
    final r = await run('SELECT 9007199254740993, 42');
    expect(r['rows'], [
      ['9007199254740993', 42]
    ]);
  });

  test('caps rows at the default and the hard cap', () async {
    final d = await run('SELECT id FROM orders');
    expect(d['rowCount'], 200);
    expect(d['truncated'], true);
    final c = await run('SELECT id FROM orders', maxRows: 5000);
    expect(c['rowCount'], 1000);
    expect(c['truncated'], true);
  });

  test('a write hidden in a CTE is refused by sqlite', () async {
    await expectLater(
        run('WITH x AS (SELECT 1) DELETE FROM orders'),
        throwsA(isA<RemoteSqlException>()));
    final r = await run('SELECT count(*) FROM orders');
    expect(r['rows'], [
      [1500]
    ]);
  });

  test('a runaway query is interrupted at the timeout', () async {
    final sw = Stopwatch()..start();
    await expectLater(
      run('WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n) '
          'SELECT count(*) FROM n',
          timeoutMs: 300),
      throwsA(isA<RemoteSqlException>()
          .having((e) => e.message, 'message', contains('timeout'))),
    );
    expect(sw.elapsedMilliseconds, lessThan(2500));
  });

  test('a reader does not stop the live connection writing', () async {
    final writer = sqlite3.open(path);
    writer.execute('PRAGMA busy_timeout = 3000');
    final read = run('SELECT id FROM orders');
    writer.execute("INSERT INTO orders (code) VALUES ('new')");
    await read;
    writer.dispose();
  });
}
