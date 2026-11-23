import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:loggecrea/loggecrea.dart';
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart';

/// Raised for a query the till refuses or could not finish. The message goes
/// back to the back office as the reply's `error`.
class RemoteSqlException implements Exception {
  final String message;
  RemoteSqlException(this.message);
  @override
  String toString() => message;
}

typedef _InterruptNative = Void Function(Pointer<Void>);
typedef _InterruptDart = void Function(Pointer<Void>);

/// Runs one read-only query for the remote console.
///
/// Three locks keep it from writing, any one of which is enough: the text must
/// be a single SELECT / WITH / EXPLAIN / read PRAGMA, the connection is opened
/// read-only with `query_only` on, and sqlite itself must report the prepared
/// statement as read-only.
///
/// The query runs in its own isolate so a slow one never stalls the till's UI,
/// and on its own connection so it never queues behind (or ahead of) the
/// cashier's writes on drift's.
class RemoteSqlService {
  static const defaultMaxRows = 200;
  static const maxRowsCap = 1000;
  static const defaultTimeoutMs = 5000;
  static const timeoutCapMs = 10000;

  /// Under the back office's ~1 MB reply limit, leaving room for the envelope.
  static const maxRowBytes = 900 * 1024;

  // Only these may follow PRAGMA. The ones in [_pragmasWithArg] take an
  // argument; on the rest an argument is the SETTER form
  // (`journal_mode(WAL)`), so none is allowed.
  static const _pragmas = {
    'table_info', 'table_xinfo', 'table_list', 'index_list', 'index_info',
    'index_xinfo', 'foreign_key_list', 'foreign_key_check', 'integrity_check',
    'quick_check', 'user_version', 'schema_version', 'page_count',
    'page_size', 'freelist_count', 'database_list', 'compile_options',
    'journal_mode', 'encoding', 'collation_list', 'function_list',
  };
  static const _pragmasWithArg = {
    'table_info', 'table_xinfo', 'table_list', 'index_list', 'index_info',
    'index_xinfo', 'foreign_key_list', 'foreign_key_check', 'integrity_check',
    'quick_check',
  };

