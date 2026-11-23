import 'dart:convert';
import 'dart:typed_data';

import 'package:caisse212/domain/models/account_status.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/account_status_store.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/kick_store.dart';
import 'package:caisse212/services/remote_config_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers every request from [handler]; throwing from it simulates a
/// network failure.
class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions o) handler;
  _FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

Future<SharedPreferences> _terminalPrefs() async {
  SharedPreferences.setMockInitialValues({
    'server_access_token': 'a.b.c',
    'server_refresh_token': 'r.s.t',
    'api_base_url': 'https://bms.test/api',
    'pos_name': 'POS-1',
    'tenant_id': 7,
    'business_id': 3,
  });
  return SharedPreferences.getInstance();
}

void main() {
  group('force_kick', () {
    test('wipes the terminal tokens, keeps identity, records why', () async {
      final prefs = await _terminalPrefs();
      final api = ApiService(prefs);
      var forced = false;
      final sub = api.forceLogoutStream.listen((_) => forced = true);

      await api.applyKick(
          {'code': 'admin_kick', 'message': 'Call the office', 'lock': false});
      await Future<void>.delayed(Duration.zero);

      expect(prefs.getString('server_access_token'), isNull);
      expect(prefs.getString('server_refresh_token'), isNull);
      expect(api.getPosName(), 'POS-1');
      expect(api.getTenantId(), 7);
      expect(api.getBusinessId(), 3);
      expect(api.getBaseUrl(), 'https://bms.test/api');
      expect(forced, isTrue, reason: 'the re-auth gate must open');
      expect(AccountStatusStore(prefs).isBlocked, isFalse,
          reason: 'lock=false must not lock sign-in');

      // A restart reads it back.
      final after = KickStore(prefs).current!;
      expect(after.code, 'ADMIN_KICK');
      expect(after.message, 'Call the office');
      await sub.cancel();
    });

    test('lock=true also locks, with the code as reasonCode', () async {
      final prefs = await _terminalPrefs();
      await ApiService(prefs).applyKick(
          {'code': 'SUBSCRIPTION_ENDED', 'message': 'Renew', 'lock': true});
      final block = AccountStatusStore(prefs).current!;
      expect(block.reasonCode, 'SUBSCRIPTION_ENDED');
      expect(block.scope, AccountBlockScope.terminal);
    });
  });

  group('reasonCode', () {
    test('read from a 423 body and from account-status', () {
      final b = accountBlockFromError(statusCode: 423, body: {
        'code': 'ACCOUNT_DISABLED',
        'scope': 'BUSINESS',
        'reasonCode': 'ADMIN_KICK',
      })!;
      expect(b.reasonCode, 'ADMIN_KICK');
      final s = parseAccountStatus(
          {'active': false, 'scope': 'TENANT', 'reasonCode': 'SUBSCRIPTION_ENDED'});
      expect((s as AccountBlock).reasonCode, 'SUBSCRIPTION_ENDED');
    });

    test('survives a restart and keeps the first one', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await AccountStatusStore(prefs).block(AccountBlock(
          scope: AccountBlockScope.tenant,
          reasonCode: 'ADMIN_KICK',
          since: DateTime(2026, 11, 20)));
      await AccountStatusStore(prefs).block(AccountBlock(
          scope: AccountBlockScope.tenant, since: DateTime(2026, 11, 21)));
      expect(AccountStatusStore(prefs).current!.reasonCode, 'ADMIN_KICK');
    });
  });

  group('lock card refresh (account-status)', () {
    Future<(ApiService, SharedPreferences)> locked(
        ResponseBody Function(RequestOptions) server) async {
      final prefs = await _terminalPrefs();
      await AccountStatusStore(prefs).block(AccountBlock(
          scope: AccountBlockScope.terminal,
          reasonCode: 'ADMIN_KICK',
          since: DateTime.now()));
      final api = ApiService(prefs);
      api.dio.httpClientAdapter = _FakeAdapter(server);
      return (api, prefs);
    }

    test('still locked when the server says inactive', () async {
      final (api, prefs) = await locked((_) =>
          _json({'active': false, 'scope': 'TERMINAL', 'reasonCode': 'ADMIN_KICK'}));
      expect(await api.checkAccountStatus(), AccountCheck.blocked);
      expect(AccountStatusStore(prefs).isBlocked, isTrue);
    });

    test('offline keeps the lock', () async {
      final (api, prefs) = await locked((o) => throw DioException(
          requestOptions: o, type: DioExceptionType.connectionError));
      expect(await api.checkAccountStatus(), AccountCheck.unknown);
      expect(AccountStatusStore(prefs).isBlocked, isTrue);
    });

    test('unlocks only on a definite active', () async {
      final (api, prefs) = await locked((_) => _json({'active': true}));
      expect(await api.checkAccountStatus(), AccountCheck.active);
      expect(AccountStatusStore(prefs).isBlocked, isFalse);
    });
  });

  group('set_config / get_config', () {
    late ProviderContainer container;
    late RemoteConfigService config;
    final configProvider = Provider((ref) => RemoteConfigService(ref));

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'sse_enabled': false,
        'server_password': 'kds-secret',
        'settings_pin': '1234',
      });
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      config = container.read(configProvider);
    });

    tearDown(() => container.dispose());

    test('applies allowed keys, refuses the rest with a reason', () async {
      final r = await config.setConfig({
        'changes': {
          'sseEnabled': true,
          'bulkSyncSize': 120,
          'currency': 'EUR',
          'zeroPriceTvaRate': 0,
          'autoSyncDurationMinutes': 'ten',
          'serverPort': 9090,
        }
      });
      expect(r['applied'], unorderedEquals(['sseEnabled', 'bulkSyncSize']));
      expect(r['before'], {'sseEnabled': false, 'bulkSyncSize': 50});
      expect(r['after'], {'sseEnabled': true, 'bulkSyncSize': 120});
      final rejected = r['rejected'] as Map;
      expect(rejected.keys,
          containsAll(['currency', 'zeroPriceTvaRate', 'serverPort', 'autoSyncDurationMinutes']));
      expect(container.read(settingsProvider).sseEnabled, isTrue);
      expect(container.read(settingsProvider).currency, isNot('EUR'));
      expect(container.read(sharedPreferencesProvider).getBool('sse_enabled'), isTrue);
    });

    test('buttonOrder may only be reordered', () async {
      final order = container.read(settingsProvider).buttonOrder;
      final r = await config.setConfig({
        'changes': {'buttonOrder': [...order.skip(1)]}
      });
      expect((r['rejected'] as Map).containsKey('buttonOrder'), isTrue);
      final ok = await config.setConfig({
        'changes': {'buttonOrder': order.reversed.toList()}
      });
      expect(ok['applied'], ['buttonOrder']);
      expect(container.read(settingsProvider).buttonOrder, order.reversed.toList());
    });

    test('nothing touching money, Z or passwords is editable', () {
      const forbidden = [
        'currency', 'zeroPriceTvaRate', 'totalsIncludeDeliveryFee',
        'deliveryFeePresets', 'quickCashAmounts', 'defaultPaymentMethod',
        'payButtonAction', 'showTipDialog', 'showTipButton',
        'showDiscountButton', 'showRefundButton', 'paymentCompletesKitchen',
        'allowZCloseWithUnpaid', 'zReportHiddenSections', 'xReportHiddenSections',
        'cashierDefaultPermissions', 'settingsPin', 'serverPassword',
        'serverPort', 'settingsLockEnabled', 'orderNumberResetMode',
        'persons', 'orderType', 'confirmOrder', 'table', 'waiter',
        'defaultOrderType',
      ];
      for (final k in forbidden) {
        expect(config.allowedKeys, isNot(contains(k)), reason: k);
      }
    });

    test('set_printers: text values, per-field rejections', () async {
      final r = await config.setPrinters({
        'changes': {
          'receipt': {
            'address': '192.168.1.50:9100',
            'connectionType': 'network',
            'kdsPrintMode': 'full',
          },
          'kds': {'connectionType': 'WIFI', 'kdsPrintMode': 'modificationsOnly'},
          'pool': {'nope': {'address': '1.2.3.4'}},
        }
      });
      final after = r['after'] as Map;
      expect(after['receipt']['address'], '192.168.1.50:9100');
      expect(after['receipt']['connectionType'], 'NETWORK');
      expect(after['kds']['printMode'], 'modificationsOnly');
      expect((r['rejected'] as Map).keys, containsAll([
        'receipt.kdsPrintMode',
        'kds.connectionType',
        'pool.nope',
      ]));
    });

    test('get_config strips secrets', () {
      final c = config.getConfig({});
      final settings = c['settings'] as Map;
      expect(settings.containsKey('serverPassword'), isFalse);
      expect(settings.containsKey('settingsPin'), isFalse);
      expect(jsonEncode(c), isNot(contains('kds-secret')));
      expect(jsonEncode(c), isNot(contains('1234')));
      expect(config.getConfig({'section': 'terminal'}).keys, ['terminal']);
    });
  });
}
