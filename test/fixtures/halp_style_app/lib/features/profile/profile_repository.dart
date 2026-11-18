import 'package:dio/dio.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<void> ping() => _dio.get<dynamic>('/ping');
}
