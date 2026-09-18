import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/providers/database_providers.dart' show CurrentUser;
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/permission_service.dart';

/// Till-side product creation.
///
/// The server owns every default and the plan's product cap, so the POS's job
/// is narrow: send four fields, respect the gate, and never turn one of the
/// server's two success shapes into an error on screen.
void main() {
  late ApiService api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = ApiService(await SharedPreferences.getInstance());
  });

  group('category is one field or the other', () {
    test('sending both is refused before it reaches the server', () async {
      // The contract 400s on both. Catching it here keeps a pointless round
      // trip — and a confusing server error — off the counter.
      expect(
        () => api.createPosProduct(
          name: 'Coca 33cl',
          price: 12,
          categoryId: 8,
          categoryName: 'Boissons',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an empty categoryName alongside an id is not "both"', () async {
      // The dialog passes '' for the unused branch; treating that as a conflict
      // would make picking an existing category impossible.
      await expectLater(
        api.createPosProduct(
            name: 'X', price: 1, categoryId: 8, categoryName: '   '),
        throwsA(isNot(isA<ArgumentError>())),
      );
    });
  });

  group('server errors keep their meaning', () {
    PosCatalogException fromResponse(int status, dynamic body) {
      return PosCatalogException.fromDio(DioException(
        requestOptions: RequestOptions(path: '/pos/products'),
        response: Response(
          requestOptions: RequestOptions(path: '/pos/products'),
          statusCode: status,
          data: body,
        ),
      ));
    }

    test('403 is recognisable as "this role may not"', () {
      // The UI hides the entry points on this, rather than showing an error.
      final e = fromResponse(403, {'message': 'Access denied'});
      expect(e.isForbidden, isTrue);
    });

    test('a plan-limit message is preserved VERBATIM', () {
      // It names the cap and the plan. Paraphrasing leaves the operator with
      // nothing to act on, so the exact string has to survive to the screen.
      const msg = 'Product limit reached for plan STARTER (50 of 50).';
      final e = fromResponse(422, {'message': msg});
      expect(e.message, msg);
      expect(e.isForbidden, isFalse);
    });

    test('a plain-string error body is kept too', () {
      final e = fromResponse(400, 'categoryId and categoryName are exclusive');
      expect(e.message, 'categoryId and categoryName are exclusive');
    });

    test('an empty body still yields a non-empty message', () {
      // An empty error box tells the cashier nothing at all.
      final e = fromResponse(500, null);
      expect(e.message.trim(), isNotEmpty);
    });
  });

  group('the pos:catalog gate', () {
    CurrentUser user(String perms, {String type = 'cashier'}) => CurrentUser(
        1, 'u', 'p', 'A', 'B', type, null, null, null, perms,
        DateTime(2026), DateTime(2026), null);

    test('a role without the token cannot create', () {
      final svc = PermissionService(user('pos:orders:view,pos:products:view'));
      expect(svc.hasPermission(Permissions.catalog), isFalse);
    });

    test('a role with it can', () {
      final svc = PermissionService(user('pos:orders:view,pos:catalog'));
      expect(svc.hasPermission(Permissions.catalog), isTrue);
    });

    test('an admin can', () {
      expect(
          PermissionService(user('', type: 'admin'))
              .hasPermission(Permissions.catalog),
          isTrue);
    });

    test('a pos:* wildcard grants it', () {
      expect(PermissionService(user('pos:*')).hasPermission(Permissions.catalog),
          isTrue);
    });

    test('the token is NOT implied by products:modify', () {
      // Editing the catalogue in the back office and minting products at the
      // till are different privileges — the plan cap makes the second costly.
      final svc = PermissionService(user('pos:products:modify'));
      expect(svc.hasPermission(Permissions.catalog), isFalse);
    });
  });
}