  /// Why [sql] is refused, or null when it may run.
  static String? validate(String sql) {
    var s = sql.trim();
    while (s.endsWith(';')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    if (s.isEmpty) return 'empty query';
    if (s.contains(';')) return 'only one statement is allowed';
    final head = RegExp(r'^[A-Za-z]+').stringMatch(s)?.toUpperCase();
    switch (head) {
      case 'SELECT':
      case 'WITH':
      case 'EXPLAIN':
        return null;
      case 'PRAGMA':
        if (s.contains('=')) return 'PRAGMA assignments are not allowed';
        final m = RegExp(
                r'^PRAGMA\s+(?:main\.)?([A-Za-z_]+)\s*(\([^()]*\))?$',
                caseSensitive: false)
            .firstMatch(s);
        if (m == null) return 'unsupported PRAGMA form';
        final name = m.group(1)!.toLowerCase();
        if (!_pragmas.contains(name)) return 'PRAGMA $name is not allowed';
        if (m.group(2) != null && !_pragmasWithArg.contains(name)) {
          return 'PRAGMA $name takes no argument here';
        }
        return null;
      default:
        return 'only SELECT, WITH, EXPLAIN or a read PRAGMA is allowed';
    }
  }

  /// Runs [sql] against the database file at [path]. Throws
  /// [RemoteSqlException] when refused, failed or timed out.
  static Future<Map<String, dynamic>> run({
    required String path,
    required String sql,
    List<Object?> params = const [],
    int? maxRows,
    int? timeoutMs,
    required int schemaVersion,
  }) async {
    final refused = validate(sql);
    if (refused != null) throw RemoteSqlException(refused);
    for (final p in params) {
      if (p != null && p is! num && p is! String && p is! bool) {
        throw RemoteSqlException('params must be JSON primitives');
      }
    }
    final rowsLimit = (maxRows ?? defaultMaxRows).clamp(1, maxRowsCap);
    final timeout = (timeoutMs ?? defaultTimeoutMs).clamp(100, timeoutCapMs);

    final port = ReceivePort();
    final done = Completer<Map<String, dynamic>>();
    int? handle;
    SendPort? control;
    var interrupted = false;
    Timer? interruptTimer;
    Timer? killTimer;
    Isolate? isolate;

    void finish({Map<String, dynamic>? data, String? error}) {
      if (done.isCompleted) return;
      interruptTimer?.cancel();
      killTimer?.cancel();
      // The worker keeps its connection open until told, so an interrupt
      // racing the result never touches a closed handle.
      control?.send('close');
      port.close();
      if (error != null) {
        done.completeError(RemoteSqlException(error));
      } else {
        done.complete(data!);
      }
    }

    port.listen((msg) {
      if (msg is Map) {
        switch (msg['t']) {
          case 'open':
            control = msg['control'] as SendPort;
            handle = msg['handle'] as int;
          case 'ok':
            finish(data: {
              'columns': msg['columns'],
              'rows': msg['rows'],
              'rowCount': (msg['rows'] as List).length,
              'truncated': msg['truncated'],
              'schemaVersion': schemaVersion,
              'durationMs': msg['durationMs'],
            });
          case 'error':
            finish(
                error: interrupted
                    ? 'timeout after ${timeout}ms'
                    : msg['message'] as String);
        }
      } else if (msg is List) {
        finish(error: 'query worker failed: ${msg.first}');
      } else if (msg == null) {
        finish(error: 'query worker exited');
      }
    });

    try {
      isolate = await Isolate.spawn(
        _worker,
        [port.sendPort, path, sql, params, rowsLimit, timeout, maxRowBytes],
        onError: port.sendPort,
        onExit: port.sendPort,
      );
    } catch (e) {
      finish(error: 'could not start the query: $e');
    }

    interruptTimer = Timer(Duration(milliseconds: timeout), () {
      if (done.isCompleted) return;
      interrupted = true;
      final h = handle;
      if (h != null) _interrupt(h);
      // An interrupt lands at the next VM step; this is for one that never
      // comes back at all.
      killTimer = Timer(const Duration(seconds: 2), () {
        if (done.isCompleted) return;
        finish(error: 'timeout after ${timeout}ms');
        isolate?.kill(priority: Isolate.immediate);
      });
    });

    return done.future;
  }

  static _InterruptDart? _interruptFn;

  // sqlite3_interrupt is documented safe to call from another thread, which
  // is the only way to stop a statement that is busy inside one step.
  static void _interrupt(int address) {
    try {
      _interruptFn ??= sqlite_open.open
          .openSqlite()
          .lookupFunction<_InterruptNative, _InterruptDart>('sqlite3_interrupt');
      _interruptFn!(Pointer<Void>.fromAddress(address));
    } catch (e) {
      Logger.instance.warning('RemoteSql: interrupt failed: $e');
    }
  }

  static Object? _jsonValue(Object? v) {
    // JSON numbers lose precision past 2^53 in the browser.
    if (v is int) return v.abs() > 9007199254740991 ? v.toString() : v;
    if (v == null || v is String) return v;
    if (v is double) return v.isFinite ? v : v.toString();
    if (v is Uint8List) return '<blob ${v.length} bytes>';
    return v.toString();
  }

  static Future<void> _worker(List<Object?> args) async {
    final main = args[0] as SendPort;
    final path = args[1] as String;
    final sql = args[2] as String;
    final params = (args[3] as List).cast<Object?>();
    final maxRows = args[4] as int;
    final timeoutMs = args[5] as int;
    final maxBytes = args[6] as int;

    final control = ReceivePort();
    Database? db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
      db.execute('PRAGMA query_only = ON;');
      // Short: a reader that cannot get in during a cashier's commit gives
      // up rather than queueing behind it.
      db.execute('PRAGMA busy_timeout = 250;');
      main.send({
        't': 'open',
        'control': control.sendPort,
        'handle': db.handle.address,
      });

      final sw = Stopwatch()..start();
      final stmt = db.prepare(sql, checkNoTail: true);
      try {
        if (!stmt.isReadOnly) {
          throw RemoteSqlException('statement is not read-only');
        }
        final cursor = stmt.selectCursor(params);
        final rows = <List<Object?>>[];
        var bytes = 0;
        var truncated = false;
        while (cursor.moveNext()) {
          if (rows.length >= maxRows) {
            truncated = true;
            break;
          }
          final row = cursor.current.values.map(_jsonValue).toList();
          bytes += jsonEncode(row).length + 1;
          if (bytes > maxBytes) {
            truncated = true;
            break;
          }
          rows.add(row);
          if (sw.elapsedMilliseconds > timeoutMs) {
            throw RemoteSqlException('timeout after ${timeoutMs}ms');
          }
        }
        main.send({
          't': 'ok',
          'columns': cursor.columnNames,
          'rows': rows,
          'truncated': truncated,
          'durationMs': sw.elapsedMilliseconds,
        });
      } finally {
        stmt.dispose();
      }
    } on RemoteSqlException catch (e) {
      main.send({'t': 'error', 'message': e.message});
    } on SqliteException catch (e) {
      main.send({'t': 'error', 'message': e.message});
    } catch (e) {
      main.send({'t': 'error', 'message': '$e'});
    }

    if (db != null) {
      await control.first
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      db.dispose();
    }
    control.close();
  }
}
