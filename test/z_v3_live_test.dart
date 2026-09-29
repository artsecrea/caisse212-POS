import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/business_day_config.dart';
import 'package:caisse212/domain/models/session_rules.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/cash_movement_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/z_rules.dart';
import 'package:caisse212/services/z_service.dart';

/// Z contract v3 against a REAL backend, with this till's own credentials.
///
/// Opt-in: runs only with `Z_LIVE=1` (it writes sessions to the server). Reads
/// the installed POS's SharedPreferences for base URL, token and X-POS-Name,
/// so it speaks as that terminal (`Z_LIVE_POS=name` to speak as another).
/// `Z_LIVE_WRITE=1` also runs the write flow.
void main() {
  final live = Platform.environment['Z_LIVE'] == '1';
  final write = Platform.environment['Z_LIVE_WRITE'] == '1';

  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  late ApiService api;
  late AppDatabase db;
  late DataSyncService sync;

  setUpAll(() async {
    if (!live) return;
    final path =
        '${Platform.environment['APPDATA']}\\artecrea\\CAISSE212\\shared_preferences.json';
    final raw = jsonDecode(await File(path).readAsString()) as Map;
    final values = <String, Object>{};
    raw.forEach((k, v) {
      final key = k.toString();
      if (!key.startsWith('flutter.') || v == null) return;
      if (v is List) {
        values[key.substring(8)] = v.map((e) => '$e').toList();
      } else {
        values[key.substring(8)] = v as Object;
      }
    });
    // Speak as another terminal of the same tenant (e.g. a test terminal).
    final posName = Platform.environment['Z_LIVE_POS'];
    if (posName != null && posName.isNotEmpty) values['pos_name'] = posName;
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    api = ApiService(prefs);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = DataSyncService(db, api, prefs);
  });

  void log(String label, Object? v) =>
      // ignore: avoid_print
      print('LIVE $label: ${v is Map || v is List ? jsonEncode(v) : v}');

  test('read: identity, session-rules, z/current', () async {
    final identity = await api.fetchPosIdentity();
    log('identity', identity);
    final rules = await api.fetchSessionRules();
    log('session-rules', rules);
    final current = await api.fetchCurrentZ();
    log('z/current', current);

    expect(identity, isNotNull);
    final day = BusinessDayConfig.fromJson(identity!);
    log('local zDay', zDayKeyOf(DateTime.now(), day.startHour));
    if (rules != null) log('parsed rules', SessionRules.fromJson(rules).toJson());
    expect(current, isNotNull, reason: '/pos/z/current must answer');
    expect(current!.containsKey('currentZDay'), isTrue);
  }, skip: !live);

  test('write: open Z, push session + movement, close Z', () async {
    final identity = (await api.fetchPosIdentity())!;
    final startHour = BusinessDayConfig.fromJson(identity).startHour;
    final before = (await api.fetchCurrentZ())!;
    final currentZDay = before['currentZDay'].toString().substring(0, 10);
    final plan = planZ(
        currentZDay: currentZDay, server: ZSnapshot.fromServer(before));
    log('plan', '$plan (local day ${zDayKeyOf(DateTime.now(), startHour)})');

    final zService = ZService(db);
    final sessions = SessionService(db);
    final z = await zService.openZ(
      label: plan.next,
      createdBy: 1,
      openMode: plan.action == ZPlanAction.adoptServer ? null : 'AUTO',
    );
    final s = await sessions.startSession(
        cashierId: 1, moneyAtStart: 100, moneyEntered: 100);
    await zService.attachSession(s.id, z.id);

    // Opening push, exactly as the login does.
    expect(await sync.syncSingleSession(s.id), isTrue,
        reason: 'opening session push');
    final opened = (await api.fetchCurrentZ())!;
    log('z/current after open', opened);

    await CashMovementService(db).record(
      direction: CashMovementService.directionOut,
      amount: 12.5,
      reason: 'live test Z v3',
      reference: 'LIVE-1',
      sessionId: s.id,
      zDay: parseZDay(plan.next.zDay),
      createdBy: 1,
    );
    expect(await sync.syncCashMovementsBulk(), 1, reason: 'movement push');

    await sessions.endSession(sessionId: s.id, countedCash: 87.5);
    await zService.closeZ(
        zId: z.id,
        closeMode: ZService.closeManual,
        sessionService: sessions,
        endedBy: 1);
    final pushed = await sync.getSessionsForSync();
    log('closing payload', pushed);
    expect(await sync.syncSessionsBulk(), 1, reason: 'closing session push');

    final after = (await api.fetchCurrentZ())!;
    log('z/current after close', after);
    expect(after['zDay'].toString().substring(0, 10), plan.next.zDay);
    expect(after['zSeq'], plan.next.zSeq);
    expect(after['closed'], isTrue);
    expect(after['closeMode'], 'MANUAL');
  }, skip: !(live && write));
}
