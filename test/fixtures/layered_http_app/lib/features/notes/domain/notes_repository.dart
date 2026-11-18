import 'note.dart';

abstract interface class NotesRepository {
  Future<List<Note>> list();
}
