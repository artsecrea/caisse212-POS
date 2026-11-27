import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/catalogue_repository.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/floor_repository.dart';
import 'package:caisse212/services/api_service.dart';

/// The providers that replace services the screens built inline.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('stateless services and repositories are shared per container', () {
    final providers = <ProviderListenable<Object>>[
      dailySummaryServiceProvider,
      unpaidOrdersServiceProvider,
      exchangeServiceProvider,
      kitchenBoardServiceProvider,
      zDayResolverProvider,
      customerServiceProvider,
      catalogueRepositoryProvider,
      floorQueriesProvider,
    ];
    for (final p in providers) {
      expect(identical(container.read(p), container.read(p)), isTrue);
    }
  });

  test('the services read the overridden database', () async {
    // A resolver on another database would not see this session.
    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        code: 'S1',
        cashierId: 1,
        moneyAtStart: 0,
        status: const Value('active')));
    final active = await container.read(zDayResolverProvider).activeSession();
    expect(active?.code, 'S1');
  });

  group('dataSyncServiceFactoryProvider', () {
    test('a fresh instance per call, never the shared one', () {
      final make = container.read(dataSyncServiceFactoryProvider);
      final api = ApiService(prefs);
      final a = make(api);
      final b = make(api, prefs);
      expect(identical(a, b), isFalse);
      expect(identical(a, container.read(dataSyncServiceProvider)), isFalse);
    });

    test('a progress callback set on one instance stays on it', () {
      final make = container.read(dataSyncServiceFactoryProvider);
      final mine = make(ApiService(prefs));
      mine.onProgress = (_, __) {};
      expect(make(ApiService(prefs)).onProgress, isNull);
      expect(container.read(dataSyncServiceProvider).onProgress, isNull);
    });
  });
}
