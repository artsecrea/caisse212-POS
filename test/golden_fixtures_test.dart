import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'golden/golden_functions.dart';

/// The golden fixtures: JSON cases the till's rules must answer exactly, and
/// that the Go hub's tests will run unchanged (test/golden/README.md).
///
/// `GOLDEN_UPDATE=1 flutter test test/golden_fixtures_test.dart` rewrites
/// every `expected` from the current Dart code. Only do that for a rule change
/// that was decided, and read the diff: it is the change the hub has to copy.
void main() {
  final update = Platform.environment['GOLDEN_UPDATE'] == '1';
  final files = Directory('test/golden/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are fixtures to run', () => expect(files, isNotEmpty));

  for (final file in files) {
    final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final cases = (doc['cases'] as List).cast<Map<String, dynamic>>();

    group(file.uri.pathSegments.last, () {
      test('case names are unique', () {
        final names = cases.map((c) => c['name']).toList();
        expect(names.toSet().length, names.length);
      });

      for (final c in cases) {
        test(c['name'] as String, () {
          final fn = goldenFunctions[c['fn']];
          expect(fn, isNotNull, reason: 'unknown fn ${c['fn']}');
          final actual = _normalise(fn!(c['input'] as Map<String, dynamic>))
              as Map<String, dynamic>;
          if (update) {
            c['expected'] = actual;
            return;
          }
          expect(c.containsKey('expected'), isTrue,
              reason: 'no expected yet: run with GOLDEN_UPDATE=1');
          final problems = <String>[];
          _compare(c['expected'], actual, r'$', problems);
          expect(problems, isEmpty, reason: problems.join('\n'));

          if (c['fn'] == 'orderMoney') {
            // The waiter API and the till's cart must quote the same total.
            final w = actual['waiterApi'] as Map;
            final t = actual['till'] as Map;
            expect(w['totalAmount'],
                closeTo(((t['total'] as num) * 100).roundToDouble() / 100, 1e-9));
          }
        });
      }

      if (update) {
        tearDownAll(() {
          file.writeAsStringSync(
              '${const JsonEncoder.withIndent('  ').convert(doc)}\n');
        });
      }
    });
  }
}

/// Numbers to 6 decimals, so a fixture reads 25.92 and not 25.919999999999998.
/// The comparison allows 1e-6, far below a cent.
Object? _normalise(Object? v) {
  if (v is double) return double.parse(v.toStringAsFixed(6));
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _normalise(e.value)};
  }
  if (v is List) return [for (final x in v) _normalise(x)];
  return v;
}

void _compare(Object? want, Object? got, String path, List<String> out) {
  if (want is num && got is num) {
    if ((want - got).abs() > 1e-6) out.add('$path: want $want, got $got');
    return;
  }
  if (want is Map && got is Map) {
    for (final k in {...want.keys, ...got.keys}) {
      if (!want.containsKey(k)) {
        out.add('$path.$k: not expected, got ${got[k]}');
      } else if (!got.containsKey(k)) {
        out.add('$path.$k: missing, want ${want[k]}');
      } else {
        _compare(want[k], got[k], '$path.$k', out);
      }
    }
    return;
  }
  if (want is List && got is List) {
    if (want.length != got.length) {
      out.add('$path: want ${want.length} items $want, got ${got.length} $got');
      return;
    }
    for (var n = 0; n < want.length; n++) {
      _compare(want[n], got[n], '$path[$n]', out);
    }
    return;
  }
  if (want != got) out.add('$path: want $want, got $got');
}
