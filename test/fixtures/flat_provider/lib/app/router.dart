import 'package:go_router/go_router.dart';
import '../features/products/products_page.dart';

final router = GoRouter(
  routes: [GoRoute(path: '/', builder: (_, __) => const ProductsPage())],
);
