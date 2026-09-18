import 'package:drift/drift.dart';

/// Platform item id → our product / variant / component.
///
/// A read-only cache of `GET /pos/mappings`, pulled with the catalogue. The POS
/// never writes mappings — the back office owns them — but it must be able to
/// resolve an incoming Glovo/Kooul line **offline**, at the moment an order
/// arrives, without a round trip.
class IntegrationMappings extends Table {
  /// Server row id.
  IntColumn get id => integer()();

  /// `GLOVO` | `KOOUL`.
  TextColumn get provider => text()();

  /// The platform's own id for the item. The match key, and unique per
  /// (provider, business) server-side.
  TextColumn get externalId => text()();

  /// `PRODUCT` | `VARIANT` | `COMPONENT`.
  TextColumn get kind => text().withDefault(const Constant('PRODUCT'))();

  IntColumn get productId => integer().nullable()();
  IntColumn get variantId => integer().nullable()();
  IntColumn get componentId => integer().nullable()();

  /// False = a placeholder the server auto-created when an unknown id first
  /// arrived, with nothing linked yet. Kept rather than skipped so the terminal
  /// can say "the back office knows about this one, it just isn't linked".
  BoolColumn get mapped => boolean().withDefault(const Constant(false))();

  /// Last name the platform sent for it — the only human-readable clue on a
  /// line that cannot be resolved.
  TextColumn get externalName => text().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}
