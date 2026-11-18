import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cart_controller.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Text('${context.watch<CartController>().count}');
}
