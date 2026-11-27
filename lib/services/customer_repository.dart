import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        OrderingTerm,
        StringExpressionOperators,
        Value;

import '../data/database/app_database.dart';
import '../domain/services/customer_service.dart';
import '../utils/phone_normalizer.dart';

/// [CustomerService] on this till's own database: the customer table reads,
/// and the writes that need to enforce phone-uniqueness.
///
/// The Customers table is keyed by `phone_normalized` for dedup. A direct
/// `insert` with a phone that's already in the table produces two rows —
/// which then becomes a reconciliation headache for the sync layer and a
/// confusing search list for the cashier ("which Ali is the right Ali?").
/// All customer create/update paths funnel through [upsertByPhone] so the
/// local DB stays single-row-per-phone.
class CustomerRepository implements CustomerService {
  final AppDatabase _db;
  CustomerRepository(this._db);

  /// Unfiltered: the customer picker narrows it in Dart on the display label,
  /// which is not a column.
  @override
  Stream<List<Customer>> watchAll() => _db.select(_db.customers).watch();

  @override
  Future<List<Customer>> getAll() => _db.select(_db.customers).get();

  @override
  Future<Customer?> getById(int id) =>
      (_db.select(_db.customers)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<List<Customer>> getByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    return (_db.select(_db.customers)..where((c) => c.id.isIn(ids))).get();
  }

  /// The six suggestions under the reservation's customer field.
  /// [lowerText] must already be trimmed and lowercased; names are compared
  /// lowercased, phones as stored.
  @override
  Future<List<Customer>> searchByNameOrPhone(String lowerText) {
    final like = '%$lowerText%';
    return (_db.select(_db.customers)
          ..where((c) =>
              c.firstName.lower().like(like) |
              c.lastName.lower().like(like) |
              c.phone.like(like) |
              c.phoneNormalized.like(like))
          ..limit(6))
        .get();
  }

  /// First row for an already-normalised phone. Duplicate-tolerant, like
  /// [upsertByPhone]'s lookup, but with no ordering: which duplicate comes
  /// back is whatever SQLite returns first, as the external-order review has
  /// always had it.
  @override
  Future<Customer?> findByPhoneNormalized(String phoneNorm) async {
    final matches = await (_db.select(_db.customers)
          ..where((c) => c.phoneNormalized.equals(phoneNorm))
          ..limit(1))
        .get();
    return matches.isEmpty ? null : matches.first;
  }

  /// Upsert a customer keyed by normalized phone.
  ///
  /// - If a row already exists with the same `phoneNormalized`, updates the
  ///   **non-empty** fields on it and returns its existing id. Empty / null
  ///   inputs are left alone — passing `firstName: ''` doesn't clobber a
  ///   stored `"Ali"`, otherwise the second cashier who types only the
  ///   phone would wipe the name the first one had typed.
  /// - Otherwise inserts a new row and returns the new id.
  /// - Returns `null` when [phoneRaw] is blank or normalises to empty —
  ///   a customer without a phone can't be deduped and we treat that as
  ///   "nothing to save".
  ///
  /// [isSynced] controls the resulting row's sync flag:
  ///   - `false` for locally-created customers that still need to push to
  ///     the server (the manual `_AddCustomerDialog` flow).
  ///   - `true` for customers that arrived from the server already (the
  ///     external order queue flow — the server is authoritative).
  @override
  Future<int?> upsertByPhone({
    required String? phoneRaw,
    String firstName = '',
    String lastName = '',
    String? email,
    bool isSynced = false,
  }) async {
    if (phoneRaw == null || phoneRaw.trim().isEmpty) return null;
    final phoneNorm = normalizePhone(phoneRaw);
    if (phoneNorm.isEmpty) return null;

    // Duplicate-tolerant lookup: the table SHOULD be single-row-per-phone, but
    // historical/synced data can hold duplicates. `getSingleOrNull()` THROWS on
    // >1 match ("Too many elements"), which froze the external-order dialogs
    // (the error escaped and the busy flag never reset). Take the oldest row
    // deterministically instead.
    final matches = await (_db.select(_db.customers)
          ..where((c) => c.phoneNormalized.equals(phoneNorm))
          ..orderBy([(c) => OrderingTerm(expression: c.id)])
          ..limit(1))
        .get();
    final existing = matches.isEmpty ? null : matches.first;

    if (existing != null) {
      await (_db.update(_db.customers)
            ..where((c) => c.id.equals(existing.id)))
          .write(CustomersCompanion(
        firstName: firstName.isNotEmpty
            ? Value(firstName)
            : const Value.absent(),
        lastName: lastName.isNotEmpty
            ? Value(lastName)
            : const Value.absent(),
        phone: Value(phoneRaw),
        phoneNormalized: Value(phoneNorm),
        email: (email != null && email.isNotEmpty)
            ? Value(email)
            : const Value.absent(),
        isSynced: Value(isSynced),
        updatedAt: Value(DateTime.now()),
      ));
      return existing.id;
    }

    return await _db.into(_db.customers).insert(
          CustomersCompanion.insert(
            firstName: Value(firstName),
            lastName: Value(lastName),
            phone: Value(phoneRaw),
            phoneNormalized: Value(phoneNorm),
            email: Value((email != null && email.isNotEmpty) ? email : null),
            isSynced: Value(isSynced),
          ),
        );
  }
}
