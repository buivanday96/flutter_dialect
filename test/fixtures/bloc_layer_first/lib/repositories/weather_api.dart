import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';
import '../models/weather.dart';

part 'weather_api.g.dart';

@RestApi()
abstract class WeatherApi {
  factory WeatherApi(Dio dio) = _WeatherApi;
  @GET('/weather')
  Future<Weather> current();
}
