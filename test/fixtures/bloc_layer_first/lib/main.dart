import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'blocs/weather_cubit.dart';
import 'injection.dart';
import 'screens/weather_screen.dart';

void main() {
  configureDependencies();
  runApp(
    BlocProvider(
      create: (_) => WeatherCubit(),
      child: const MaterialApp(home: WeatherScreen()),
    ),
  );
}
