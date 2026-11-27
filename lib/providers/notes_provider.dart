import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../domain/services/notes_service.dart';
import '../services/notes_repository.dart';
import 'database_providers.dart';

/// The notes board for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final notesServiceProvider = Provider<NotesService>(
    (ref) => NotesRepository(ref.watch(databaseProvider)));

// Stream of all notes, newest first
final notesStreamProvider = StreamProvider<List<Note>>(
    (ref) => ref.watch(notesServiceProvider).watchAll());

class NoteNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  final NotesService _notes;

  NoteNotifier(this._notes) : super(const AsyncValue.loading()) {
    _load();
  }

  void _load() {
    _notes.watchAll().listen((notes) {
      state = AsyncValue.data(notes);
    });
  }

  Future<void> addNote({
    required String content,
    required String color,
    double posX = 20.0,
    double posY = 20.0,
    double width = 200.0,
    double height = 180.0,
    int? orderId,
    String? orderCode,
  }) =>
      _notes.addNote(
        content: content,
        color: color,
        posX: posX,
        posY: posY,
        width: width,
        height: height,
        orderId: orderId,
        orderCode: orderCode,
      );

  Future<void> updateNote(Note note) => _notes.updateNote(note);

  Future<void> moveNote(int id, double posX, double posY) =>
      _notes.moveNote(id, posX, posY);

  Future<void> resizeNote(int id, double width, double height) =>
      _notes.resizeNote(id, width, height);

  Future<void> deleteNote(int id) => _notes.deleteNote(id);

  Future<void> clearAll() => _notes.clearAll();
}

final noteNotifierProvider =
    StateNotifierProvider<NoteNotifier, AsyncValue<List<Note>>>((ref) {
  return NoteNotifier(ref.watch(notesServiceProvider));
});
