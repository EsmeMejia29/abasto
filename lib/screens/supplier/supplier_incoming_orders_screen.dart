import 'package:flutter/material.dart';
import '../../main.dart';
import '../../config/session_manager.dart';
import '../../theme/app_theme.dart';

class SupplierIncomingOrdersScreen extends StatefulWidget {
  const SupplierIncomingOrdersScreen({super.key});

  @override
  State<SupplierIncomingOrdersScreen> createState() => _SupplierIncomingOrdersScreenState();
}

class _SupplierIncomingOrdersScreenState extends State<SupplierIncomingOrdersScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchSupplierOrders();
  }

  Future<List<Map<String, dynamic>>> _fetchSupplierOrders() async {
    final response = await supabase
        .from('orders')
        .select('*, order_items(*), profiles!orders_restaurant_id_fkey(business_name, phone, address)')
        .eq('supplier_id', SessionManager.supplierId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    await supabase.from('orders').update({'status': newStatus}).eq('id', orderId);
    setState(() {
      _ordersFuture = _fetchSupplierOrders();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido actualizado a: $newStatus')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Despacho de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _ordersFuture = _fetchSupplierOrders()),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return const Center(
              child: Text('No tienes pedidos pendientes de entrega.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final restaurant = order['profiles'] as Map<String, dynamic>?;
              final restaurantName = restaurant?['business_name'] ?? 'Restaurante';
              final restaurantAddress = restaurant?['address'] ?? 'Sin dirección';
              final items = (order['order_items'] as List<dynamic>?) ?? [];
              final currentStatus = order['status'] ?? 'pendiente';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(order['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Chip(
                            label: Text(currentStatus.toString().toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            backgroundColor: currentStatus == 'entregado' ? AppColors.tealMint.withOpacity(0.2) : Colors.orange.shade100,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Cliente: $restaurantName', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.navyDark)),
                      Text('Destino: $restaurantAddress', style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                      const Divider(height: 20),
                      ...items.map((i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${i['quantity']}x ${i['product_name']}'),
                            Text('\$${(i['total'] as num?)?.toStringAsFixed(2) ?? "0.00"}'),
                          ],
                        ),
                      )),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total a cobrar:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            '\$${(order['total_amount'] as num?)?.toStringAsFixed(2) ?? "0.00"}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primaryBlue),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Acciones de despacho del repartidor/distribuidor
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: currentStatus == 'enRuta'
                                  ? null
                                  : () => _updateOrderStatus(order['id'], 'enRuta'),
                              child: const Text('En Ruta', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.tealMint),
                              onPressed: currentStatus == 'entregado'
                                  ? null
                                  : () => _updateOrderStatus(order['id'], 'entregado'),
                              child: const Text('Entregado', style: TextStyle(fontSize: 12, color: Colors.white)),
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