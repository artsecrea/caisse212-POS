/// Models for the Agenda / Booking backend contract (`/api/pos/...`).
///
/// All timestamps from the server are UTC instants; we parse them and expose
/// LOCAL [DateTime]s so the UI can render and pick directly. On write the API
/// layer converts back and always sends an explicit `Z` — a naked, offset-less
/// timestamp is read by the backend as shop-local, which is not what a device
/// in another zone means.
library;

DateTime? _parseUtcLocal(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

int? _int(dynamic v) => (v as num?)?.toInt();
double? _double(dynamic v) => (v as num?)?.toDouble();

Map<String, dynamic>? _obj(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

String? _fullName(Map<String, dynamic>? m) {
  if (m == null) return null;
  final name = [m['firstName'], m['lastName']]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(' ');
  return name.isEmpty ? null : name;
}

/// A free time window a service can be booked into. Already filtered by the
/// server to windows at least `serviceDurationMinutes` long, so any interval
/// here is bookable as-is — clamp the end to `start + duration` when the user
/// picks an exact start inside a longer interval.
class TimeInterval {
  final DateTime start;
  final DateTime end;

  const TimeInterval({required this.start, required this.end});

  Duration get length => end.difference(start);

  factory TimeInterval.fromJson(Map<String, dynamic> json) {
    return TimeInterval(
      start: _parseUtcLocal(json['start']) ?? DateTime.now(),
      end: _parseUtcLocal(json['end']) ?? DateTime.now(),
    );
  }
}

/// One provider considered for a booking, with their free windows.
///
/// The field is called `waiterId` on the wire for API stability, but it is a
/// **provider** employee id — a distinct staff profile from waiters, and never
/// the same person (the backend enforces one profile per employee).
class AvailabilityCandidate {
  final int waiterId;
  final String waiterName;
  final List<TimeInterval> freeIntervals;

  const AvailabilityCandidate({
    required this.waiterId,
    required this.waiterName,
    required this.freeIntervals,
  });

  bool get hasAvailability => freeIntervals.isNotEmpty;

  factory AvailabilityCandidate.fromJson(Map<String, dynamic> json) {
    final raw = (json['freeIntervals'] as List?) ?? const [];
    return AvailabilityCandidate(
      waiterId: _int(json['waiterId']) ?? 0,
      waiterName: (json['waiterName'] as String?) ?? '',
      freeIntervals: raw
          .whereType<Map>()
          .map((e) => TimeInterval.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Response of `GET /api/pos/availability`.
///
/// **Advisory only.** It accounts for business hours, staff hours and time-off,
/// existing bookings and resource capacity — but the authoritative conflict
/// check is the schedule PATCH, which takes advisory locks. A slot seen free
/// here can still come back 409, and that is expected rather than exceptional.
///
/// An empty [candidates], or a candidate with empty `freeIntervals`, both mean
/// genuinely no availability — not an error.
class AvailabilityResponse {
  final int productId;
  final String date; // shop-zone yyyy-MM-dd echoed back
  final int serviceDurationMinutes;
  final bool requiresResource;
  final List<int> eligibleResourceIds;
  final int? resolvedResourceId;
  final List<AvailabilityCandidate> candidates;

  const AvailabilityResponse({
    required this.productId,
    required this.date,
    required this.serviceDurationMinutes,
    required this.requiresResource,
    required this.eligibleResourceIds,
    required this.resolvedResourceId,
    required this.candidates,
  });

  bool get hasAnyAvailability => candidates.any((c) => c.hasAvailability);

  factory AvailabilityResponse.fromJson(Map<String, dynamic> json) {
    final cands = (json['candidates'] as List?) ?? const [];
    final res = (json['eligibleResourceIds'] as List?) ?? const [];
    return AvailabilityResponse(
      productId: _int(json['productId']) ?? 0,
      date: (json['date'] as String?) ?? '',
      serviceDurationMinutes: _int(json['serviceDurationMinutes']) ?? 0,
      requiresResource: json['requiresResource'] as bool? ?? false,
      eligibleResourceIds:
          res.map((e) => (e as num).toInt()).toList(growable: false),
      resolvedResourceId: _int(json['resolvedResourceId']),
      candidates: cands
          .whereType<Map>()
          .map((e) =>
              AvailabilityCandidate.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Parsed `409` from the schedule PATCH — a provider double-booking (capacity
/// is always 1) or a resource at its capacity.
///
/// The right response is always the same: refresh availability and let staff
/// pick again. Never auto-retry the same slot — the server serialises claims
/// with advisory locks, so a 409 means someone else holds it, not that the
/// request was unlucky.
class ScheduleConflict implements Exception {
  final String message;
  final bool isResource; // false = provider conflict
  final int? current; // resource occupancy at conflict time
  final int? capacity; // resource capacity

  const ScheduleConflict({
    required this.message,
    this.isResource = false,
    this.current,
    this.capacity,
  });

  factory ScheduleConflict.fromJson(Map<String, dynamic> json) {
    final msg = (json['message'] ?? json['error'] ?? 'Slot no longer available')
        .toString();
    return ScheduleConflict(
      message: msg,
      isResource:
          (json['kind'] ?? json['type'])?.toString().toLowerCase() == 'resource' ||
              json['capacity'] != null,
      current: _int(json['current']),
      capacity: _int(json['capacity']),
    );
  }

  @override
  String toString() => message;
}

/// Thrown on a `400` from the schedule PATCH.
///
/// The server rejects: a line of a canceled order, a product that is not
/// time-managed, an end that does not follow the start (and no duration to
/// derive one from), a staff member who is not an active provider, and a
/// resource outside the product's pool.
class ScheduleValidationError implements Exception {
  final String message;
  const ScheduleValidationError(this.message);
  @override
  String toString() => message;
}

/// Where a booking sits relative to now.
///
/// The server sends this on the agenda, but it is purely a function of the
/// clock — a `NOT_YET` pulled at 09:00 is wrong by 09:30. So it is never
/// stored and never read off the wire: the UI derives it as it paints and a
/// ticker repaints as the day moves. There is deliberately no booking-status
/// column anywhere in this app.
enum BookingTimeStatus { notYet, inProgress, done }

/// [BookingTimeStatus] for a booking running from [start] to [end], as of
/// [now] (defaults to the current instant).
///
/// The boundaries are half-open: a booking is IN_PROGRESS from its start until
/// its end, so the instant a slot ends it reads DONE rather than flickering
/// between two states.
BookingTimeStatus bookingTimeStatus(DateTime start, DateTime end,
    {DateTime? now}) {
  final at = now ?? DateTime.now();
  if (at.isBefore(start)) return BookingTimeStatus.notYet;
  if (at.isBefore(end)) return BookingTimeStatus.inProgress;
  return BookingTimeStatus.done;
}

/// One appointment from `GET /api/pos/agenda`.
///
/// Denormalised on purpose: an appointment can belong to an order this
/// terminal has never held — another till's sale, or one taken on the web —
/// so the diary carries its own labels rather than assuming the orders behind
/// it were synced down.
class AgendaBookingDto {
  final int orderProductId;
  final int? orderId;
  final String? orderCode;
  final int? productId;
  final String? productName;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final DateTime planStartAt;
  final DateTime planEndAt;
  final int? planWaiterId;
  final String? planWaiterName;
  final int? planResourceId;
  final String? planResourceName;
  final String? planResourceType;

  /// Net line value: `price × qty × (1 − (discountPct + manualDiscountPct)/100)`,
  /// **without TVA**. Expected money, not realised revenue — a service line only
  /// becomes revenue on its service day.
  final double? value;

  /// Kitchen line state (PENDING/…). A **separate axis** from scheduling and
  /// deliberately ignored by every booking decision here: canceled orders are
  /// excluded server-side, so anything that arrives is live.
  final String? lineState;

  final DateTime? updatedAt;

  const AgendaBookingDto({
    required this.orderProductId,
    this.orderId,
    this.orderCode,
    this.productId,
    this.productName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.note,
    required this.planStartAt,
    required this.planEndAt,
    this.planWaiterId,
    this.planWaiterName,
    this.planResourceId,
    this.planResourceName,
    this.planResourceType,
    this.value,
    this.lineState,
    this.updatedAt,
  });

  /// Nested objects with flat fallbacks: the flat spellings were what an
  /// earlier build of the endpoint sent, and a terminal may meet either.
  factory AgendaBookingDto.fromJson(Map<String, dynamic> json) {
    final order = _obj(json['order']);
    final product = _obj(json['product']);
    final customer = _obj(json['customer']);
    final waiter = _obj(json['waiter']);
    final resource = _obj(json['resource']);

    final start = _parseUtcLocal(json['planStartAt']);
    final end = _parseUtcLocal(json['planEndAt']);

    return AgendaBookingDto(
      orderProductId: _int(json['id'] ?? json['orderProductId']) ?? 0,
      orderId: _int(order?['id'] ?? json['orderId']),
      orderCode: (order?['code'] ?? json['orderCode'])?.toString(),
      productId: _int(product?['id'] ?? json['productId']),
      productName: (product?['name'] ?? json['productName'])?.toString(),
      customerId: _int(customer?['id'] ?? json['clientId']),
      customerName: _fullName(customer) ?? json['customerName']?.toString(),
      customerPhone:
          (customer?['phone'] ?? json['customerPhone'])?.toString(),
      note: json['note']?.toString(),
      planStartAt: start ?? DateTime.now(),
      // A missing end must never produce a backwards window — the grid would
      // draw a negative-height block.
      planEndAt: end ?? start ?? DateTime.now(),
      planWaiterId: _int(waiter?['id'] ?? json['planWaiterId']),
      planWaiterName: _fullName(waiter) ?? json['planWaiterName']?.toString(),
      planResourceId: _int(resource?['id'] ?? json['planResourceId']),
      planResourceName:
          (resource?['name'] ?? json['planResourceName'])?.toString(),
      planResourceType: resource?['type']?.toString(),
      value: _double(json['value']),
      lineState: json['state']?.toString(),
      updatedAt: _parseUtcLocal(json['updatedAt']),
    );
  }

  bool get hasWindow => planEndAt.isAfter(planStartAt);

  /// Whether this booking touches [dayStart, dayEnd) at all.
  ///
  /// The agenda uses overlap semantics, so a booking that began yesterday
  /// evening and runs past midnight belongs on today's grid too.
  bool overlaps(DateTime dayStart, DateTime dayEnd) =>
      planStartAt.isBefore(dayEnd) && planEndAt.isAfter(dayStart);
}

/// Reserved money and headcount for one day of an agenda window.
class AgendaDaySummary {
  final DateTime date;
  final int count;
  final double reservedValue;

  const AgendaDaySummary({
    required this.date,
    required this.count,
    required this.reservedValue,
  });

  factory AgendaDaySummary.fromJson(Map<String, dynamic> json) {
    final raw = json['date']?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return AgendaDaySummary(
      date: parsed ?? DateTime.now(),
      count: _int(json['count']) ?? 0,
      reservedValue: _double(json['reservedValue']) ?? 0,
    );
  }
}

/// The `summary` block of an agenda response.
///
/// [reservedValue] is money **expected**, not taken: the sum of the window's
/// line values, net of discounts and excluding TVA. A service becomes revenue
/// on the day it is performed, so this is a forecast, and showing it beside
/// takings would be double counting.
class AgendaSummary {
  final int count;
  final double reservedValue;
  final List<AgendaDaySummary> days;

  const AgendaSummary({
    this.count = 0,
    this.reservedValue = 0,
    this.days = const [],
  });

  factory AgendaSummary.fromJson(Map<String, dynamic> json) {
    final days = (json['days'] as List?) ?? const [];
    return AgendaSummary(
      count: _int(json['count']) ?? 0,
      reservedValue: _double(json['reservedValue']) ?? 0,
      days: days
          .whereType<Map>()
          .map((e) => AgendaDaySummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// Summary for a window the server did not summarise (an older backend that
  /// answers with a bare array), derived from the items themselves.
  factory AgendaSummary.fromItems(List<AgendaBookingDto> items) {
    final byDay = <DateTime, List<AgendaBookingDto>>{};
    for (final i in items) {
      final day = DateTime(
          i.planStartAt.year, i.planStartAt.month, i.planStartAt.day);
      byDay.putIfAbsent(day, () => []).add(i);
    }
    final days = byDay.entries.map((e) => AgendaDaySummary(
          date: e.key,
          count: e.value.length,
          reservedValue: e.value.fold<double>(0, (s, i) => s + (i.value ?? 0)),
        )).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return AgendaSummary(
      count: items.length,
      reservedValue: items.fold<double>(0, (s, i) => s + (i.value ?? 0)),
      days: days,
    );
  }
}

/// A window of the diary: the bookings and the server's summary of them.
class AgendaPage {
  final List<AgendaBookingDto> items;
  final AgendaSummary summary;

  const AgendaPage({required this.items, required this.summary});

  static const empty = AgendaPage(items: [], summary: AgendaSummary());

  /// Accepts both shapes: `{data: [...], summary: {...}}` and the bare array an
  /// older backend answers with.
  factory AgendaPage.fromResponse(dynamic body) {
    if (body is List) {
      final items = _items(body);
      return AgendaPage(items: items, summary: AgendaSummary.fromItems(items));
    }
    if (body is Map) {
      final map = Map<String, dynamic>.from(body);
      final items = _items(map['data'] ?? map['items'] ?? const []);
      final summary = _obj(map['summary']);
      return AgendaPage(
        items: items,
        summary: summary == null
            ? AgendaSummary.fromItems(items)
            : AgendaSummary.fromJson(summary),
      );
    }
    return empty;
  }

  static List<AgendaBookingDto> _items(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => AgendaBookingDto.fromJson(Map<String, dynamic>.from(e)))
        // A row with no usable window cannot be placed on the grid, and a row
        // with no line id cannot be rescheduled — neither is a booking.
        .where((b) => b.orderProductId > 0 && b.hasWindow)
        .toList();
  }
}
