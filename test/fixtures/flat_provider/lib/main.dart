import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/router.dart';
import 'features/cart/cart_controller.dart';
import 'features/products/products_controller.dart';

void main() => runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ProductsController()),
      ChangeNotifierProvider(create: (_) => CartController()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ),
);
