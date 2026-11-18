import '../../core/api_client.dart';
import 'products_models.dart';

class ProductsRepository {
  ProductsRepository(this._api);
  final ApiClient _api;
  Future<List<Product>> list() async => ((await _api.get('/products')) as List)
      .map((e) => Product.fromJson(e as Map<String, dynamic>))
      .toList();
}
