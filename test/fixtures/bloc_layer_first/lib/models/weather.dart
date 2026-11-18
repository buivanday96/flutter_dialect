import 'package:json_annotation/json_annotation.dart';

part 'weather.g.dart';

@JsonSerializable()
class Weather {
  Weather(this.temp);
  factory Weather.fromJson(Map<String, dynamic> json) =>
      _$WeatherFromJson(json);
  final double temp;
}
