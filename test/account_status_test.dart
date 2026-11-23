import 'package:caisse212/domain/models/account_status.dart';
import 'package:caisse212/services/account_status_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('accountBlockFromError', () {
    test('423 with the contract body', () {
      final b = accountBlockFromError(
        statusCode: 423,
        body: {'code': 'ACCOUNT_DISABLED', 'scope': 'BUSINESS', 'message': 'Unpaid'},
      )!;
      expect(b.scope, AccountBlockScope.business);
      expect(b.message, 'Unpaid');
    });

    test('header alone (proxy rewrote the body)', () {
      final b = accountBlockFromError(
          statusCode: 423, body: '<html>', statusHeader: 'DISABLED_TENANT')!;
      expect(b.scope, AccountBlockScope.tenant);
    });

    test('code on another status still counts', () {
      expect(
          accountBlockFromError(statusCode: 403, body: {'code': 'ACCOUNT_DISABLED'}),
          isNotNull);
    });

    test('legacy 403 "POS terminal is not active"', () {
      final b = accountBlockFromError(
          statusCode: 403, body: {'message': 'POS terminal is not active'})!;
      expect(b.scope, AccountBlockScope.terminal);
    });

    test('ordinary errors are not a block', () {
      expect(accountBlockFromError(statusCode: 403, body: {'message': 'Forbidden'}), isNull);
      expect(accountBlockFromError(statusCode: 401, body: null), isNull);
      expect(accountBlockFromError(statusCode: 500, body: {'code': 'X'}), isNull);
      expect(accountBlockFromError(statusCode: 200, body: null, statusHeader: 'ACTIVE'),
          isNull);
    });
  });

  group('parseAccountStatus', () {
    test('active', () => expect(parseAccountStatus({'active': true}), true));
    test('disabled', () {
      final b = parseAccountStatus({'active': false, 'scope': 'TERMINAL'});
      expect(b, isA<AccountBlock>());
      expect((b as AccountBlock).scope, AccountBlockScope.terminal);
    });
    test('absent or unreadable changes nothing', () {
      expect(parseAccountStatus(null), isNull);
      expect(parseAccountStatus({'scope': 'TENANT'}), isNull);
      expect(parseAccountStatus({'active': 'maybe'}), isNull);
    });
  });

  group('AccountStatusStore', () {
    test('persists, keeps the first since, clears', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = AccountStatusStore(prefs);
      expect(store.isBlocked, isFalse);

      final first = DateTime(2026, 11, 16, 9);
      await store.block(AccountBlock(scope: AccountBlockScope.terminal, since: first));
      await store.block(AccountBlock(
          scope: AccountBlockScope.tenant, message: 'x', since: DateTime(2026, 11, 16, 10)));
      final b = AccountStatusStore(prefs).current!;
      expect(b.scope, AccountBlockScope.tenant);
      expect(b.since, first);

      await store.applyStatus(true);
      expect(store.isBlocked, isFalse);
    });
  });
}
