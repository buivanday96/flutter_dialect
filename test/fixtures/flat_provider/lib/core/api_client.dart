import 'package:dio/dio.dart';

class ApiClient {
  ApiClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;
  Future<dynamic> get(String path) async =>
      (await _dio.get<dynamic>(path)).data;
}
