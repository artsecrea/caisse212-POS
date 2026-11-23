import 'package:drift/drift.dart';

/// The business's order tags (schema v60) — short labels made in the back
/// office ("VIP", "URG"), cached here from `GET /pos/order-tags`.
///
/// Server-owned: the till never creates, renames or deletes a tag. The cache is
/// replaced whole on every fetch, so a tag deleted in the back office simply
/// stops existing here too.
class OrderTags extends Table {
  /// The server's id — the one `PUT /pos/orders/{code}/tags` names.
  IntColumn get id => integer()();

  /// 1–6 characters.
  TextColumn get label => text()();

  /// Free text from the back office, usually "#RRGGBB".
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Null = shared by every business of the tenant.
  IntColumn get businessId => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
