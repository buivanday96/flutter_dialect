import 'package:dio/dio.dart';
import 'package:halp_style/features/home/home_models.dart';

class HomeRepository {
  HomeRepository(this._dio);

  final Dio _dio;

  Future<HomeCard> load() async {
    final response = await _dio.get<dynamic>('/home');
    return HomeCard.fromMap((response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  }
}
