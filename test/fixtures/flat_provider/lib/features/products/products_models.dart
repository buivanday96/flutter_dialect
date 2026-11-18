class Product {
  Product({required this.id, required this.name});
  factory Product.fromJson(Map<String, dynamic> json) =>
      Product(id: json['id'] as int, name: json['name'] as String);
  final int id;
  final String name;
}
