import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/reservation_models.dart';
import 'package:caisse212/presentation/reservations/agenda_screen.dart';
import 'package:caisse212/presentation/reservations/reservation_panel.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/reservation_providers.dart';
import 'package:caisse212/providers/resource_providers.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/reservation_service.dart';
import 'package:caisse212/utils/app_localizations.dart';

/// The agenda with a realistic day: two staff, a room, a reservation whose
/// two services sit on two columns, a break and a slot busy elsewhere.
/// Pumps the real screen and drives the real gestures (tap, press-and-slide,
/// mouse hover and drag), so a layout or gesture regression fails here
/// instead of on a till.

/// Bounded pumping: the screen has a live clock, so pumpAndSettle could wait
/// forever.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Offline, and never touches the database: drift's timers do not run under
/// the widget tester's fake clock. The cache paths are covered in
/// reservations_test.dart against a real in-memory database.
class _NoDbService extends LocalReservationService {
  _NoDbService(ApiService api, AppDatabase db) : super(api, db, () => false);

  @override
  Future<Reservation?> refresh(Reservation r) async => null;
}

String _iso(DateTime local) => local.toUtc().toIso8601String();

Product _product(int id, String name, double price,
        {int? minutes, bool plannable = true}) =>
    Product(
      id: id,
      name: name,
      price: price,
      uom: 'unit',
      tvaAmount: 0,
      discountAmount: 0,
      finalPrice: price,
      isActive: true,
      isAvailable: true,
      isVariant: false,
      isSerialTracked: false,
      refundable: true,
      isPlannable: plannable,
      planDurationMinutes: minutes,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  final today = dayStartOf(DateTime.now());
  DateTime at(int h, [int m = 0]) =>
      DateTime(today.year, today.month, today.day, h, m);

  final frame = {
    'zone': 'Africa/Casablanca',
    'openHours': [
      {'start': _iso(at(9)), 'end': _iso(at(19))}
    ],
    'resources': [
      for (final r in [
        {'id': 1, 'name': 'Sarah', 'type': 'STAFF', 'color': '#7C3AED'},
        {'id': 2, 'name': 'Leila', 'type': 'STAFF', 'color': null},
        {'id': 3, 'name': 'Salle 1', 'type': 'ROOM', 'color': '#0EA5E9'},
      ])
        {
          ...r,
          'sortOrder': 0,
          'capacity': 1,
          'isActive': true,
          'availability': [
            {
              'date': dayKey(today),
              'ranges': [
                {'start': _iso(at(9)), 'end': _iso(at(13))},
                {'start': _iso(at(14)), 'end': _iso(at(19))},
              ]
            }
          ],
        }
    ],
    'blocks': [
      {
        'id': 9,
        'resourceId': 2,
        'kind': 'BREAK',
        'title': null,
        'startAt': _iso(at(13)),
        'endAt': _iso(at(14)),
      }
    ],
    'foreignBusy': [
      {'resourceId': 1, 'start': _iso(at(16)), 'end': _iso(at(17))}
    ],
  };

  Map<String, dynamic> item(int id, int productId, String name, DateTime s,
          DateTime e, int resourceId) =>
      {
        'id': id,
        'productId': productId,
        'name': name,
        'quantity': 1,
        'unitPrice': 100,
        'value': 100,
        'startAt': _iso(s),
        'endAt': _iso(e),
        'durationMinutes': e.difference(s).inMinutes,
        'resourceIds': [resourceId],
      };

  final amina = Reservation.fromJson({
    'id': 1,
    'code': 'RFFZK3E4',
    'status': 'CONFIRMED',
    'customer': {'id': 4, 'name': 'Amina', 'phone': '0612345678'},
    'startAt': _iso(at(10)),
    'endAt': _iso(at(11)),
    'value': 250,
    'items': [
      item(1, 19, 'Coupe', at(10), at(10, 30), 1),
      item(2, 20, 'Soin', at(10, 30), at(11), 3),
    ],
  });

  // An unconfirmed booking taken over Amina's cut on Sarah.
  final nadia = Reservation.fromJson({
    'id': 2,
    'code': 'NADIA001',
    'status': 'BOOKED',
    'customer': {'name': 'Nadia', 'phone': '0611111111'},
    'startAt': _iso(at(10, 15)),
    'endAt': _iso(at(10, 45)),
    'value': 100,
    'items': [item(5, 19, 'Coupe', at(10, 15), at(10, 45), 1)],
  });

  Future<void> pump(
    WidgetTester tester, {
    bool online = true,
    bool overlap = false,
    CartBooking? booking,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final day = AgendaDay.fromFrame(
        dayKey(today), frame, [amina, if (overlap) nadia],
        fetchedAt: DateTime.now());

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseProvider.overrideWithValue(db),
        canReserveProvider.overrideWithValue(online),
        // Offline service: the pull on open is a no-op, nothing hits a network.
        reservationServiceProvider
            .overrideWithValue(_NoDbService(ApiService(prefs), db)),
        agendaDayProvider.overrideWith((ref, date) async =>
            dayStartOf(date) == today ? day : AgendaDay(day: dayKey(date))),
        clockTickProvider.overrideWith((ref) => Stream.value(DateTime.now())),
        resourcesProvider.overrideWith((ref) => Stream.value(const [])),
        servicePoolsProvider.overrideWith((ref) => Stream.value(const {})),
        bookableServicesProvider.overrideWith((ref) => Stream.value([
              _product(19, 'Coupe', 100, minutes: 30),
              _product(20, 'Soin', 150, minutes: 45),
            ])),
        serviceCategoryNamesProvider.overrideWith((ref) async => const {}),
        retailProductSearchProvider.overrideWith((ref, q) async =>
            [_product(30, 'Shampoing', 80, plannable: false)]),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: AgendaScreen(booking: booking),
      ),
    ));
    await _settle(tester);
    // Today opens scrolled to the current hour, which by day puts the
    // morning fixtures out of view. Start from the top, whatever the clock.
    for (final s in tester.stateList<ScrollableState>(find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down))) {
      s.position.jumpTo(0);
    }
    await _settle(tester);
  }

  /// The grid header for [name] (the sidebar has a second, further left).
  Offset columnX(WidgetTester tester, String name) {
    final xs = find.text(name).evaluate().map((e) {
      final box = e.renderObject as RenderBox;
      return box.localToGlobal(box.size.center(Offset.zero));
    }).toList()
      ..sort((a, b) => a.dx.compareTo(b.dx));
    return xs.last;
  }

  /// Just below the ruler's [hour] line, so it snaps down to that hour.
  Future<double> hourY(WidgetTester tester, String hour) async {
    await tester.ensureVisible(find.text(hour));
    await _settle(tester);
    return tester.getCenter(find.text(hour)).dy + 10;
  }

  Future<void> tapSlot(WidgetTester tester, String column, String hour) async {
    final y = await hourY(tester, hour);
    await tester.tapAt(Offset(columnX(tester, column).dx, y));
    await _settle(tester);
  }

  testWidgets('draws columns, services, a break and busy-elsewhere',
      (tester) async {
    await pump(tester);
    expect(tester.takeException(), isNull);
    // Each person is a column header and a line in the sidebar's team list.
    for (final name in ['Sarah', 'Leila', 'Salle 1']) {
      expect(find.text(name), findsNWidgets(2));
    }
    // One card per service, each in its own column.
    expect(find.text('Amina'), findsNWidgets(2));
    expect(find.textContaining('Coupe'), findsOneWidget);
    expect(find.textContaining('Soin'), findsOneWidget);
    expect(find.text('Break'), findsOneWidget);
    expect(find.text('Busy elsewhere'), findsOneWidget);
    expect(find.textContaining('to sort out'), findsNothing);
  });

  testWidgets('tapping a reservation opens it with Ring up', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('Coupe'));
    await _settle(tester);
    expect(find.text('Ring up'), findsOneWidget);
    expect(find.text('RFFZK3E4'), findsOneWidget);
  });

  testWidgets('offline: banner shown, ring up still offered, writes off',
      (tester) async {
    await pump(tester, online: false);
    expect(find.textContaining('Offline'), findsOneWidget);
    final newButton = tester.widget<FilledButton>(find.ancestor(
        of: find.text('New reservation'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(newButton.onPressed, isNull);

    await tester.tap(find.textContaining('Coupe'));
    await _settle(tester);
    final ringUp = tester.widget<FilledButton>(find.ancestor(
        of: find.text('Ring up'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(ringUp.onPressed, isNotNull);
    final cancel = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Cancel reservation'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton)));
    expect(cancel.onPressed, isNull);
  });

  testWidgets('list view shows the reservation with its status',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('List'));
    await _settle(tester);
    expect(find.text('Amina'), findsOneWidget);
    // The status chip, beside the sidebar legend's own label.
    expect(find.text('Confirmed'), findsNWidgets(2));
    expect(find.text('Coupe · Soin'), findsOneWidget);
  });

  testWidgets('tapping an empty slot opens the panel at that time and person',
      (tester) async {
    await pump(tester);
    await tapSlot(tester, 'Leila', '15:00');
    expect(find.text('Search a customer by name or phone'), findsOneWidget);
    expect(find.text('15:00–15:30'), findsWidgets);
    // The first service goes to the column that was tapped.
    await tester.tap(find.widgetWithText(ListTile, 'Coupe'));
    await _settle(tester);
    final staff = tester
        .widget<DropdownButton<int?>>(find.byType(DropdownButton<int?>));
    expect(staff.value, 2);
  });

  testWidgets('press and slide picks the length', (tester) async {
    await pump(tester);
    final y = await hourY(tester, '15:00');
    final g = await tester.startGesture(Offset(columnX(tester, 'Leila').dx, y));
    await tester.pump(const Duration(milliseconds: 700)); // long press
    await g.moveBy(const Offset(0, 40));
    await tester.pump();
    await g.moveBy(const Offset(0, 40)); // ~ +50 min from the grab
    await tester.pump();
    expect(find.text('15:00–16:00'), findsOneWidget,
        reason: 'live label while sliding');
    await g.up();
    await _settle(tester);
    expect(find.text('Search a customer by name or phone'), findsOneWidget);
  });

  testWidgets('services chain, each can go to its own person, products ride',
      (tester) async {
    await pump(tester);
    await tapSlot(tester, 'Leila', '15:00');
    await tester.tap(find.widgetWithText(ListTile, 'Coupe'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Soin'));
    await _settle(tester);
    expect(find.text('15:00–15:30'), findsWidgets);
    expect(find.text('15:30–16:15'), findsWidgets); // panel + grid outline
    expect(find.textContaining('75 min'), findsOneWidget);

    // Hand the Soin to Sarah: same chain, another person.
    await tester.tap(find.byType(DropdownButton<int?>).last);
    await _settle(tester);
    await tester.tap(find.text('Sarah').last);
    await _settle(tester);
    expect(
        tester
            .widgetList<DropdownButton<int?>>(find.byType(DropdownButton<int?>))
            .map((d) => d.value),
        [2, 1]);

    // A retail product rides along, with no time of its own.
    await tester.tap(find.text('Products'));
    await _settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Search').last, 'sh');
    await _settle(tester);
    await tester.tap(find.widgetWithText(ListTile, 'Shampoing'));
    await _settle(tester);
    expect(find.byIcon(Icons.shopping_bag_outlined), findsWidgets);

    // Without a customer the booking cannot be sent yet.
    final book = tester.widget<FilledButton>(find.ancestor(
        of: find.textContaining('Book ·'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(book.onPressed, isNull);
  });

  testWidgets('booking over someone else warns before sending',
      (tester) async {
    await pump(tester);
    // 09:30 on Sarah is free, but a 45-min Soin runs into Amina's 10:00 cut.
    final y = await hourY(tester, '09:00') + 40;
    await tester.tapAt(Offset(columnX(tester, 'Sarah').dx, y));
    await _settle(tester);
    expect(find.text('09:30–10:00'), findsWidgets);
    await tester.tap(find.widgetWithText(ListTile, 'Soin'));
    await _settle(tester);
    expect(find.text('Overlaps another booking'), findsOneWidget);
    // It can still be booked, but only as unconfirmed ("Book anyway" is the
    // server's 409 dialog, not the panel).
    expect(find.text('Overlapping bookings stay unconfirmed.'), findsOneWidget);
    final confirmed = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Customer already confirmed'));
    expect(confirmed.value, isFalse);
    expect(confirmed.onChanged, isNull);
  });

  testWidgets('overlaps are flagged and listed to sort out', (tester) async {
    await pump(tester, overlap: true);
    expect(find.text('1 to sort out'), findsOneWidget);
    expect(find.byIcon(Icons.layers_rounded), findsWidgets);
    await tester.tap(find.text('1 to sort out'));
    await _settle(tester);
    expect(find.text('To sort out'), findsOneWidget);
    expect(find.textContaining('Nadia'), findsWidgets);
    // Leila is free 10:15–10:45: one tap hands Nadia's cut to her.
    expect(find.text('To Leila'), findsWidgets);
    expect(find.text('Confirm this one'), findsOneWidget);
  });

  testWidgets('from the till: the cart is the reservation', (tester) async {
    var booked = false;
    await pump(tester,
        booking: CartBooking(
          lines: () => [
            BasketLine(
                productId: 20,
                name: 'Soin',
                catalogPrice: 150,
                durationMinutes: 45),
          ],
          customer: const PanelCustomer(name: 'Karima', phone: '0622222222'),
          summary: 'Soin',
          onBooked: () => booked = true,
        ));
    expect(find.text('Pick a slot for: Soin'), findsOneWidget);
    await tapSlot(tester, 'Leila', '15:00');
    expect(find.text('15:00–15:45'), findsWidgets);
    expect(find.text('Karima'), findsOneWidget);
    // The customer and a service are there: only the server is missing.
    final book = tester.widget<FilledButton>(find.ancestor(
        of: find.textContaining('Book ·'),
        matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(book.onPressed, isNotNull);
    expect(booked, isFalse);
  });

  testWidgets('mouse: hover shows where a click books, drag previews',
      (tester) async {
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    final y = await hourY(tester, '15:00');
    await mouse.moveTo(Offset(columnX(tester, 'Leila').dx, y));
    await _settle(tester);
    expect(find.text('+ 15:00'), findsOneWidget);

    // Grab Amina's cut and drag it an hour down: no long press needed.
    await tester.ensureVisible(find.textContaining('Coupe'));
    await _settle(tester);
    final card = tester.getCenter(find.textContaining('Coupe'));
    await mouse.moveTo(card);
    await tester.pump();
    await mouse.down(card);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await mouse.moveBy(const Offset(0, 16));
      await tester.pump();
    }
    expect(find.text('11:00–11:30'), findsOneWidget,
        reason: 'ghost shows the landing time');
    await mouse.up();
    await _settle(tester);
    // The drop reached the service, which refuses it offline and raises a
    // toast; let the toast's timer run out.
    await tester.pump(const Duration(seconds: 6));
  });
}
