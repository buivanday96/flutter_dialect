class ApiEnvelope {
  const ApiEnvelope({required this.code, required this.message, required this.data});

  factory ApiEnvelope.decode(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return ApiEnvelope(code: map['code'] as int, message: '${map['message']}', data: map['data']);
  }

  final int code;
  final String message;
  final dynamic data;
}
