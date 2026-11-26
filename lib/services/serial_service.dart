import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// Local serial (unit-level stock) operations for serial-tracked products.
///
/// The POS never creates serials — the web dashboard does that at reception.
/// This owns the three things the till needs: answer "is this product tracked",
/// list the units still sellable, and hold a unit while it sits in a basket.
class SerialService {
  final AppDatabase _db;

  SerialService(this._db);

  /// Tracked = the product's flag OR the specific variant's flag. Either side
  /// can turn it on, so a variant of an untracked product is still tracked.
  Future<bool> isTracked({required int productId, int? variantId}) async {
    if (variantId != null) {
      final v = await (_db.select(_db.productVariants)
            ..where((t) => t.id.equals(variantId))
            ..limit(1))
          .getSingleOrNull();
      if (v?.isSerialTracked == true) return true;
    }
    final p = await (_db.select(_db.products)
          ..where((t) => t.id.equals(productId))
          ..limit(1))
        .getSingleOrNull();
    return p?.isSerialTracked ?? false;
  }

  /// Units of [productId] still sellable, oldest id first so stock rotates
  /// FIFO when the cashier just takes the top of the list.
  ///
  /// [excludeIds] drops serials already committed to the basket in this same
  /// order. Reservation already flips `isAvailable`, but an edit of an existing
  /// line re-opens the picker with that line's own serial still held, and it
  /// must not disappear from its own picker.
  Future<List<Serial>> availableFor(int productId,
      {Set<int> excludeIds = const {}}) async {
    final rows = await (_db.select(_db.serials)
          ..where((t) => t.productId.equals(productId) & t.isAvailable.equals(true))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
    if (excludeIds.isEmpty) return rows;
    return rows.where((r) => !excludeIds.contains(r.id)).toList();
  }

  Future<Serial?> byId(int id) => (_db.select(_db.serials)
        ..where((t) => t.id.equals(id))
        ..limit(1))
      .getSingleOrNull();

  /// Serial number by id, so a refund slip names the exact unit going back.
  /// Ids no longer in the cache are simply absent.
  Future<Map<int, String>> serialNumbersByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (_db.select(_db.serials)..where((t) => t.id.isIn(ids)))
        .get();
    return {for (final r in rows) r.id: r.serialNumber};
  }

  /// Resolve a scanned/typed number against the local cache.
  ///
  /// Case-insensitive and whitespace-trimmed: a scanner can emit trailing
  /// whitespace and a cashier typing by hand will not match case exactly.
  /// Returns null when unknown — the caller decides whether to try the server.
  Future<Serial?> byNumber(String raw) async {
    final needle = raw.trim().toLowerCase();
    if (needle.isEmpty) return null;
    final rows = await _db.select(_db.serials).get();
    for (final r in rows) {
      if (r.serialNumber.trim().toLowerCase() == needle) return r;
      if ((r.code ?? '').trim().toLowerCase() == needle) return r;
    }
    return null;
  }

  /// Hold a unit while it sits in a basket, so a second line on this terminal
  /// cannot claim it. Server truth overwrites this on the next catalogue pull,
  /// which is what recovers a crash mid-order.
  Future<void> reserve(int serialId) => _setAvailable(serialId, false);

  /// Give the unit back — line removed, order cancelled, or the cashier changed
  /// the serial on a line.
  Future<void> release(int serialId) => _setAvailable(serialId, true);

  Future<void> releaseAll(Iterable<int> serialIds) async {
    for (final id in serialIds) {
      await release(id);
    }
  }

  Future<void> _setAvailable(int serialId, bool value) async {
    await (_db.update(_db.serials)..where((t) => t.id.equals(serialId)))
        .write(SerialsCompanion(
      isAvailable: Value(value),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// How many units are sellable right now — drives the badge on the product
  /// tile and the "out of stock" guard before the picker even opens.
  Future<int> availableCount(int productId) async {
    final rows = await (_db.select(_db.serials)
          ..where(
              (t) => t.productId.equals(productId) & t.isAvailable.equals(true)))
        .get();
    return rows.length;
  }

  /// Reactive variant for the picker, so another terminal's sale (arriving via
  /// a catalogue pull) removes the unit from an open list.
  Stream<List<Serial>> watchAvailableFor(int productId) =>
      (_db.select(_db.serials)
            ..where(
                (t) => t.productId.equals(productId) & t.isAvailable.equals(true))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .watch();

  /// Units this till sold that went to another order and nobody has said they
  /// have seen yet, newest first.
  Stream<List<SerialConflict>> watchUnacknowledgedConflicts() =>
      (_db.select(_db.serialConflicts)
            ..where((c) => c.acknowledgedAt.isNull())
            ..orderBy([(c) => OrderingTerm.desc(c.detectedAt)]))
          .watch();

  /// Acknowledged, not deleted: somebody will ask what happened to that box
  /// weeks from now. Every row gets the same [at].
  Future<void> acknowledgeConflicts(Iterable<int> ids, DateTime at) async {
    for (final id in ids) {
      await (_db.update(_db.serialConflicts)..where((row) => row.id.equals(id)))
          .write(SerialConflictsCompanion(acknowledgedAt: Value(at)));
    }
  }
}
