/// Models for the reservations contract (`/api/pos/reservations`, backend
/// V198). A reservation is independent from orders: a customer and a few
/// services, each with its own time and resources. It becomes an order only
/// when the customer is served (see `reservationCode` on the order push).
///
/// Every instant on the wire is UTC with a `Z`. They are parsed to LOCAL
/// [DateTime]s for drawing and sent back as UTC, so a naked wall time never
/// leaves this app (the server would read one in the shop's zone).
library;

DateTime? _instant(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

int? _int(dynamic v) =>
    v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
double? _double(dynamic v) =>
    v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// UTC ISO string with `Z`, as every reservation write expects.
String toWireInstant(DateTime t) => t.toUtc().toIso8601String();

/// `yyyy-MM-dd` for a local calendar day.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

DateTime dayStartOf(DateTime d) => DateTime(d.year, d.month, d.day);

// ─── Status ────────────────────────────────────────────────────────────────

abstract final class ReservationStatus {
  static const booked = 'BOOKED';
  static const confirmed = 'CONFIRMED';
  static const arrived = 'ARRIVED';
  static const converted = 'CONVERTED';
  static const noShow = 'NO_SHOW';
  static const canceled = 'CANCELED';

  /// Statuses that occupy their slots. The other two free them.
  static const holdingSlot = {booked, confirmed, arrived, converted};

  /// Statuses a person may set through `PATCH /{id}/status`. CONVERTED is
  /// set only by the order link.
  static const settable = [booked, confirmed, arrived, noShow, canceled];
}

/// Where a reservation sits relative to now. The server sends `timeStatus`,
/// but it is a function of the clock, so it is always derived here as the
/// agenda paints and a ticker repaints as the day moves.
enum BookingTimeStatus { notYet, inProgress, done }

BookingTimeStatus bookingTimeStatus(
  DateTime start,
  DateTime end, {
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  if (at.isBefore(start)) return BookingTimeStatus.notYet;
  if (at.isBefore(end)) return BookingTimeStatus.inProgress;
  return BookingTimeStatus.done;
}

// ─── Reservation ───────────────────────────────────────────────────────────

class ReservationItem {
  final int? id;
  final int productId;
  final int? variantId;

  /// Booking-time snapshot, "Product — Variant".
  final String name;
  final double quantity;

  /// Booking-time unit price: no discount, no TVA. Those come from the local
  /// catalogue when the reservation is rung up.
  final double unitPrice;
  final double value;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final List<int> resourceIds;
  final String? note;

  /// False for a retail line (a product sold with the reservation, no time
  /// slot). Its [startAt]/[endAt] are then the reservation's and mean nothing.
  final bool timed;

  const ReservationItem({
    this.id,
    required this.productId,
    this.variantId,
    required this.name,
    this.quantity = 1,
    required this.unitPrice,
    required this.value,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    this.resourceIds = const [],
    this.note,
    this.timed = true,
  });

  factory ReservationItem.fromJson(
    Map<String, dynamic> j, {
    DateTime? fallback,
  }) {
    final rawStart = _instant(j['startAt']);
    final start = rawStart ?? fallback ?? DateTime.now();
    final end = _instant(j['endAt']) ?? start;
    // V199 says it outright (SERVICE | ADDON); older payloads are read
    // from the times.
    final kind = _str(j['kind'])?.toUpperCase();
    return ReservationItem(
      timed: kind == null
          ? rawStart != null && end.isAfter(start)
          : kind != 'ADDON',
      id: _int(j['id']),
      productId: _int(j['productId']) ?? 0,
      variantId: _int(j['variantId']),
      name: _str(j['name']) ?? '#${j['productId']}',
      quantity: _double(j['quantity']) ?? 1,
      unitPrice: _double(j['unitPrice']) ?? 0,
      value: _double(j['value']) ?? 0,
      startAt: start,
      endAt: end,
      durationMinutes:
          _int(j['durationMinutes']) ?? end.difference(start).inMinutes,
      resourceIds: (j['resourceIds'] is List)
          ? (j['resourceIds'] as List).map(_int).whereType<int>().toList()
          : const [],
      note: _str(j['note']),
    );
  }
}

class ReservationCustomer {
  final int? id;
  final String? name;
  final String? phone;

  const ReservationCustomer({this.id, this.name, this.phone});

  factory ReservationCustomer.fromJson(Map<String, dynamic> j) =>
      ReservationCustomer(
        id: _int(j['id']),
        name: _str(j['name']),
        phone: _str(j['phone']),
      );

  String get label => name ?? phone ?? '';
}

class Reservation {
  final int id;
  final String code;
  final String status;
  final String? source;
  final ReservationCustomer? customer;
  final DateTime startAt;
  final DateTime endAt;
  final double value;
  final String? note;
  final String? internalNote;
  final int? orderId;
  final String? orderCode;
  final String? cancelReason;
  final List<ReservationItem> items;

  /// The server's JSON, kept verbatim for the offline cache.
  final Map<String, dynamic> raw;

  const Reservation({
    required this.id,
    required this.code,
    required this.status,
    this.source,
    this.customer,
    required this.startAt,
    required this.endAt,
    required this.value,
    this.note,
    this.internalNote,
    this.orderId,
    this.orderCode,
    this.cancelReason,
    this.items = const [],
    this.raw = const {},
  });

  factory Reservation.fromJson(Map<String, dynamic> j) {
    final headStart = _instant(j['startAt']);
    final items =
        _maps(j['items'])
            .map((m) => ReservationItem.fromJson(m, fallback: headStart))
            .toList()
          // Timed services in time order, retail lines after them.
          ..sort(
            (a, b) => a.timed != b.timed
                ? (a.timed ? -1 : 1)
                : a.startAt.compareTo(b.startAt),
          );
    final timed = items.where((i) => i.timed).toList();
    final start =
        headStart ?? (timed.isEmpty ? DateTime.now() : timed.first.startAt);
    final end =
        _instant(j['endAt']) ??
        (timed.isEmpty
            ? start
            : timed.map((i) => i.endAt).reduce((a, b) => a.isAfter(b) ? a : b));
    final customer = j['customer'] is Map
        ? ReservationCustomer.fromJson(_map(j['customer']))
        : null;
    return Reservation(
      id: _int(j['id']) ?? 0,
      code: _str(j['code']) ?? '',
      status: _str(j['status']) ?? ReservationStatus.booked,
      source: _str(j['source']),
      customer: customer,
      startAt: start,
      endAt: end,
      value:
          _double(j['value']) ?? items.fold<double>(0, (s, i) => s + i.value),
      note: _str(j['note']),
      internalNote: _str(j['internalNote']),
      orderId: _int(j['orderId']),
      orderCode: _str(j['orderCode']),
      cancelReason: _str(j['cancelReason']),
      items: items,
      raw: j,
    );
  }

  bool get holdsSlot => ReservationStatus.holdingSlot.contains(status);
  bool get isConverted =>
      status == ReservationStatus.converted || orderCode != null;

  /// Whether this reservation can still be rung up as an order.
  bool get canConvert =>
      !isConverted &&
      items.isNotEmpty &&
      (status == ReservationStatus.booked ||
          status == ReservationStatus.confirmed ||
          status == ReservationStatus.arrived);

  /// CANCELED and NO_SHOW are closed; CONVERTED has its basket locked.
  bool get isEditable =>
      status == ReservationStatus.booked ||
      status == ReservationStatus.confirmed ||
      status == ReservationStatus.arrived;

  BookingTimeStatus timeStatus({DateTime? now}) =>
      bookingTimeStatus(startAt, endAt, now: now);

  bool overlaps(DateTime from, DateTime to) =>
      startAt.isBefore(to) && endAt.isAfter(from);

  String get customerLabel => customer?.label ?? '';
}

// ─── Agenda frame ──────────────────────────────────────────────────────────

class TimeRange {
  final DateTime start;
  final DateTime end;
  const TimeRange(this.start, this.end);

  factory TimeRange.fromJson(Map<String, dynamic> j) {
    final s = _instant(j['start'] ?? j['startAt']) ?? DateTime.now();
    return TimeRange(s, _instant(j['end'] ?? j['endAt']) ?? s);
  }

  bool contains(DateTime from, DateTime to) =>
      !from.isBefore(start) && !to.isAfter(end);
}

/// `[{date, ranges:[{start,end}]}]` → ranges for one shop-zone day.
List<TimeRange> _rangesForDay(dynamic days, String day) {
  for (final d in _maps(days)) {
    if (d['date']?.toString() == day) {
      return _maps(d['ranges']).map(TimeRange.fromJson).toList();
    }
  }
  return const [];
}

class AgendaResource {
  final int id;
  final String name;

  /// STAFF | ROOM | CHAIR | EQUIPMENT | OTHER.
  final String type;
  final String? color;
  final int sortOrder;
  final int capacity;
  final bool isActive;

  /// Null = shared across the tenant's shops (a stylist in two shops).
  final int? businessId;
  final Map<String, dynamic> raw;

  const AgendaResource({
    required this.id,
    required this.name,
    required this.type,
    this.color,
    this.sortOrder = 0,
    this.capacity = 1,
    this.isActive = true,
    this.businessId,
    this.raw = const {},
  });

  factory AgendaResource.fromJson(Map<String, dynamic> j) => AgendaResource(
    id: _int(j['id']) ?? 0,
    name: _str(j['name']) ?? '#${j['id']}',
    type: (_str(j['type']) ?? 'OTHER').toUpperCase(),
    color: _str(j['color']),
    sortOrder: _int(j['sortOrder']) ?? 0,
    capacity: _int(j['capacity']) ?? 1,
    isActive: j['isActive'] as bool? ?? true,
    businessId: _int(j['businessId']),
    raw: j,
  );

  bool get isStaff => type == 'STAFF';

  /// Bookable windows on [day] (`yyyy-MM-dd`).
  List<TimeRange> availabilityOn(String day) =>
      _rangesForDay(raw['availability'], day);
}

class AgendaBlock {
  final int id;
  final int resourceId;

  /// BREAK | ABSENCE | BLOCK.
  final String kind;
  final String? title;
  final DateTime startAt;
  final DateTime endAt;

  const AgendaBlock({
    required this.id,
    required this.resourceId,
    required this.kind,
    this.title,
    required this.startAt,
    required this.endAt,
  });

  factory AgendaBlock.fromJson(Map<String, dynamic> j) {
    final s = _instant(j['startAt']) ?? DateTime.now();
    return AgendaBlock(
      id: _int(j['id']) ?? 0,
      resourceId: _int(j['resourceId']) ?? 0,
      kind: (_str(j['kind']) ?? 'BLOCK').toUpperCase(),
      title: _str(j['title']),
      startAt: s,
      endAt: _instant(j['endAt']) ?? s,
    );
  }
}

/// A shared resource booked by ANOTHER business at that time. Drawn greyed
/// and never clickable; the server already counts it as busy.
class ForeignBusy {
  final int resourceId;
  final DateTime start;
  final DateTime end;

  const ForeignBusy(this.resourceId, this.start, this.end);

  factory ForeignBusy.fromJson(Map<String, dynamic> j) {
    final s = _instant(j['start']) ?? DateTime.now();
    return ForeignBusy(_int(j['resourceId']) ?? 0, s, _instant(j['end']) ?? s);
  }
}

class AgendaDayCount {
  final String date;
  final int count;
  final double value;
  const AgendaDayCount(this.date, this.count, this.value);
}

/// Counts only BOOKED/CONFIRMED/ARRIVED/CONVERTED. [value] is money expected,
/// not taken; it is never shown next to takings.
class AgendaSummary {
  final int count;
  final double value;
  final List<AgendaDayCount> days;

  const AgendaSummary({this.count = 0, this.value = 0, this.days = const []});

  factory AgendaSummary.fromJson(Map<String, dynamic> j) => AgendaSummary(
    count: _int(j['count']) ?? 0,
    value: _double(j['value']) ?? 0,
    days: _maps(j['days'])
        .map(
          (d) => AgendaDayCount(
            d['date']?.toString() ?? '',
            _int(d['count']) ?? 0,
            _double(d['value']) ?? 0,
          ),
        )
        .toList(),
  );

  AgendaDayCount? forDay(String day) =>
      days.where((d) => d.date == day).firstOrNull;
}

/// A service the server counts over its resource's capacity (overbooked,
/// stacked unconfirmed, or clashing with another shop on shared staff).
class ServerConflict {
  final int reservationId;
  final int? itemId;
  final int resourceId;
  final List<int> withReservationIds;

  const ServerConflict(
    this.reservationId,
    this.itemId,
    this.resourceId,
    this.withReservationIds,
  );

  factory ServerConflict.fromJson(Map<String, dynamic> j) => ServerConflict(
    _int(j['reservationId']) ?? 0,
    _int(j['itemId']),
    _int(j['resourceId']) ?? 0,
    (j['withReservationIds'] is List)
        ? (j['withReservationIds'] as List).map(_int).whereType<int>().toList()
        : const [],
  );
}

/// One day of the agenda, ready to draw: the frame plus its reservations.
class AgendaDay {
  final String day;
  final String? zone;
  final List<TimeRange> openHours;
  final List<AgendaResource> resources;
  final List<Reservation> reservations;
  final List<AgendaBlock> blocks;
  final List<ForeignBusy> foreignBusy;

  /// The server's own overlap list; null from a backend that does not send
  /// one (the agenda then works it out locally).
  final List<ServerConflict>? serverConflicts;

  /// When the frame was pulled; null = never pulled for this day.
  final DateTime? fetchedAt;

  const AgendaDay({
    required this.day,
    this.zone,
    this.openHours = const [],
    this.resources = const [],
    this.reservations = const [],
    this.blocks = const [],
    this.foreignBusy = const [],
    this.serverConflicts,
    this.fetchedAt,
  });

  /// Build from a cached day frame (see [AgendaWindow.dayFrame]).
  factory AgendaDay.fromFrame(
    String day,
    Map<String, dynamic> frame,
    List<Reservation> reservations, {
    DateTime? fetchedAt,
  }) {
    final resources = _maps(
      frame['resources'],
    ).map(AgendaResource.fromJson).toList()..sort(_resourceOrder);
    return AgendaDay(
      day: day,
      zone: _str(frame['zone']),
      openHours: _maps(frame['openHours']).map(TimeRange.fromJson).toList(),
      resources: resources,
      reservations: reservations,
      blocks: _maps(frame['blocks']).map(AgendaBlock.fromJson).toList(),
      foreignBusy: _maps(
        frame['foreignBusy'],
      ).map(ForeignBusy.fromJson).toList(),
      serverConflicts: frame.containsKey('conflicts')
          ? _maps(frame['conflicts']).map(ServerConflict.fromJson).toList()
          : null,
      fetchedAt: fetchedAt,
    );
  }
}

/// STAFF first, then the back office's order, then name.
int _resourceOrder(AgendaResource a, AgendaResource b) {
  if (a.isStaff != b.isStaff) return a.isStaff ? -1 : 1;
  final bySort = a.sortOrder.compareTo(b.sortOrder);
  if (bySort != 0) return bySort;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Response of `GET /pos/reservations/agenda`.
class AgendaWindow {
  final String? zone;
  final Map<String, dynamic> raw;
  final List<Reservation> reservations;
  final AgendaSummary summary;

  const AgendaWindow({
    this.zone,
    required this.raw,
    required this.reservations,
    required this.summary,
  });

  factory AgendaWindow.fromJson(Map<String, dynamic> j) => AgendaWindow(
    zone: _str(j['zone']),
    raw: j,
    reservations: _maps(j['reservations']).map(Reservation.fromJson).toList(),
    summary: AgendaSummary.fromJson(_map(j['summary'])),
  );

  /// The part of this window that draws [day] (local calendar day), as JSON
  /// for the day cache: open hours and each resource's availability for that
  /// date, blocks and busy-elsewhere slots that overlap it.
  Map<String, dynamic> dayFrame(DateTime day) {
    final key = dayKey(day);
    final from = dayStartOf(day);
    final to = from.add(const Duration(days: 1));
    bool overlaps(Map<String, dynamic> m, String s, String e) {
      final start = _instant(m[s]);
      final end = _instant(m[e]);
      return start != null &&
          end != null &&
          start.isBefore(to) &&
          end.isAfter(from);
    }

    List<Map<String, dynamic>> dayOnly(dynamic days) =>
        _maps(days).where((d) => d['date']?.toString() == key).toList();

    final openHours = <Map<String, dynamic>>[
      for (final d in dayOnly(raw['openHours'])) ..._maps(d['ranges']),
    ];
    final dayReservationIds = {
      for (final r in _maps(raw['reservations']))
        if (overlaps(r, 'startAt', 'endAt')) _int(r['id']),
    };
    return {
      'zone': zone,
      'openHours': openHours,
      'resources': [
        for (final r in _maps(raw['resources']))
          {...r, 'availability': dayOnly(r['availability'])},
      ],
      'blocks': _maps(
        raw['blocks'],
      ).where((b) => overlaps(b, 'startAt', 'endAt')).toList(),
      'foreignBusy': _maps(
        raw['foreignBusy'],
      ).where((b) => overlaps(b, 'start', 'end')).toList(),
      if (raw.containsKey('conflicts'))
        'conflicts': _maps(raw['conflicts'])
            .where((c) => dayReservationIds.contains(_int(c['reservationId'])))
            .toList(),
    };
  }
}

// ─── Availability ──────────────────────────────────────────────────────────

class SlotItem {
  final int productId;
  final DateTime startAt;
  final DateTime endAt;
  final List<int> resourceIds;

  const SlotItem(this.productId, this.startAt, this.endAt, this.resourceIds);

  factory SlotItem.fromJson(Map<String, dynamic> j) {
    final s = _instant(j['startAt']) ?? DateTime.now();
    return SlotItem(
      _int(j['productId']) ?? 0,
      s,
      _instant(j['endAt']) ?? s,
      (j['resourceIds'] is List)
          ? (j['resourceIds'] as List).map(_int).whereType<int>().toList()
          : const [],
    );
  }
}

/// A free start for the whole basket: the services chained back to back,
/// each with the resources the server would assign.
class AvailabilitySlot {
  final DateTime startAt;
  final DateTime endAt;
  final List<SlotItem> items;

  const AvailabilitySlot(this.startAt, this.endAt, this.items);

  factory AvailabilitySlot.fromJson(Map<String, dynamic> j) {
    final s = _instant(j['startAt']) ?? DateTime.now();
    return AvailabilitySlot(
      s,
      _instant(j['endAt']) ?? s,
      _maps(j['items']).map(SlotItem.fromJson).toList(),
    );
  }
}

// ─── Errors ────────────────────────────────────────────────────────────────

/// A reservation write attempted with no connection. Writes claim slots in
/// the shop's one diary, so they are never queued.
class OfflineReservationException implements Exception {
  const OfflineReservationException();
  @override
  String toString() => 'Reconnect to change reservations';
}

/// `409`: SLOT_TAKEN (a resource is already booked) or NO_RESOURCE_FREE (no
/// resource of a type is free). [message] is staff-readable as sent. The
/// right answer is to refresh and pick again, never to retry the same slot.
class ReservationConflict implements Exception {
  final String message;
  final String? code;
  final int? resourceId;
  final String? resourceType;

  /// Index in the request's `items`.
  final int? itemIndex;

  /// The signed-in user may book it anyway (a manager): resend the same
  /// request with `overbook: true` once they confirm.
  final bool overbookable;

  const ReservationConflict({
    required this.message,
    this.code,
    this.resourceId,
    this.resourceType,
    this.itemIndex,
    this.overbookable = false,
  });

  factory ReservationConflict.fromJson(Map<String, dynamic> j) {
    final d = _map(j['details']);
    return ReservationConflict(
      message: _str(j['message']) ?? 'Slot no longer available',
      code: _str(d['code']),
      resourceId: _int(d['resourceId']),
      resourceType: _str(d['type']),
      itemIndex: _int(d['item']),
      overbookable: d['overbookable']?.toString() == 'true',
    );
  }

  @override
  String toString() => message;
}

/// `400`: outside hours, over a block, wrong resource for the service, basket
/// change on a converted reservation, editing a canceled one.
class ReservationValidationError implements Exception {
  final String message;
  const ReservationValidationError(this.message);
  @override
  String toString() => message;
}

// ─── Order link ────────────────────────────────────────────────────────────

abstract final class ReservationLinkStatus {
  static const linked = 'LINKED';

  /// The order saved, but another order holds the reservation: a possible
  /// duplicate sale.
  static const alreadyLinked = 'ALREADY_LINKED';
  static const notFound = 'NOT_FOUND';
}

/// One entry of `reservationLink` / `reservationLinks` on an order push.
class ReservationLink {
  final String? orderCode;
  final String reservationCode;
  final String status;
  final String? linkedOrderCode;

  const ReservationLink({
    this.orderCode,
    required this.reservationCode,
    required this.status,
    this.linkedOrderCode,
  });

  factory ReservationLink.fromJson(
    Map<String, dynamic> j, {
    String? orderCode,
  }) => ReservationLink(
    orderCode: _str(j['orderCode']) ?? orderCode,
    reservationCode: _str(j['reservationCode']) ?? '',
    status: (_str(j['status']) ?? '').toUpperCase(),
    linkedOrderCode: _str(j['linkedOrderCode']),
  );

  /// Reads both shapes: the single PUT's `reservationLink` object (whose
  /// order is [orderCode]) and the bulk's `reservationLinks` array.
  static List<ReservationLink> listFrom(dynamic body, {String? orderCode}) {
    if (body is! Map) return const [];
    final single = body['reservationLink'];
    return [
          if (single is Map)
            ReservationLink.fromJson(
              Map<String, dynamic>.from(single),
              orderCode: orderCode,
            ),
          for (final m in _maps(body['reservationLinks']))
            ReservationLink.fromJson(m),
        ]
        .where((l) => l.reservationCode.isNotEmpty && l.orderCode != null)
        .toList();
  }
}

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
