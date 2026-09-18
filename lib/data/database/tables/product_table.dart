import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get barcode => text().nullable()();
  /// Server-side product reference / SKU (nullable, max 100). Searchable
  /// alongside name and barcode.
  TextColumn get reference => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get description => text().nullable()();
  RealColumn get price => real()();
  /// Purchase/production cost per base unit, from `/pos/products`.
  /// Nullable: the catalogue does not always carry a cost, and 0.0 would
  /// read as "free" in a margin calculation rather than "unknown".
  RealColumn get cost => real().nullable()();
  TextColumn get uom => text().withDefault(const Constant('unit'))();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get stationId => integer().nullable()();
  RealColumn get tvaAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get finalPrice => real()();
  TextColumn get color => text().nullable()();
  // SERVER-owned: the catalogue says this product exists and is sellable.
  // Overwritten by every sync.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  // LOCAL-owned "86": the kitchen has run out right now. Deliberately separate
  // from [isActive] — one is a catalogue fact the backend decides, the other is
  // a service-time fact the kitchen decides, and a sync must not undo it.
  //
  // `_persistProducts` never writes this column, and because the sync upserts
  // (ON CONFLICT DO UPDATE over the supplied columns only) rather than
  // replacing the row, an omitted column keeps its local value. That is what
  // makes an 86 survive a catalogue refresh.
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();
  BoolColumn get isVariant => boolean().withDefault(const Constant(false))();
  /// SERVER-owned: every unit of this product carries a serial, so it cannot
  /// be sold without naming the exact unit. A variant may set its own flag;
  /// tracked = product flag OR variant flag.
  BoolColumn get isSerialTracked =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isPlannable => boolean().withDefault(const Constant(false))();
  IntColumn get planDurationMinutes => integer().nullable()(); // Default plan duration in minutes
  /// MBW / PLU code used for scale-barcode lookup (nullable — only set for weighed products).
  TextColumn get mbwCode => text().nullable()();
  /// Price per kg stored in centimes (nullable — only set for weighed products).
  IntColumn get pricePerKg => integer().nullable()();
  /// Unit label from the server (e.g. "kg", "pcs", "box") — nullable.
  TextColumn get unitName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

