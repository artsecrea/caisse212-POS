import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The screens reach business data only through the service interfaces in
/// lib/domain/services, so a hub-linked till can swap every one of them by
/// overriding its provider. This pins that: a screen reading the database,
/// or a provider typed by a concrete local class, fails here.
void main() {
  final screens = [
    for (final dir in ['lib/presentation', 'lib/utils'])
      ...Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
  ];
  String rel(File f) => f.path.replaceAll(r'\', '/');

  final interfaces = <String>{
    for (final f in Directory('lib/domain/services')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')))
      ...RegExp(r'abstract interface class (\w+)')
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(1)!),
  };

  // Every provider declared in lib, with its type and its body.
  final providers = <String, ({String type, String body, String file})>{};
  final decl = RegExp(
      r'^final (\w+Provider)\s*=\s*([\w.]+)\s*(?:<(.*?)>)?\s*\(',
      multiLine: true);
  for (final f in Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final s = f.readAsStringSync();
    for (final m in decl.allMatches(s)) {
      final end = s.indexOf(RegExp(r'^\}\);|\);$', multiLine: true), m.end);
      providers[m.group(1)!] = (
        type: '${m.group(2)}<${m.group(3) ?? ''}>',
        body: s.substring(m.end, end < 0 ? s.length : end),
        file: rel(f),
      );
    }
  }

  Set<String> providersUsedBy(File f) => {
        for (final m
            in RegExp(r'\b(\w+Provider)\b').allMatches(f.readAsStringSync()))
          if (providers.containsKey(m.group(1))) m.group(1)!,
      };

  // The class a plain `Provider<T>` provides, or null for any other kind.
  String? providedClass(String type) =>
      RegExp(r'^Provider(?:\.\w+)*<(\w+)').firstMatch(type)?.group(1);

  test('no screen reads the database or builds a local service', () {
    final offenders = <String>[];
    for (final f in screens) {
      final s = f.readAsStringSync();
      if (s.contains('databaseProvider')) {
        offenders.add('${rel(f)}: databaseProvider');
      }
      for (final m in RegExp(r"import 'package:drift/drift\.dart'([^;]*);")
          .allMatches(s)) {
        if (m.group(1)!.trim() != 'show Value') {
          offenders.add('${rel(f)}: imports drift beyond Value');
        }
      }
      for (final m
          in RegExp(r'\b(\w+Repository|Local\w+Service)\(').allMatches(s)) {
        offenders.add('${rel(f)}: builds ${m.group(1)}');
      }
    }
    expect(offenders, isEmpty);
  });

  // Providers of the till itself — its printer, settings, network, LAN
  // devices, updater — and values computed from other providers. A hub
  // changes none of them.
  const deviceLocal = {
    'ApiService', 'PrintingService', 'BarcodeScannerService', 'DateTime',
    'SharedPreferences', 'Set', 'bool', 'int', 'String', 'Map',
    'ServerService', 'CategoryDisplayMode', 'SseService', 'PosCommandHandler',
    'UpdateService', 'CustomerDisplayService', 'KdsPresenceRegistry',
    'LanNotificationHub', 'NetworkWatchService', 'PermissionService',
    'RemoteAccessReporter', 'SoundService', 'WaiterCallService',
    'WaiterKitchenEventService', 'CurrencyFormatter', 'Future', 'AsyncValue',
  };

  test('every service a screen reads is typed by an interface', () {
    final offenders = <String>{};
    for (final f in screens) {
      for (final p in providersUsedBy(f)) {
        final d = providers[p]!;
        final t = providedClass(d.type);
        if (t == null || interfaces.contains(t) || deviceLocal.contains(t)) {
          continue;
        }
        offenders.add('${rel(f)} reads $p (${d.type})');
      }
    }
    expect(offenders, isEmpty);
  });

  // A provider typed by an interface builds its local implementation on the
  // database: that is the swap point. Every other provider a screen reads —
  // streams, futures, notifiers, values — must get its data through one.
  test('no provider a screen watches queries the database itself', () {
    final offenders = <String>{};
    for (final f in screens) {
      for (final p in providersUsedBy(f)) {
        final d = providers[p]!;
        if (interfaces.contains(providedClass(d.type))) continue;
        if (d.body.contains('databaseProvider')) {
          offenders.add('$p (${d.file}) reads databaseProvider');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
