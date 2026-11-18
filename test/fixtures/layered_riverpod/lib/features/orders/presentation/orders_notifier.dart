import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/order.dart';

class OrdersNotifier extends StateNotifier<List<Order>> {
  OrdersNotifier() : super(const []);
}
