enum OrderStatus {
  pendiente,
  confirmado,
  enRuta,
  entregado,
  cancelado,
}

class OrderItem {
  final String productName;
  final int quantity;
  final double unitPrice;

  const OrderItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productName: map['product_name']?.toString() ?? 'Producto',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OrderModel {
  final String id;
  final String code;
  final String restaurantName;
  final String supplierName;
  final String supplierPhone;
  final List<OrderItem> items;
  final double totalAmount;
  final OrderStatus status;
  final DateTime deliveryDate;
  final bool isFinanced;
  final int installmentsCount;

  const OrderModel({
    required this.id,
    required this.code,
    required this.restaurantName,
    required this.supplierName,
    this.supplierPhone = '',
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.deliveryDate,
    this.isFinanced = false,
    this.installmentsCount = 1,
  });

  factory OrderModel.fromMap(
    Map<String, dynamic> map, {
    String? supplierNameOverride,
    String? supplierPhoneOverride,
  }) {
    OrderStatus parseStatus(String? s) {
      switch (s?.toLowerCase()) {
        case 'confirmado':
          return OrderStatus.confirmado;
        case 'enruta':
        case 'en ruta':
          return OrderStatus.enRuta;
        case 'entregado':
          return OrderStatus.entregado;
        case 'cancelado':
          return OrderStatus.cancelado;
        default:
          return OrderStatus.pendiente;
      }
    }

    final rawItems = map['order_items'] as List<dynamic>?;
    final parsedItems = rawItems != null
        ? rawItems.map((i) => OrderItem.fromMap(i as Map<String, dynamic>)).toList()
        : <OrderItem>[];

    return OrderModel(
      id: map['id']?.toString() ?? '',
      code: map['code'] ?? 'ORD-000',
      restaurantName: map['restaurant_name'] ?? 'Restaurante',
      supplierName: supplierNameOverride ??
          map['supplier_name'] ??
          'Distribuidor',
      supplierPhone: supplierPhoneOverride ??
          map['supplier_phone'] ??
          map['phone'] ??
          '',
      items: parsedItems,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: parseStatus(map['status']),
      deliveryDate: map['delivery_date'] != null
          ? DateTime.tryParse(map['delivery_date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isFinanced: map['is_financed'] ?? false,
      installmentsCount: map['installments_count'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'restaurant_name': restaurantName,
      'supplier_name': supplierName,
      'supplier_phone': supplierPhone,
      'total_amount': totalAmount,
      'status': status.name,
      'delivery_date': deliveryDate.toIso8601String(),
      'is_financed': isFinanced,
      'installments_count': installmentsCount,
    };
  }
}

// Alias para compatibilidad
typedef Order = OrderModel;