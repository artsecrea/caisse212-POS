import 'package:drift/drift.dart';

class Users extends Table {
  IntColumn get id => integer()();
  TextColumn get username => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get password => text()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  TextColumn get type => text()(); // e.g., 'admin', 'cashier', 'waiter'
  TextColumn get imageUrl => text().nullable()();
  TextColumn get accessToken => text().nullable()();
  TextColumn get refreshToken => text().nullable()();
  TextColumn get permissions => text().nullable()(); // JSON string of permissions
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get lastLogin => dateTime().nullable()();
  TextColumn get displayName => text().nullable()();
}

