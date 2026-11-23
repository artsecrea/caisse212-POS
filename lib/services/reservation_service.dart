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

/// A reservation being created or edited, before it is sent.
class ReservationDraftItem {
  final int? id;
  final int productId;
  final int? variantId;
  final double quantity;
  final DateTime? startAt;
  final DateTime? endAt;

  /// Empty = let the server auto-assign one per required type.
  final List<int> resourceIds;

  /// Agreed price when it is not the catalogue's; null = the server's.
  final double? unitPrice;

  /// False for a retail product sold with the reservation: no time, no
  /// resource, it only rides along to the till.
  final bool timed;

  const ReservationDraftItem({
    this.id,
    required this.productId,
    this.variantId,
    this.quantity = 1,
    this.startAt,
    this.endAt,
    this.resourceIds = const [],
    this.unitPrice,
    this.timed = true,
  });

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'productId': productId,
    if (variantId != null) 'variantId': variantId,
    if (quantity != 1) 'quantity': quantity,
    if (unitPrice != null) 'unitPrice': unitPrice,
    if (timed && startAt != null) 'startAt': toWireInstant(startAt!),
    if (timed && endAt != null) 'endAt': toWireInstant(endAt!),
    if (timed && resourceIds.isNotEmpty) 'resourceIds': resourceIds,
  };
}

class ReservationDraft {
  final DateTime startAt;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final String? internalNote;

  /// BOOKED or CONFIRMED on create; null on edit (the status is kept).
  final String? status;
  final List<ReservationDraftItem> items;

  /// A manager double-booking on purpose, after a 409 that said they may
  /// (`overbookable`). Covers capacity only; hours and blocks stay `force`.
  final bool overbook;

  /// An unconfirmed (BOOKED) booking may sit over others; no permission
  /// needed. The agenda then flags the overlap to sort out, and confirming
  /// it later is refused while it still collides with a firm booking.
  final bool allowOverlap;

  const ReservationDraft({
    required this.startAt,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.note,
    this.internalNote,
    this.status = ReservationStatus.booked,
    required this.items,
    this.overbook = false,
    this.allowOverlap = false,
  });

  Map<String, dynamic> toJson() {
    String? blank(String? s) =>
        (s == null || s.trim().isEmpty) ? null : s.trim();
    return {
      'startAt': toWireInstant(startAt),
      // Never a local-only id (the server answers 404): the caller passes
      // only ids the server knows, else name + phone and the server matches
      // or creates the customer by phone.
      if (customerId != null) 'customerId': customerId,
      if (blank(customerName) != null) 'customerName': blank(customerName),
      if (blank(customerPhone) != null) 'customerPhone': blank(customerPhone),
      if (blank(note) != null) 'note': blank(note),
      if (blank(internalNote) != null) 'internalNote': blank(internalNote),
      if (status != null) 'status': status,
      if (overbook) 'overbook': true,
      if (allowOverlap) 'allowOverlap': true,
      'items': [for (final i in items) i.toJson()],
    };
  }
}

/// The one path through which the POS reads and changes reservations.
///
/// Writes are online only and throw [OfflineReservationException] otherwise:
/// they claim slots in the shop's single diary, and a queued claim would be a
/// promise this till cannot keep. Reads fall back to the last pull, and a
/// reservation held here can be rung up as an order offline; the order sync
/// links it later through `reservationCode`.
class ReservationService {
  final ApiService _api;
  final AppDatabase _db;
  final bool Function() _isOnline;
  final _logger = Logger.instance;

  ReservationService(this._api, this._db, this._isOnline);

  bool get isOnline => _isOnline();

  void _requireOnline() {
    if (!_isOnline()) throw const OfflineReservationException();
  }

  // ── Agenda ──────────────────────────────────────────────────────────────

  /// Pull [from]..[to] (local days, inclusive) and replace the cache for
  /// that window. Returns the server's summary, or null when offline or the
  /// pull failed — the cache is then left as it was.
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

  Future<Reservation> create(ReservationDraft draft) async {
    _requireOnline();
    final r = await _api.createReservation(draft.toJson());
    await _upsert(r);
    return r;
  }

  /// Full replace. Items that keep their `id` are kept server-side.
  Future<Reservation> update(int id, ReservationDraft draft) async {
    _requireOnline();
    final r = await _api.updateReservation(id, draft.toJson());
    await _upsert(r);
    return r;
  }

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

  Future<void> deleteBlock(int id) {
    _requireOnline();
    return _api.deleteAgendaBlock(id);
  }

  /// Best effort, never blocks the sale: tells the server the customer is
  /// here. Skipped offline and when already ARRIVED.
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
  Future<List<Order>> localOrdersFor(String code) =>
      (_db.select(_db.orders)..where(
            (o) =>
                o.reservationCode.equals(code) &
                o.status.isNotValue('CANCELED'),
          ))
          .get();
}
