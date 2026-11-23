import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/reservation_models.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/reservation_service.dart';
import 'package:caisse212/presentation/reservations/agenda_conflicts.dart';

/// The reservations contract (backend V198) has rules that break quietly:
///
///   * every instant on the wire is UTC with `Z`, every instant on screen local;
///   * a write never carries a local-only customer id (the server 404s);
///   * a converted reservation reaches the server only as `reservationCode` on
///     the order push, and the link result comes back in two shapes;
///   * the agenda cache must still show a day, and ring a reservation up,
///     with no connection.

Map<String, dynamic> _reservationJson({
  int id = 1,
  String code = 'RFFZK3E4',
  String status = 'BOOKED',
  String start = '2026-10-14T10:00:00Z',
  String end = '2026-10-14T10:30:00Z',
  double unitPrice = 100,
  int productId = 19,
  String? orderCode,
}) =>
    {
      'id': id,
      'code': code,
      'businessId': 2,
      'status': status,
      'timeStatus': 'NOT_YET',
      'source': 'POS',
      'customer': {'id': 4, 'name': 'Amina', 'phone': '0612345678'},
      'startAt': start,
      'endAt': end,
      'value': unitPrice,
      'note': null,
      'orderId': null,
      'orderCode': orderCode,
      'items': [
        {
          'id': 7,
          'productId': productId,
          'variantId': null,
          'name': 'Coupe',
          'quantity': 1.0,
          'unitPrice': unitPrice,
          'value': unitPrice,
          'startAt': start,
          'endAt': end,
          'durationMinutes': 30,
          'resourceIds': [1],
          'note': null,
        }
      ],
    };

