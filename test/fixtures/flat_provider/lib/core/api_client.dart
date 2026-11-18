import 'package:dio/dio.dart';

class ApiClient {
  ApiClient([Dio? dio]) : _dio = dio ?? Dio();
  final Dio _dio;

  Future<dynamic> get(String path, {Map<String, dynamic>? queryParameters}) async =>
      (await _dio.get<dynamic>(path, queryParameters: queryParameters)).data;

  Future<dynamic> post(String path, {Object? data}) async => (await _dio.post<dynamic>(path, data: data)).data;

  Future<dynamic> put(String path, {Object? data}) async => (await _dio.put<dynamic>(path, data: data)).data;

  Future<dynamic> delete(String path) async => (await _dio.delete<dynamic>(path)).data;
}
