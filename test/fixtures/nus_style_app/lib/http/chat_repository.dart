import 'package:nus_style/http/api_client.dart';
import 'package:nus_style/model/chat_message.dart';

class ChatRepository {
  ChatRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<List<ChatMessage>> messages() async {
    final envelope = await _api.get('/api/v1/chat');
    return (envelope.data as List<dynamic>).map((e) => ChatMessage.fromMap(e as Map<String, dynamic>)).toList();
  }
}
