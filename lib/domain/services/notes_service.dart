import '../../data/database/app_database.dart' show Note;

/// The sticky notes board. An interface because, linked to a hub, a till
/// shares the hub's board: standalone, it keeps its own (`NotesRepository`).
abstract interface class NotesService {
  /// Every note, newest first, as they change.
  Stream<List<Note>> watchAll();

  Future<void> addNote({
    required String content,
    required String color,
    double posX = 20.0,
    double posY = 20.0,
    double width = 200.0,
    double height = 180.0,
    int? orderId,
    String? orderCode,
  });

  Future<void> updateNote(Note note);

  Future<void> moveNote(int id, double posX, double posY);

  Future<void> resizeNote(int id, double width, double height);

  Future<void> deleteNote(int id);

  Future<void> clearAll();
}
