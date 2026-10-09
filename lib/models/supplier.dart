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
  final String? avatarUrl;
  final String? bannerUrl;
  final String? phone;
  final String? website;
  final String? nrcNit;
  final String businessHours;
  final bool isVerified;
  final String? description;

  const Supplier({
    required this.id,
    required this.name,
    required this.category,
    required this.rating,
    required this.reviewsCount,
    required this.location,
    required this.deliveryDays,
    this.minOrderAmount = 0.0,
    this.avatarUrl,
    this.bannerUrl,
    this.phone,
    this.website,
    this.nrcNit,
    this.businessHours = 'Lunes a Sábado: 7:00 AM - 5:00 PM',
    this.isVerified = true,
    this.description,
  });

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id']?.toString() ?? map['profile_id']?.toString() ?? '',
      name: map['business_name'] ?? map['name'] ?? 'Distribuidor',
      category: map['category'] ?? 'Distribuidora General',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      reviewsCount: (map['reviews_count'] as num?)?.toInt() ?? 0,
      location: map['address'] ?? map['delivery_coverage'] ?? map['location'] ?? 'Santa Tecla, El Salvador',
      deliveryDays: map['delivery_days'] ?? 'Lunes a Sábado',
      minOrderAmount: (map['min_order_amount'] as num?)?.toDouble() ?? 0.0,
      avatarUrl: map['avatar_url'] as String?,
      bannerUrl: map['banner_url'] as String?,
      phone: map['phone'] as String?,
      website: map['website'] as String?,
      nrcNit: map['nrc_nit'] as String?,
      businessHours: map['business_hours'] ?? 'Lunes a Sábado: 7:00 AM - 5:00 PM',
      isVerified: map['is_verified'] ?? true,
      description: map['description'] as String?,
    );
  }
}