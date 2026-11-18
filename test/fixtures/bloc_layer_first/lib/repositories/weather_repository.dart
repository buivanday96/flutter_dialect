import 'package:injectable/injectable.dart';
import 'weather_api.dart';

@injectable
class WeatherRepository {
  WeatherRepository(this._api);
  final WeatherApi _api;
}
