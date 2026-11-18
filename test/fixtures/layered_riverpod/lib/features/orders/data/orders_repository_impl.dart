import 'package:http/http.dart' as http;
import '../domain/order.dart';
import '../domain/orders_repository.dart';

class OrdersRepositoryImpl implements OrdersRepository {
  OrdersRepositoryImpl(this._client);
  final http.Client _client;
  @override
  Future<List<Order>> list() async => [];
}
