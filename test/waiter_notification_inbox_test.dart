import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/waiter_call_service.dart';
import 'package:caisse212/services/waiter_kitchen_events.dart';
import 'package:caisse212/services/waiter_notification_inbox.dart';

/// The waiter's notification history: in memory, per waiter, with read flags.
void main() {
  group('WaiterNotificationInbox', () {
    late WaiterNotificationInbox inbox;
    setUp(() => inbox = WaiterNotificationInbox());

    test('a waiter sees their own entries and broadcasts, newest first', () {
      inbox.add(id: 'a', waiterId: 1, type: 'kitchen-ready', data: {});
      inbox.add(id: 'b', waiterId: 2, type: 'kitchen-ready', data: {});
      inbox.add(id: 'c', waiterId: null, type: 'product-availability', data: {});

      expect(inbox.listFor(1).map((e) => e['id']), ['c', 'a']);
      expect(inbox.listFor(2).map((e) => e['id']), ['c', 'b']);
    });

    test('read state is per waiter, even for a broadcast', () {
      inbox.add(id: 'r', waiterId: null, type: 'product-availability', data: {});
      inbox.markRead(1, ['r']);

      expect(inbox.unreadCount(1), 0);
      expect(inbox.unreadCount(2), 1);
      expect(inbox.listFor(2).single['read'], isFalse);
    });

    test('mark all read with no ids', () {
      inbox.add(id: 'a', waiterId: 1, type: 'kitchen-ready', data: {});
      inbox.add(id: 'b', waiterId: 1, type: 'kitchen-canceled', data: {});
      inbox.markRead(1);
      expect(inbox.unreadCount(1), 0);
    });

    test('entries older than a day fall out', () {
      inbox.add(
          id: 'old',
          waiterId: 1,
          type: 'kitchen-ready',
          data: {},
          at: DateTime.now().subtract(const Duration(hours: 25)));
      inbox.add(id: 'new', waiterId: 1, type: 'kitchen-ready', data: {});
      expect(inbox.listFor(1).map((e) => e['id']), ['new']);
    });

    test('bounded by count', () {
      for (var i = 0; i < WaiterNotificationInbox.maxEntries + 5; i++) {
        inbox.add(id: '$i', waiterId: 1, type: 'kitchen-ready', data: {});
      }
      expect(inbox.unreadCount(1), WaiterNotificationInbox.maxEntries);
      expect(inbox.listFor(1, limit: 1).single['id'],
          '${WaiterNotificationInbox.maxEntries + 4}');
    });
  });

  group('services feed the inbox', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SharedPreferences.setMockInitialValues({
        'waiter_call_enabled': true,
        'waiter_notify_rupture': true,
      });
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a kitchen event is kept under its eventId', () {
      container
          .read(waiterKitchenEventServiceProvider)
          .productAvailabilityChanged(
              productId: 1, name: 'Tajine', isAvailable: false);
      final entry =
          container.read(waiterNotificationInboxProvider).listFor(3).single;
      expect(entry['type'], 'product-availability');
      expect(entry['id'], (entry['data'] as Map)['eventId']);
    });

    test('a call is kept, and acknowledging it marks it read', () async {
      final calls = container.read(waiterCallServiceProvider);
      final r =
          await calls.call(waiterId: 1, waiterName: 'Ali', fromUser: 'Sam');
      final inbox = container.read(waiterNotificationInboxProvider);
      expect(inbox.listFor(1).single['type'], 'waiter-call');
      expect(inbox.unreadCount(1), 1);

      calls.acknowledge(r.call.id);
      expect(inbox.unreadCount(1), 0);
    });
  });
}
