import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/pos_log.dart';
import 'app_database.dart';

/// The till's database file, opened the way the app always has.
///
/// Kept out of `app_database.dart` because `path_provider` is a Flutter
/// plugin: the schema has to load without Flutter, in tests, tools and a
/// future hub. Only the app's `databaseProvider` opens this.
LazyDatabase openAppDatabaseConnection() {
  return LazyDatabase(() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, AppDatabase.dbName));

      // Ensure directory exists
      if (!await dbFolder.exists()) {
        await dbFolder.create(recursive: true);
      }
      posLog(">>>>>>>>"+dbFolder.path);

      AppDatabase.openedFile = file;
      return NativeDatabase.createInBackground(file);
    } catch (e) {
      // Fallback: try using executable directory on Windows
      if (Platform.isWindows) {
        try {
          final exePath = Platform.resolvedExecutable;
          final exeDir = File(exePath).parent.path;
          final dataDir = Directory(p.join(exeDir, 'data'));
          if (!await dataDir.exists()) {
            await dataDir.create(recursive: true);
          }
          final file = File(p.join(dataDir.path, AppDatabase.dbName));
          AppDatabase.openedFile = file;
          return NativeDatabase.createInBackground(file);
        } catch (e2) {
          rethrow;
        }
      }
      rethrow;
    }
  });
}
