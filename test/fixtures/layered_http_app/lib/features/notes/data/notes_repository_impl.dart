import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/note.dart';
import '../domain/notes_repository.dart';

class NotesRepositoryImpl implements NotesRepository {
  NotesRepositoryImpl(this._client, this._baseUrl);

  final http.Client _client;
  final Uri _baseUrl;

  @override
  Future<List<Note>> list() async {
    final response = await _client.get(_baseUrl.resolve('notes'));
    return (jsonDecode(response.body) as List<dynamic>).map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
  }
}
