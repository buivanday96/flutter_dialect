import 'package:dio/dio.dart';
import 'package:nus_style/http/api_envelope.dart';

class ApiClient {
  ApiClient._();

  static final instance = ApiClient._();

  final Dio _dio = Dio();

  Future<ApiEnvelope> get(String path, {Map<String, dynamic>? queryParameters, CancelToken? cancelToken}) =>
      _send('GET', path, queryParameters: queryParameters);

  Future<ApiEnvelope> post(String path, {Object? data, Map<String, dynamic>? queryParameters}) =>
      _send('POST', path, data: data, queryParameters: queryParameters);

  Future<ApiEnvelope> patch(String path, {Object? data, Map<String, dynamic>? queryParameters}) =>
      _send('PATCH', path, data: data, queryParameters: queryParameters);

  Future<ApiEnvelope> delete(String path, {Object? data, Map<String, dynamic>? queryParameters}) =>
      _send('DELETE', path, data: data, queryParameters: queryParameters);

  Future<ApiEnvelope> _send(String method, String path, {Object? data, Map<String, dynamic>? queryParameters}) async {
    final response = await _dio.request<dynamic>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: Options(method: method),
    );
    return ApiEnvelope.decode(response.data);
  }
}
