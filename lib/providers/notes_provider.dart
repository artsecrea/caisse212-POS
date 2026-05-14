import 'package:drift/drift.dart' show Value, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import 'database_providers.dart';

// Stream of all notes, newest first
final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notes)
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .watch();
});

// Filter: notes linked to a specific order
final notesByOrderProvider = StreamProvider.family<List<Note>, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notes)
        ..where((n) => n.orderId.equals(orderId))
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .watch();
});

class NoteNotifier extends StateNotifier<AsyncValue<List<Note>>> {
  final AppDatabase _db;

  NoteNotifier(this._db) : super(const AsyncValue.loading()) {
    _load();
  }

  void _load() {
    (_db.select(_db.notes)
          ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
        .watch()
        .listen((notes) {
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
  }) async {
    await _db.into(_db.notes).insert(NotesCompanion(
          content: Value(content),
          color: Value(color),
          posX: Value(posX),
          posY: Value(posY),
          width: Value(width),
          height: Value(height),
          orderId: Value(orderId),
          orderCode: Value(orderCode),
          updatedAt: Value(DateTime.now()),
        ));
  }

  Future<void> updateNote(Note note) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(note.id))).write(
      NotesCompanion(
        content: Value(note.content),
        color: Value(note.color),
        posX: Value(note.posX),
        posY: Value(note.posY),
        width: Value(note.width),
        height: Value(note.height),
        orderId: Value(note.orderId),
        orderCode: Value(note.orderCode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> moveNote(int id, double posX, double posY) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        posX: Value(posX),
        posY: Value(posY),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> resizeNote(int id, double width, double height) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        width: Value(width),
        height: Value(height),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNote(int id) async {
    await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }

  Future<void> clearAll() async {
    await _db.delete(_db.notes).go();
  }
}

final noteNotifierProvider =
    StateNotifierProvider<NoteNotifier, AsyncValue<List<Note>>>((ref) {
  final db = ref.watch(databaseProvider);
  return NoteNotifier(db);
});



