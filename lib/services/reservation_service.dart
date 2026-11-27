import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import '../domain/models/reservation_models.dart';
import '../utils/customer_display.dart';
import '../utils/phone_normalizer.dart';
import '../utils/zero_price_tva.dart';
import 'api_service.dart';
import '../domain/services/reservation_service.dart';

/// The one path through which the POS reads and changes reservations.
///
/// Writes are online only and throw [OfflineReservationException] otherwise:
/// they claim slots in the shop's single diary, and a queued claim would be a
/// promise this till cannot keep. Reads fall back to the last pull, and a
/// reservation held here can be rung up as an order offline; the order sync
/// links it later through `reservationCode`.
class LocalReservationService implements ReservationService {
  final ApiService _api;
  final AppDatabase _db;
  final bool Function() _isOnline;
  final _logger = Logger.instance;

  LocalReservationService(this._api, this._db, this._isOnline);

  bool get isOnline => _isOnline();

  void _requireOnline() {
    if (!_isOnline()) throw const OfflineReservationException();
  }

  // ── Agenda ──────────────────────────────────────────────────────────────

  /// Pull [from]..[to] (local days, inclusive) and replace the cache for
  /// that window. Returns the server's summary, or null when offline or the
  /// pull failed — the cache is then left as it was.
  @override
  Future<AgendaSummary?> pullAgenda(DateTime from, DateTime to) async {
    if (!_isOnline()) return null;
    try {
      final window = await _api.fetchReservationAgenda(from: from, to: to);
      await _cacheWindow(window, dayStartOf(from), dayStartOf(to));
      return window.summary;
    } catch (e) {
      _logger.warning('Reservation agenda pull failed: $e');
      return null;
    }
  }

  Future<void> _cacheWindow(
    AgendaWindow window,
    DateTime from,
    DateTime toInclusive,
  ) async {
    final windowEnd = toInclusive.add(const Duration(days: 1));
    final now = DateTime.now();
    await _db.transaction(() async {
      // Overlap, like the endpoint: a reservation that left the window was
      // moved, canceled or deleted, and must not linger in the cache.
      await (_db.delete(_db.cachedReservations)..where(
            (t) =>
                t.startAt.isSmallerThanValue(windowEnd) &
                t.endAt.isBiggerThanValue(from),
          ))
          .go();
      for (final r in window.reservations) {
        await _upsert(r, now);
      }
      for (
        var d = from;
        d.isBefore(windowEnd);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        await _db
            .into(_db.agendaDaySnapshots)
            .insertOnConflictUpdate(
              AgendaDaySnapshotsCompanion.insert(
                day: dayKey(d),
                payload: jsonEncode(window.dayFrame(d)),
                fetchedAt: Value(now),
              ),
            );
      }
    });
  }

  Future<void> _upsert(Reservation r, [DateTime? at]) => _db
      .into(_db.cachedReservations)
      .insertOnConflictUpdate(
        CachedReservationsCompanion.insert(
          id: Value(r.id),
          code: r.code,
          status: r.status,
          startAt: r.startAt,
          endAt: r.endAt,
          customerName: Value(r.customer?.name),
          customerPhone: Value(r.customer?.phone),
          orderCode: Value(r.orderCode),
          payload: jsonEncode(r.raw),
          fetchedAt: Value(at ?? DateTime.now()),
        ),
      );

