import '../../data/database/app_database.dart' show Order, Product, Resource;
import '../models/order_models.dart' show CurrentOrder;
import '../models/reservation_models.dart';

/// The shop's diary — reservations, blocks, availability — and what can be
/// booked, as the screens use them. An interface because the diary is one
/// for the whole shop: standalone, this till reads its cache and writes
/// through the cloud (`LocalReservationService`); linked to a hub, the hub
/// will answer.
abstract interface class ReservationService {
  /// Pull [from]..[to] (local days, inclusive) and replace the cache for
  /// that window. Returns the server's summary, or null when offline or the
  /// pull failed — the cache is then left as it was.
  Future<AgendaSummary?> pullAgenda(DateTime from, DateTime to);

  /// One day from the cache: its frame and every reservation touching it.
  Future<AgendaDay> loadDay(DateTime day);

  /// Search online when possible, the cache otherwise.
  Future<List<Reservation>> search(String query);

  /// The freshest copy of a reservation: the server when online, else the
  /// cache. Null when neither has it.
  Future<Reservation?> refresh(Reservation r);

  Future<List<AvailabilitySlot>> availability({
    required List<int> productIds,
    required DateTime date,
    int days = 1,
    List<int>? resourceIds,
    int? step,
    int? excludeReservationId,
  });

  Future<Reservation> create(ReservationDraft draft);

  /// Full replace. Items that keep their `id` are kept server-side.
  Future<Reservation> update(int id, ReservationDraft draft);

  Future<Reservation> move(
    int id, {
    required DateTime startAt,
    int? resourceId,
    bool overbook = false,
    bool allowOverlap = false,
  });

  Future<Reservation> moveItem(
    int itemId, {
    required DateTime startAt,
    DateTime? endAt,
    List<int>? resourceIds,
    bool overbook = false,
    bool allowOverlap = false,
  });

  Future<Reservation> setStatus(
    int id,
    String status, {
    String? reason,
    bool overbook = false,
  });

  Future<void> addBlock({
    required int resourceId,
    required String kind,
    String? title,
    required DateTime startAt,
    required DateTime endAt,
  });

  Future<void> deleteBlock(int id);

  /// Best effort, never blocks the sale: tells the server the customer is
  /// here. Skipped offline and when already ARRIVED.
  Future<void> markArrivedQuietly(Reservation r);

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
  });

  /// Orders already rung up from [code] on this till — a second conversion
  /// here is almost certainly a mistake.
  Future<List<Order>> localOrdersFor(String code);

  /// Every bookable service: a time-managed, active product with a duration,
  /// as they change. One without a duration cannot be sized into a slot, so
  /// it is not offered.
  Stream<List<Product>> watchBookableServices();

  /// Each service's resource pool (who can do it), as it changes. No entry =
  /// any staff member.
  Stream<Map<int, Set<int>>> watchServicePools();

  /// Retail products (not time-managed) matching [query], to sell alongside
  /// a reservation.
  Future<List<Product>> searchRetailProducts(String query);

  /// The active bookable resources (staff, rooms, chairs, equipment) in the
  /// back office's order, as they change.
  Stream<List<Resource>> watchResources();
}
