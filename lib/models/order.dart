enum OrderStatus { pendiente, confirmado, enRuta, entregado, cancelado }

OrderStatus parseOrderStatus(String? status) {
  switch (status) {
    case 'confirmado':
      return OrderStatus.confirmado;
    case 'enRuta':
      return OrderStatus.enRuta;
    case 'entregado':
      return OrderStatus.entregado;
    case 'cancelado':
      return OrderStatus.cancelado;
    case 'pendiente':
    default:
      return OrderStatus.pendiente;
  }
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
      productName: map['product_name'] ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class OrderModel {
  final String id;
  final String code;
  final String supplierName;
  final DateTime date;
  final OrderStatus status;
  final List<OrderItem> items;
  final double totalAmount;

  const OrderModel({
    required this.id,
    required this.code,
    required this.supplierName,
    required this.date,
    required this.status,
    required this.items,
    required this.totalAmount,
  });

  factory OrderModel.fromMap(Map<String, dynamic> map, {String? supplierNameOverride}) {
    final itemsList = (map['order_items'] as List<dynamic>?)
            ?.map((item) => OrderItem.fromMap(item as Map<String, dynamic>))
            .toList() ??
        [];

    return OrderModel(
      id: map['id']?.toString() ?? '',
      code: map['code'] ?? '',
      supplierName: supplierNameOverride ?? 'Proveedor de Alimentos',
      date: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      status: parseOrderStatus(map['status']?.toString()),
      items: itemsList,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }
}