void main() {
  group('Reservation.fromJson', () {
    test('instants arrive UTC and are exposed local', () {
      final r = Reservation.fromJson(_reservationJson());
      expect(r.startAt.isUtc, isFalse);
      expect(r.startAt, DateTime.utc(2026, 10, 14, 10).toLocal());
      expect(r.items.single.resourceIds, [1]);
      expect(r.customer?.phone, '0612345678');
    });

    test('only the four live statuses hold a slot', () {
      for (final s in ['BOOKED', 'CONFIRMED', 'ARRIVED', 'CONVERTED']) {
        expect(Reservation.fromJson(_reservationJson(status: s)).holdsSlot,
            isTrue,
            reason: s);
      }
      for (final s in ['NO_SHOW', 'CANCELED']) {
        expect(Reservation.fromJson(_reservationJson(status: s)).holdsSlot,
            isFalse,
            reason: s);
      }
    });

    test('a linked or converted reservation cannot be rung up again', () {
      expect(Reservation.fromJson(_reservationJson()).canConvert, isTrue);
      expect(
          Reservation.fromJson(_reservationJson(status: 'CONVERTED'))
              .canConvert,
          isFalse);
      expect(
          Reservation.fromJson(_reservationJson(orderCode: 'ORD9')).canConvert,
          isFalse);
      expect(Reservation.fromJson(_reservationJson(status: 'CANCELED'))
          .canConvert, isFalse);
    });
  });

  group('ReservationDraft', () {
    test('sends UTC with Z and omits what was not given', () {
      final draft = ReservationDraft(
        startAt: DateTime(2026, 10, 14, 11),
        customerName: '  Amina ',
        customerPhone: '0612345678',
        items: const [ReservationDraftItem(productId: 19)],
      );
      final json = draft.toJson();
      expect(json['startAt'], endsWith('Z'));
      expect(json['customerName'], 'Amina');
      expect(json.containsKey('customerId'), isFalse);
      expect(json.containsKey('note'), isFalse);
      expect(json['status'], 'BOOKED');
      // Omitted resourceIds = the server auto-assigns.
      expect(json['items'], [
        {'productId': 19}
      ]);
    });

    test('an edit keeps its status by not sending one', () {
      final json = ReservationDraft(
        startAt: DateTime(2026, 10, 14, 11),
        status: null,
        items: const [ReservationDraftItem(id: 7, productId: 19)],
      ).toJson();
      expect(json.containsKey('status'), isFalse);
      expect((json['items'] as List).single['id'], 7);
    });
  });

  group('errors', () {
    test('409 details are strings on the wire', () {
      final c = ReservationConflict.fromJson({
        'status': 409,
        'message': 'Leila is already booked 14/10 17:00–17:30',
        'details': {'code': 'SLOT_TAKEN', 'resourceId': '2', 'item': '0'},
      });
      expect(c.code, 'SLOT_TAKEN');
      expect(c.resourceId, 2);
      expect(c.itemIndex, 0);
      expect(c.message, startsWith('Leila'));
    });
  });

  group('ReservationLink.listFrom', () {
    test('single PUT: the object, keyed to the pushed order', () {
      final links = ReservationLink.listFrom({
        'reservationLink': {
          'reservationCode': 'R1',
          'status': 'ALREADY_LINKED',
          'linkedOrderCode': 'ORD1',
        },
      }, orderCode: 'ORD2');
      expect(links.single.orderCode, 'ORD2');
      expect(links.single.status, ReservationLinkStatus.alreadyLinked);
      expect(links.single.linkedOrderCode, 'ORD1');
    });

    test('bulk: the array, each naming its order', () {
      final links = ReservationLink.listFrom({
        'reservationLinks': [
          {'orderCode': 'A', 'reservationCode': 'R1', 'status': 'LINKED'},
          {'orderCode': 'B', 'reservationCode': 'R2', 'status': 'NOT_FOUND'},
        ],
      });
      expect(links.map((l) => l.orderCode), ['A', 'B']);
    });

    test('a backend without reservations reports nothing', () {
      expect(ReservationLink.listFrom({'conflicts': []}), isEmpty);
      expect(ReservationLink.listFrom([1, 2]), isEmpty);
    });
  });

  group('AgendaWindow.dayFrame', () {
    test('keeps only the day: hours, availability, blocks, busy', () {
      final day = DateTime.utc(2026, 10, 14, 12).toLocal();
      final key = dayKey(day);
      final w = AgendaWindow.fromJson({
        'zone': 'Africa/Casablanca',
        'openHours': [
          {
            'date': key,
            'ranges': [
              {'start': '2026-10-14T08:00:00Z', 'end': '2026-10-14T18:00:00Z'}
            ]
          },
          {'date': '2026-10-15', 'ranges': []},
        ],
        'resources': [
          {
            'id': 1,
            'name': 'Sarah',
            'type': 'STAFF',
            'availability': [
              {
                'date': key,
                'ranges': [
                  {'start': '2026-10-14T08:00:00Z', 'end': '2026-10-14T12:00:00Z'}
                ]
              },
              {'date': '2026-10-15', 'ranges': []},
            ],
          }
        ],
        'reservations': [],
        'blocks': [
          {
            'id': 3,
            'resourceId': 1,
            'kind': 'BREAK',
            'startAt': '2026-10-14T12:00:00Z',
            'endAt': '2026-10-14T13:00:00Z'
          },
          {
            'id': 4,
            'resourceId': 1,
            'kind': 'BREAK',
            'startAt': '2026-10-20T12:00:00Z',
            'endAt': '2026-10-20T13:00:00Z'
          },
        ],
        'foreignBusy': [
          {
            'resourceId': 1,
            'start': '2026-10-14T15:00:00Z',
            'end': '2026-10-14T16:00:00Z'
          }
        ],
        'summary': {'count': 0, 'value': 0, 'days': []},
      });
      final d = AgendaDay.fromFrame(key, w.dayFrame(day), const []);
      expect(d.zone, 'Africa/Casablanca');
      expect(d.openHours, hasLength(1));
      expect(d.resources.single.availabilityOn(key), hasLength(1));
      expect(d.blocks.map((b) => b.id), [3]);
      expect(d.foreignBusy, hasLength(1));
    });
  });

  group('ReservationService (cache + conversion)', () {
    late AppDatabase db;
    late ReservationService service;
    var online = false;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      online = false;
      service = ReservationService(ApiService(prefs), db, () => online);
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(19),
            name: 'Coupe',
            price: 100,
            finalPrice: 90,
            tvaAmount: const Value(15),
            discountAmount: const Value(10),
          ));
    });
    tearDown(() => db.close());

    Future<void> cache(Map<String, dynamic> json) =>
        db.into(db.cachedReservations).insert(CachedReservationsCompanion.insert(
              id: Value(json['id'] as int),
              code: json['code'] as String,
              status: json['status'] as String,
              startAt: DateTime.parse(json['startAt'] as String).toLocal(),
              endAt: DateTime.parse(json['endAt'] as String).toLocal(),
              customerName: const Value('Amina'),
              customerPhone: const Value('0612345678'),
              payload: '{"id":${json['id']},"code":"${json['code']}",'
                  '"status":"${json['status']}","startAt":"${json['startAt']}",'
                  '"endAt":"${json['endAt']}","items":[]}',
            ));

    test('writes are refused offline, never queued', () async {
      expect(
          () => service.create(ReservationDraft(
              startAt: DateTime.now(),
              items: const [ReservationDraftItem(productId: 19)])),
          throwsA(isA<OfflineReservationException>()));
      expect(await db.select(db.pendingSyncOperations).get(), isEmpty);
    });

    test('a cached day still loads offline, by overlap', () async {
      await cache(_reservationJson(
          start: '2026-10-14T23:30:00Z', end: '2026-10-15T01:00:00Z'));
      final start = DateTime.utc(2026, 10, 14, 23, 30).toLocal();
      final end = DateTime.utc(2026, 10, 15, 1).toLocal();
      for (final d in {dayStartOf(start), dayStartOf(end)}) {
        final day = await service.loadDay(d);
        expect(day.reservations.map((r) => r.code), ['RFFZK3E4'], reason: '$d');
        expect(day.fetchedAt, isNull);
      }
    });

    test('offline search finds by name and phone', () async {
      await cache(_reservationJson());
      expect((await service.search('amina')).single.code, 'RFFZK3E4');
      expect((await service.search('061234')).single.code, 'RFFZK3E4');
    });

    test('ringing up at the catalogue price gives the catalogue line',
        () async {
      final cart = await service.buildCart(
          Reservation.fromJson(_reservationJson(unitPrice: 100)),
          orderType: 'TAKE_AWAY');
      final line = cart.items.single;
      expect(cart.reservationCode, 'RFFZK3E4');
      expect(line.finalPrice, 90);
      expect(line.discount, 10);
      expect(line.tva, 15);
      // Phone kept for the cart even with no local customer row.
      expect(cart.customerPhone, '0612345678');
    });

    test('an agreed price that differs from the catalogue wins', () async {
      final cart = await service.buildCart(
          Reservation.fromJson(_reservationJson(unitPrice: 80)),
          orderType: 'TAKE_AWAY');
      final line = cart.items.single;
      expect(line.finalPrice, 80);
      expect(line.discount, 0);
      // TVA scaled to the price actually charged.
      expect(line.tva, closeTo(15 * 80 / 90, 0.01));
    });

    test('a service missing locally stops the conversion', () async {
      expect(
          () => service.buildCart(
              Reservation.fromJson(_reservationJson(productId: 999)),
              orderType: 'TAKE_AWAY'),
          throwsA(isA<StateError>()));
    });

    test('the local customer is found by phone', () async {
      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: const Value(55),
            firstName: const Value('Amina'),
            phone: const Value('0612345678'),
            phoneNormalized: const Value('212612345678'),
          ));
      final cart = await service.buildCart(
          Reservation.fromJson(_reservationJson()),
          orderType: 'TAKE_AWAY');
      expect(cart.customerId, 55);
    });
  });

  test('the order push carries reservationCode', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final sync = DataSyncService(db, ApiService(prefs), prefs);
    await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD1',
          status: const Value('COMPLETED'),
          reservationCode: const Value('RFFZK3E4'),
        ));
    await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD2',
          status: const Value('COMPLETED'),
        ));
    final orders = {
      for (final o in await sync.getOrdersForSync()) o['code']: o,
    };
    expect(orders['ORD1']!['reservationCode'], 'RFFZK3E4');
    expect(orders['ORD2']!.containsKey('reservationCode'), isFalse);
    // Booking no longer rides on order lines.
    expect(orders['ORD1']!.toString(), isNot(contains('planStartAt')));
  });

  group('retail lines and overlaps', () {
    test('V199 add-ons say so: kind ADDON, null times', () {
      final r = Reservation.fromJson({
        ..._reservationJson(),
        'items': [
          ...(_reservationJson()['items'] as List),
          {'id': 9, 'kind': 'ADDON', 'productId': 30, 'name': 'Shampoing',
           'quantity': 1, 'unitPrice': 80, 'value': 80, 'startAt': null,
           'endAt': null, 'durationMinutes': 0, 'resourceIds': []},
        ],
      });
      expect(r.items.map((i) => i.timed), [true, false]);
      expect(r.items.last.resourceIds, isEmpty);
    });

    test('a 409 a manager may override says so', () {
      final c = ReservationConflict.fromJson({
        'status': 409,
        'message': 'Leila is already booked',
        'details': {'code': 'SLOT_TAKEN', 'overbookable': 'true'},
      });
      expect(c.overbookable, isTrue);
      expect(
          ReservationConflict.fromJson({
            'message': 'x',
            'details': {'code': 'SLOT_TAKEN'}
          }).overbookable,
          isFalse);
    });

    test('a product without times is a retail line, not a slot', () {
      final r = Reservation.fromJson({
        ..._reservationJson(),
        'items': [
          ...(_reservationJson()['items'] as List),
          {'id': 9, 'productId': 30, 'name': 'Shampoing', 'quantity': 2,
           'unitPrice': 80, 'value': 160},
        ],
      });
      expect(r.items.map((i) => i.timed), [true, false]);
      // The reservation's window comes from its services only.
      expect(r.endAt, DateTime.utc(2026, 10, 14, 10, 30).toLocal());
    });

    test('the draft sends a retail line without time or resource', () {
      final json = ReservationDraft(
        startAt: DateTime(2026, 10, 14, 11),
        overbook: true,
        items: [
          ReservationDraftItem(
              productId: 19,
              startAt: DateTime(2026, 10, 14, 11),
              endAt: DateTime(2026, 10, 14, 11, 30),
              resourceIds: const [2]),
          ReservationDraftItem(
              productId: 30,
              quantity: 2,
              unitPrice: 75,
              timed: false,
              startAt: DateTime(2026, 10, 14, 11),
              resourceIds: const [2]),
        ],
      ).toJson();
      expect(json['overbook'], true);
      expect((json['items'] as List).last,
          {'productId': 30, 'quantity': 2.0, 'unitPrice': 75.0});
    });

    AgendaDay day(List<Map<String, dynamic>> items, {int capacity = 1}) {
      final res = AgendaResource(
          id: 1, name: 'Sarah', type: 'STAFF', capacity: capacity);
      return AgendaDay(day: '2026-10-14', resources: [res], reservations: [
        for (var i = 0; i < items.length; i++)
          Reservation.fromJson({
            ..._reservationJson(id: i + 1, code: 'R$i', status: 'BOOKED'),
            'items': [items[i]],
          }),
      ]);
    }

    Map<String, dynamic> it(String s, String e) => {
          'id': s.hashCode,
          'productId': 19,
          'name': 'Coupe',
          'unitPrice': 100,
          'value': 100,
          'startAt': '2026-10-14T${s}:00Z',
          'endAt': '2026-10-14T${e}:00Z',
          'resourceIds': [1],
        };

    test('two bookings on one person at once are one conflict', () {
      final d = day([it('10:00', '10:30'), it('10:15', '10:45'), it('11:00', '11:30')]);
      final groups = findConflicts(d, d.resources);
      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(2));
    });

    test('back to back is not an overlap', () {
      final d = day([it('10:00', '10:30'), it('10:30', '11:00')]);
      expect(findConflicts(d, d.resources), isEmpty);
    });

    test('a room holding two at once is fine with two, not three', () {
      expect(
          findConflicts(
              day([it('10:00', '11:00'), it('10:00', '11:00')], capacity: 2),
              [AgendaResource(id: 1, name: 'Salle', type: 'ROOM', capacity: 2)]),
          isEmpty);
      final three =
          day([it('10:00', '11:00'), it('10:00', '11:00'), it('10:30', '11:30')],
              capacity: 2);
      expect(findConflicts(three, three.resources), hasLength(1));
    });
  });
}