  /// One day from the cache: its frame and every reservation touching it.
  @override
  Future<AgendaDay> loadDay(DateTime day) async {
    final key = dayKey(day);
    final from = dayStartOf(day);
    final to = from.add(const Duration(days: 1));
    final snap = await (_db.select(
      _db.agendaDaySnapshots,
    )..where((t) => t.day.equals(key))).getSingleOrNull();
    final rows =
        await (_db.select(_db.cachedReservations)
              ..where(
                (t) =>
                    t.startAt.isSmallerThanValue(to) &
                    t.endAt.isBiggerThanValue(from),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.startAt)]))
            .get();
    final reservations = rows.map(_fromRow).whereType<Reservation>().toList();
    if (snap == null) return AgendaDay(day: key, reservations: reservations);
    Map<String, dynamic> frame;
    try {
      frame = Map<String, dynamic>.from(jsonDecode(snap.payload) as Map);
    } catch (_) {
      frame = const {};
    }
    return AgendaDay.fromFrame(
      key,
      frame,
      reservations,
      fetchedAt: snap.fetchedAt,
    );
  }

  Reservation? _fromRow(CachedReservation row) {
    try {
      return Reservation.fromJson(
        Map<String, dynamic>.from(jsonDecode(row.payload) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  /// Search the cached reservations (code, name, phone) — the offline answer
  /// to "find Amina's booking".
  Future<List<Reservation>> searchCached(String query, {int limit = 30}) async {
    final q = '%${query.trim().toLowerCase()}%';
    final rows =
        await (_db.select(_db.cachedReservations)
              ..where(
                (t) =>
                    t.code.lower().like(q) |
                    t.customerName.lower().like(q) |
                    t.customerPhone.like(q),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.startAt)])
              ..limit(limit))
            .get();
    return rows.map(_fromRow).whereType<Reservation>().toList();
  }

  /// Search online when possible, the cache otherwise.
  @override
  Future<List<Reservation>> search(String query) async {
    if (_isOnline()) {
      try {
        final found = await _api.searchReservations(search: query);
        for (final r in found) {
          await _upsert(r);
        }
        return found;
      } catch (e) {
        _logger.warning('Reservation search failed, using cache: $e');
      }
    }
    return searchCached(query);
  }

  /// The freshest copy of a reservation: the server when online, else the
  /// cache. Null when neither has it.
  @override
  Future<Reservation?> refresh(Reservation r) async {
    if (_isOnline()) {
      try {
        final fresh = await _api.fetchReservation(r.id);
        await _upsert(fresh);
        return fresh;
      } catch (e) {
        _logger.warning('Reservation ${r.code} refresh failed: $e');
      }
    }
    final row = await (_db.select(
      _db.cachedReservations,
    )..where((t) => t.id.equals(r.id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  // ── Writes (online only) ────────────────────────────────────────────────

  @override
  Future<List<AvailabilitySlot>> availability({
    required List<int> productIds,
    required DateTime date,
    int days = 1,
    List<int>? resourceIds,
    int? step,
    int? excludeReservationId,
  }) {
    _requireOnline();
    return _api.fetchReservationAvailability(
      productIds: productIds,
      date: date,
      days: days,
      resourceIds: resourceIds,
      step: step,
      excludeReservationId: excludeReservationId,
    );
  }

  @override
  Future<Reservation> create(ReservationDraft draft) async {
    _requireOnline();
    final r = await _api.createReservation(draft.toJson());
    await _upsert(r);
    return r;
  }

  /// Full replace. Items that keep their `id` are kept server-side.
  @override
  Future<Reservation> update(int id, ReservationDraft draft) async {
    _requireOnline();
    final r = await _api.updateReservation(id, draft.toJson());
    await _upsert(r);
    return r;
  }

  @override
  Future<Reservation> move(
    int id, {
    required DateTime startAt,
    int? resourceId,
    bool overbook = false,
    bool allowOverlap = false,
  }) async {
    _requireOnline();
    final r = await _api.moveReservation(
      id,
      startAt: startAt,
      resourceId: resourceId,
      overbook: overbook,
      allowOverlap: allowOverlap,
    );
    await _upsert(r);
    return r;
  }

  @override
  Future<Reservation> moveItem(
    int itemId, {
    required DateTime startAt,
    DateTime? endAt,
    List<int>? resourceIds,
    bool overbook = false,
    bool allowOverlap = false,
  }) async {
    _requireOnline();
    final r = await _api.updateReservationItem(
      itemId,
      startAt: startAt,
      endAt: endAt,
      resourceIds: resourceIds,
      overbook: overbook,
      allowOverlap: allowOverlap,
    );
    await _upsert(r);
    return r;
  }

  @override
  Future<Reservation> setStatus(
    int id,
    String status, {
    String? reason,
    bool overbook = false,
  }) async {
    _requireOnline();
    final r = await _api.setReservationStatus(
      id,
      status,
      reason: reason,
      overbook: overbook,
    );
    await _upsert(r);
    return r;
  }

  @override
  Future<void> addBlock({
    required int resourceId,
    required String kind,
    String? title,
    required DateTime startAt,
    required DateTime endAt,
  }) {
    _requireOnline();
    return _api.createAgendaBlock(
      resourceId: resourceId,
      kind: kind,
      title: title,
      startAt: startAt,
      endAt: endAt,
    );
  }

  @override
  Future<void> deleteBlock(int id) {
    _requireOnline();
    return _api.deleteAgendaBlock(id);
  }

  /// Best effort, never blocks the sale: tells the server the customer is
  /// here. Skipped offline and when already ARRIVED.
  @override
  Future<void> markArrivedQuietly(Reservation r) async {
    if (!_isOnline() || r.status == ReservationStatus.arrived) return;
    try {
      await setStatus(r.id, ReservationStatus.arrived);
    } catch (e) {
      _logger.warning('Marking ${r.code} ARRIVED failed: $e');
    }
  }

  // ── Conversion ──────────────────────────────────────────────────────────

  /// Build the cart for [r]: one line per reserved service, priced like any
  /// line from the local catalogue. The cashier can add, remove and discount
  /// as usual; options (modifiers) are not on reservations and are picked at
  /// checkout. The order push carries [Reservation.code] and the server marks
  /// the reservation CONVERTED.
  ///
  /// Throws [StateError] naming the first service missing from the local
  /// catalogue — it cannot be priced or sent.
  @override
  Future<CurrentOrder> buildCart(
    Reservation r, {
    required String orderType,
    double zeroPriceTvaRate = 0,
  }) async {
    final items = <OrderItem>[];
    for (final it in r.items) {
      final product = await (_db.select(
        _db.products,
      )..where((t) => t.id.equals(it.productId))).getSingleOrNull();
      if (product == null) {
        throw StateError(it.name);
      }
      final variant = it.variantId == null
          ? null
          : await (_db.select(
              _db.productVariants,
            )..where((t) => t.id.equals(it.variantId!))).getSingleOrNull();

      final catalogUnit = variant?.price ?? product.finalPrice;
      final catalogTva = variant?.tvaAmount ?? product.tvaAmount;
      final bookedAtCatalogPrice =
          (it.unitPrice - (variant?.price ?? product.price)).abs() < 0.005;

      // Booked at today's catalogue price: the line is exactly what tapping
      // the product would give (catalogue discount included). Otherwise the
      // agreed price wins: the price changed since booking, or staff set it.
      final unit = bookedAtCatalogPrice ? catalogUnit : it.unitPrice;
      final tva = bookedAtCatalogPrice
          ? catalogTva
          : (catalogUnit > 0
                ? (catalogTva * unit / catalogUnit * 100).roundToDouble() / 100
                : lineUnitTva(
                    catalogPrice: catalogUnit,
                    catalogTva: catalogTva,
                    unitPrice: unit,
                    zeroPriceRate: zeroPriceTvaRate,
                  ));

      items.add(
        OrderItem(
          productId: product.id,
          productName: product.name,
          variantId: variant?.id,
          variantName: variant?.name,
          imageUrl: product.imageUrl,
          finalPrice: unit,
          quantity: it.quantity <= 0 ? 1 : it.quantity,
          tva: tva,
          discount: bookedAtCatalogPrice ? product.discountAmount : 0,
          note: it.note,
          unitName: product.unitName,
        ),
      );
    }

    final customer = await _localCustomer(r.customer);
    return CurrentOrder(
      items: items,
      type: orderType,
      customerId: customer?.id,
      customerName: customer?.displayLabel ?? r.customer?.name,
      customerPhone: customer?.phone ?? r.customer?.phone,
      reservationCode: r.code,
    );
  }

  /// The local customer row for a reservation's customer: by server id, then
  /// by normalised phone.
  Future<Customer?> _localCustomer(ReservationCustomer? c) async {
    if (c == null) return null;
    if (c.id != null) {
      final byId = await (_db.select(
        _db.customers,
      )..where((t) => t.id.equals(c.id!))).getSingleOrNull();
      if (byId != null) return byId;
    }
    final phone = c.phone;
    if (phone == null || phone.trim().isEmpty) return null;
    final norm = normalizePhone(phone);
    if (norm.isEmpty) return null;
    return (_db.select(_db.customers)
          ..where((t) => t.phoneNormalized.equals(norm))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Orders already rung up from [code] on this till — a second conversion
  /// here is almost certainly a mistake.
  @override
  Future<List<Order>> localOrdersFor(String code) =>
      (_db.select(_db.orders)..where(
            (o) =>
                o.reservationCode.equals(code) &
                o.status.isNotValue('CANCELED'),
          ))
          .get();

  // ── What can be booked ──────────────────────────────────────────────────

  /// Every bookable service: a time-managed, active product with a duration,
  /// as they change. One without a duration cannot be sized into a slot, so
  /// it is not offered.
  @override
  Stream<List<Product>> watchBookableServices() => (_db.select(_db.products)
        ..where((p) =>
            p.isPlannable.equals(true) &
            p.isActive.equals(true) &
            p.planDurationMinutes.isNotNull() &
            p.planDurationMinutes.isBiggerThanValue(0))
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .watch();

  /// Each service's resource pool (who can do it), as it changes. No entry =
  /// any staff member.
  @override
  Stream<Map<int, Set<int>>> watchServicePools() =>
      _db.select(_db.productResources).watch().map((rows) {
        final out = <int, Set<int>>{};
        for (final r in rows) {
          out.putIfAbsent(r.productId, () => <int>{}).add(r.resourceId);
        }
        return out;
      });

  /// Retail products (not time-managed) matching [query], to sell alongside
  /// a reservation.
  @override
  Future<List<Product>> searchRetailProducts(String query) {
    final q = '%${query.trim().toLowerCase()}%';
    return (_db.select(_db.products)
          ..where((p) =>
              p.isActive.equals(true) &
              p.isPlannable.equals(false) &
              (p.name.lower().like(q) | p.barcode.like(q)))
          ..orderBy([(p) => OrderingTerm(expression: p.name)])
          ..limit(30))
        .get();
  }

  /// The active bookable resources (staff, rooms, chairs, equipment) in the
  /// back office's order, as they change.
  @override
  Stream<List<Resource>> watchResources() => (_db.select(_db.resources)
        ..where((r) => r.isActive.equals(true))
        ..orderBy([
          (r) => OrderingTerm(expression: r.sortOrder),
          (r) => OrderingTerm(expression: r.name),
        ]))
      .watch();
}
