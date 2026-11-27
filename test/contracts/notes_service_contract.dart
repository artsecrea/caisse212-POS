import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/notes_service.dart';

/// What a [NotesService] must do, whoever implements it.
abstract class NotesHarness {
  NotesService get notes;
  Future<void> dispose();
}

void notesServiceContract(String name, Future<NotesHarness> Function() make) {
  group('$name honours the NotesService contract', () {
    late NotesHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a note is added with the board defaults, and listed', () async {
      await h.notes.addNote(content: 'Call the supplier', color: 'yellow');

      final n = (await h.notes.watchAll().first).single;
      expect((n.content, n.color), ('Call the supplier', 'yellow'));
      expect((n.posX, n.posY, n.width, n.height), (20.0, 20.0, 200.0, 180.0));
    });

    test('a note moves, resizes and is rewritten', () async {
      await h.notes.addNote(content: 'a', color: 'blue', orderId: 7);
      final id = (await h.notes.watchAll().first).single.id;

      await h.notes.moveNote(id, 50, 60);
      await h.notes.resizeNote(id, 300, 120);
      var n = (await h.notes.watchAll().first).single;
      expect((n.posX, n.posY, n.width, n.height), (50.0, 60.0, 300.0, 120.0));

      await h.notes.updateNote(n.copyWith(content: 'b'));
      n = (await h.notes.watchAll().first).single;
      expect((n.content, n.orderId), ('b', 7));
    });

    test('notes are deleted one at a time or all at once', () async {
      for (final c in ['1', '2', '3']) {
        await h.notes.addNote(content: c, color: 'green');
      }
      final ids = [for (final n in await h.notes.watchAll().first) n.id];

      await h.notes.deleteNote(ids.first);
      expect(await h.notes.watchAll().first, hasLength(2));

      await h.notes.clearAll();
      expect(await h.notes.watchAll().first, isEmpty);
    });
  });
}
