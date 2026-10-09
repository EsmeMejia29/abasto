class Product {
  final String id;
  final String supplierId;
  final String name;
  final String category;
  final String unit;
  final double price;
  final String? imageUrl;
  final bool isAvailable;

  const Product({
    required this.id,
    required this.supplierId,
    required this.name,
    required this.category,
    required this.unit,
    required this.price,
    this.imageUrl,
    this.isAvailable = true,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id']?.toString() ?? '',
      supplierId: map['supplier_id']?.toString() ?? '',
      name: map['name'] ?? '',
      category: map['category'] ?? 'General',
      unit: map['unit'] ?? 'unidad',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['image_url'] as String?,
      isAvailable: map['is_available'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'name': name,
      'category': category,
      'unit': unit,
      'price': price,
      'image_url': imageUrl,
      'is_available': isAvailable,
    };
  }
}

class Supplier {
  final String id;
  final String name;
  final String category;
  final double rating;
  final int reviewsCount;
  final String location;
  final String deliveryDays;
  final double minOrderAmount;

  const Supplier({
    required this.id,
    required this.name,
    required this.category,
    required this.rating,
    required this.reviewsCount,
    required this.location,
    required this.deliveryDays,
    this.minOrderAmount = 0.0,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id']?.toString() ?? map['profile_id']?.toString() ?? '',
      name: map['business_name'] ?? map['name'] ?? 'Distribuidor',
      category: map['category'] ?? 'General',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      reviewsCount: (map['reviews_count'] as num?)?.toInt() ?? 0,
      location: map['delivery_coverage'] ?? map['location'] ?? 'Cobertura Central',
      deliveryDays: map['delivery_days'] ?? 'Lunes a Viernes',
      minOrderAmount: (map['min_order_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'business_name': name,
      'category': category,
      'rating': rating,
      'reviews_count': reviewsCount,
      'delivery_coverage': location,
      'delivery_days': deliveryDays,
      'min_order_amount': minOrderAmount,
    };
  }
}