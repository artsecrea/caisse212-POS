import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/notes_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/notes_provider.dart';

import 'contracts/notes_service_contract.dart';

/// The till's own notes table behind [NotesService], driven by the shared
/// contract a hub-backed service will have to pass too.
class _LocalNotesHarness implements NotesHarness {
  _LocalNotesHarness(this.db)
      : container = ProviderContainer(
            overrides: [databaseProvider.overrideWithValue(db)]);

  final AppDatabase db;
  final ProviderContainer container;

  @override
  NotesService get notes => container.read(notesServiceProvider);

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  notesServiceContract('NotesRepository',
      () async => _LocalNotesHarness(AppDatabase.forTesting(NativeDatabase.memory())));
}
