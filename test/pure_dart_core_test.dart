import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The shared core (money, rules, schema, settlement) must load without
/// Flutter, or a hub cannot reuse it. `dart run` refuses anything that
/// reaches `dart:ui`, so a Flutter import slipping into one of these files
/// fails here instead of on the day the hub is built.
void main() {
  test('the shared core loads with plain dart', () async {
    final result = await Process.run(
      'dart',
      ['run', 'tool/pure_dart_core.dart'],
      runInShell: true,
    );
    expect(result.exitCode, 0,
        reason: '${result.stdout}\n${result.stderr}'.trim());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
