import 'package:drift/drift.dart';

/// Per-product override of a component group's selection rules.
///
/// The server sends these already merged with the group defaults — a row here
/// is the *effective* rule for that (product, group) pair. Products with no
/// row simply follow the group's own defaults, which is why only overridden
/// pairs are ever stored.
///
/// Columns are nullable so a server that omits a field (an older build, a
/// partial payload) falls back to the group default rather than to a zero
/// that would silently make a group required or uncapped.
class ProductComponentGroups extends Table {
  IntColumn get productId => integer()();
  IntColumn get groupId => integer()();

  /// 'SINGLE' | 'MULTIPLE' | 'QUANTITY'
  TextColumn get selectionType => text().nullable()();
  IntColumn get minSelection => integer().nullable()();
  IntColumn get maxSelection => integer().nullable()();
  IntColumn get freeQuantity => integer().nullable()();
  BoolColumn get isRequired => boolean().nullable()();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  /// JSON array of component ids (from other groups) that make this group
  /// appear on this product, OR'd. Null or empty = always shown. The server
  /// resolves it per product, so this column, never the group's own default,
  /// is what the picker evaluates. See `visibleGroupIds`.
  TextColumn get visibleWhenComponentIds => text().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {productId, groupId};
}
