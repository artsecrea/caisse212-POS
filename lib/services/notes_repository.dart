import 'package:drift/drift.dart' show Value, OrderingTerm;

import '../data/database/app_database.dart';
import '../domain/services/notes_service.dart';

/// [NotesService] on this till's own database.
class NotesRepository implements NotesService {
  final AppDatabase _db;

  NotesRepository(this._db);

  @override
  Stream<List<Note>> watchAll() => (_db.select(_db.notes)
        ..orderBy([(n) => OrderingTerm.desc(n.createdAt)]))
      .watch();

  @override
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

  @override
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

  @override
  Future<void> moveNote(int id, double posX, double posY) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        posX: Value(posX),
        posY: Value(posY),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> resizeNote(int id, double width, double height) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        width: Value(width),
        height: Value(height),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> deleteNote(int id) async {
    await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.notes).go();
  }
}
