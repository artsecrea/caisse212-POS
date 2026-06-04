import 'package:drift/drift.dart';

class Customers extends Table {
  IntColumn get id => integer()();
  // First and last name are now OPTIONAL. The phone number is the primary
  // user-visible identifier; the name is just a friendly label. Stored as
  // `text()()` (empty string allowed) so existing rows survive.
  TextColumn get firstName => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get lastName => text().withDefault(const Constant(''))();

  // Phone number — required for new customers. Kept nullable at the DB level
  // so existing pre-migration rows (which may have null phones) can be
  // migrated lazily. Enforced as non-empty in the UI + sync payload.
  TextColumn get phone => text().nullable()();

  // Canonical, formatting-stripped representation of [phone] used as the
  // dedup key on the server side (and via a partial UNIQUE index locally).
  // Format: `<countryCode><subscriberDigits>` with no spaces / dashes /
  // leading zeros. e.g. "0600000000" → "212600000000".
  TextColumn get phoneNormalized => text().nullable()();

  TextColumn get email => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

