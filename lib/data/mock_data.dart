import '../models/supplier.dart';
import '../models/order.dart';

final List<Supplier> sampleSuppliers = [
  Supplier(
    id: 's1',
    name: 'Distribuidora San José',
    category: 'Verduras y Hortalizas Frescas',
    location: 'Ruta Santa Tecla - Antiguo Cuscatlán',
    rating: 4.8,
    reviewsCount: 38,
    deliveryDays: 'Lunes, Miércoles y Viernes',
    offersFinancing: true,
    catalog: [
      Product(id: 'p1', name: 'Tomate de ensalada', unit: 'Caja 50 lb', price: 22.50),
      Product(id: 'p2', name: 'Cebolla blanca nacional', unit: 'Saco 45 lb', price: 18.00),
      Product(id: 'p3', name: 'Chile verde dulce', unit: 'Ciento', price: 14.00),
      Product(id: 'p4', name: 'Papas de primera', unit: 'Bolsa 100 lb', price: 34.00),
    ],
  ),
  Supplier(
    id: 's2',
    name: 'Lácteos y Quesos El Prado',
    category: 'Lácteos y Derivados',
    location: 'San Salvador y La Libertad',
    rating: 4.9,
    reviewsCount: 52,
    deliveryDays: 'Martes y Jueves',
    offersFinancing: true,
    catalog: [
      Product(id: 'p5', name: 'Quesillo especial para pupusas', unit: 'Bloque 10 lb', price: 26.00),
      Product(id: 'p6', name: 'Crema pura de hacienda', unit: 'Galón', price: 15.50),
      Product(id: 'p7', name: 'Queso duro blando', unit: 'Libra', price: 3.75),
    ],
  ),
  Supplier(
    id: 's3',
    name: 'Carnes de Oriente SV',
    category: 'Carnes, Pollo y Embutidos',
    location: 'Zona Metropolitana San Salvador',
    rating: 4.6,
    reviewsCount: 24,
    deliveryDays: 'Lunes a Sábado',
    offersFinancing: false,
    catalog: [
      Product(id: 'p8', name: 'Pechuga de pollo deshuesada', unit: 'Caja 40 lb', price: 58.00),
      Product(id: 'p9', name: 'Lomito de res clasificado', unit: 'Libra', price: 5.25),
      Product(id: 'p10', name: 'Carne molida especial', unit: 'Libra', price: 3.10),
    ],
  ),
];

final List<OrderModel> sampleOrders = [
  OrderModel(
    id: 'ORD-2026-089',
    supplierName: 'Distribuidora San José',
    date: DateTime.now().subtract(const Duration(hours: 3)),
    status: OrderStatus.enRuta,
    isFinanced: true,
    installments: 2,
    installmentAmount: 20.25,
    items: [
      OrderItem(productName: 'Tomate de ensalada', quantity: 1, unitPrice: 22.50),
      OrderItem(productName: 'Cebolla blanca nacional', quantity: 1, unitPrice: 18.00),
    ],
  ),
  OrderModel(
    id: 'ORD-2026-074',
    supplierName: 'Lácteos y Quesos El Prado',
    date: DateTime.now().subtract(const Duration(days: 2)),
    status: OrderStatus.entregado,
    isFinanced: false,
    installments: 1,
    installmentAmount: 52.00,
    items: [
      OrderItem(productName: 'Quesillo especial para pupusas', quantity: 2, unitPrice: 26.00),
    ],
  ),
];