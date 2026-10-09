import 'package:flutter/material.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import 'order_chat_screen.dart';

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
    // 1. Obtener órdenes con sus items
    final ordersResponse = await supabase
        .from('orders')
        .select('*, order_items(*)')
        .order('created_at', ascending: false);

    final ordersData = ordersResponse as List<dynamic>;
    if (ordersData.isEmpty) return [];

    // 2. Obtener nombres y teléfonos de perfiles
    final supplierIds =
        ordersData.map((o) => o['supplier_id'].toString()).toSet().toList();
    final profilesResponse = await supabase
        .from('profiles')
        .select('id, business_name, phone')
        .filter('id', 'in', supplierIds);

    final supplierNameMap = <String, String>{};
    final supplierPhoneMap = <String, String>{};

    for (var prof in profilesResponse as List<dynamic>) {
      final id = prof['id'].toString();
      supplierNameMap[id] = prof['business_name'] ?? 'Proveedor';
      supplierPhoneMap[id] = prof['phone'] ?? '+503 7000-0000';
    }

    return ordersData.map((order) {
      final sId = order['supplier_id']?.toString() ?? '';
      return OrderModel.fromMap(
        order as Map<String, dynamic>,
        supplierNameOverride: supplierNameMap[sId],
        supplierPhoneOverride: supplierPhoneMap[sId],
      );
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
        return 'Entregado';
      case OrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  void _showContactInfoDialog(OrderModel order) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(order.supplierName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Datos directos del distribuidor:',
              style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone, color: AppColors.primaryBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  order.supplierPhone,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Asociado a tu pedido: ${order.code}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderChatScreen(order: order),
                ),
              );
            },
            icon: const Icon(Icons.chat, size: 16, color: Colors.white),
            label: const Text('Abrir Chat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                child: Text('Error al cargar pedidos: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
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
                  const Text('No hay pedidos activos en curso.',
                      style: TextStyle(color: AppColors.subtitleGrey)),
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
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.navyDark),
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
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.navyDark),
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
                              Text('${item.quantity}x ${item.productName}',
                                  style: const TextStyle(fontSize: 13)),
                              Text('\$${item.total.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
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
                            style: TextStyle(
                                color: AppColors.subtitleGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Total: \$${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Botones de comunicación directa
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.primaryBlue),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => _showContactInfoDialog(order),
                              icon: const Icon(Icons.phone_outlined, size: 16),
                              label: const Text('Llamar / Info', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderChatScreen(order: order),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_outlined, size: 16),
                              label: const Text('Chat del Pedido', style: TextStyle(fontSize: 12)),
                            ),
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