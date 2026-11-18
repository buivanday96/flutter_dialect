import 'order.dart';

abstract interface class OrdersRepository {
  Future<List<Order>> list();
}
