import 'package:dio/dio.dart';

Dio createApiDio({required String baseUrl}) => Dio(BaseOptions(baseUrl: baseUrl));
