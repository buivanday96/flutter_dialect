import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;
void main() => runApp(const ProviderScope(child: MaterialApp()));
