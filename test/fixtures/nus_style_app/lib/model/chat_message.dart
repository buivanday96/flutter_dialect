class ChatMessage {
  ChatMessage({required this.text});

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(text: map['text'] as String);

  final String text;

  Map<String, dynamic> toMap() => {'text': text};
}
