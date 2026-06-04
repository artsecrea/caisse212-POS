import 'package:drift/drift.dart' show Value;

import '../data/database/app_database.dart';
import '../utils/phone_normalizer.dart';

/// Customer table operations that need to enforce phone-uniqueness.
///
/// The Customers table is keyed by `phone_normalized` for dedup. A direct
/// `insert` with a phone that's already in the table produces two rows —
/// which then becomes a reconciliation headache for the sync layer and a
/// confusing search list for the cashier ("which Ali is the right Ali?").
/// All customer create/update paths funnel through [upsertByPhone] so the
/// local DB stays single-row-per-phone.
class CustomerRepository {
  final AppDatabase _db;
  CustomerRepository(this._db);

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

    final existing = await (_db.select(_db.customers)
          ..where((c) => c.phoneNormalized.equals(phoneNorm)))
        .getSingleOrNull();

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
