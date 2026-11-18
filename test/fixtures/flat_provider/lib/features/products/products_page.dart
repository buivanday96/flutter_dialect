import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'products_controller.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Text('${context.watch<ProductsController>().items.length}');
}
