import 'package:flutter/material.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<OrderModel>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
  }

  Future<List<OrderModel>> _fetchOrders() async {
    // 1. Obtener órdenes con sus ítems (sin join ambiguo a profiles)
    final ordersResponse = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false);

    final ordersData = ordersResponse as List<dynamic>;
    if (ordersData.isEmpty) return [];

    // 2. Obtener los nombres de perfiles de proveedores involucrados
    final supplierIds = ordersData.map((o) => o['supplier_id'].toString()).toSet().toList();
    final profilesResponse = await supabase
        .from('profiles')
        .select('id, business_name')
        .filter('id', 'in', supplierIds);

    final supplierMap = <String, String>{};
    for (var prof in profilesResponse as List<dynamic>) {
      supplierMap[prof['id'].toString()] = prof['business_name'] ?? 'Proveedor';
    }

    // 3. Mapear cada orden con su respectivo nombre de proveedor
    return ordersData.map((order) {
      final sId = order['supplier_id']?.toString();
      final name = supplierMap[sId] ?? 'Proveedor de Alimentos';
      return OrderModel.fromMap(order as Map<String, dynamic>, supplierNameOverride: name);
    }).toList();
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pendiente:
        return Colors.orange;
      case OrderStatus.confirmado:
        return AppColors.primaryBlue;
      case OrderStatus.enRuta:
        return const Color(0xFF6B46C1);
      case OrderStatus.entregado:
        return AppColors.tealMint;
      case OrderStatus.cancelado:
        return Colors.red;
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pendiente:
        return 'Pendiente';
      case OrderStatus.confirmado:
        return 'Confirmado';
      case OrderStatus.enRuta:
        return 'En Ruta de Reparto';
      case OrderStatus.entregado:
        return 'Entregado en Local';
      case OrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _ordersFuture = _fetchOrders();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<OrderModel>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Error al cargar pedidos: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No hay pedidos activos en curso.', style: TextStyle(color: AppColors.subtitleGrey)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 1.5,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.code,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(order.status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getStatusText(order.status),
                              style: TextStyle(
                                color: _getStatusColor(order.status),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.storefront, size: 16, color: AppColors.primaryBlue),
                          const SizedBox(width: 6),
                          Text(
                            order.supplierName,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navyDark),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      ...order.items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${item.quantity}x ${item.productName}', style: const TextStyle(fontSize: 13)),
                              Text('\$${item.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Pago contra entrega',
                            style: TextStyle(color: AppColors.subtitleGrey, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Total: \$${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}