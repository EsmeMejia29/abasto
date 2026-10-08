class Product {
  final String id;
  final String name;
  final String unit;
  final double price;

  const Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.price,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      unit: map['unit'] ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class Supplier {
  final String id;
  final String name;
  final String category;
  final String location;
  final double rating;
  final int reviewsCount;
  final String deliveryDays;
  final bool offersFinancing;

  const Supplier({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.rating,
    required this.reviewsCount,
    required this.deliveryDays,
    required this.offersFinancing,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return Supplier(
      id: map['profile_id']?.toString() ?? '',
      name: profile?['business_name'] ?? 'Proveedor',
      category: map['category'] ?? '',
      location: map['delivery_coverage'] ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      reviewsCount: (map['reviews_count'] as num?)?.toInt() ?? 0,
      deliveryDays: map['delivery_days'] ?? '',
      offersFinancing: map['offers_financing'] ?? false,
    );
  }
}