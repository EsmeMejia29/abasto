import 'package:flutter/material.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'order_chat_screen.dart';
import '../widgets/review_dialog.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
  }

  void _refresh() {
    setState(() {
      _ordersFuture = _fetchOrders();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
    final res = await supabase
        .from('orders')
        .select('''
          *,
          order_items (*)
        ''')
        .eq('restaurant_id', _currentUserId)
        .order('created_at', ascending: false);

    final orders = List<Map<String, dynamic>>.from(res);

    final supplierIds = orders
        .map((o) => o['supplier_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    if (supplierIds.isNotEmpty) {
      try {
        final profs = await supabase
            .from('profiles')
            .select('id, business_name, phone')
            .filter('id', 'in', supplierIds);

        final profMap = {
          for (var p in (profs as List<dynamic>))
            p['id'].toString(): p as Map<String, dynamic>
        };

        for (var o in orders) {
          final sId = o['supplier_id']?.toString();
          if (sId != null && profMap.containsKey(sId)) {
            o['supplier_name'] = profMap[sId]!['business_name'];
            o['supplier_phone'] = profMap[sId]!['phone'];
          }
        }
      } catch (_) {}
    }

    return orders;
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'entregado':
        return Colors.green;
      case 'enruta':
      case 'en ruta':
        return Colors.blue;
      case 'confirmado':
        return AppColors.tealMint;
      case 'pendiente':
        return Colors.orange;
      case 'cancelado':
        return Colors.red;
      default:
        return AppColors.primaryBlue;
    }
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'enruta':
        return 'En Ruta';
      case 'entregado':
        return 'Entregado';
      case 'confirmado':
        return 'Confirmado';
      case 'pendiente':
        return 'Pendiente';
      default:
        return status;
    }
  }

  void _showTimelineDialog(Map<String, dynamic> order) {
    final history = (order['status_history'] as List<dynamic>?) ?? [];
    final createdAt = order['created_at'] != null
        ? DateTime.tryParse(order['created_at'].toString())?.toLocal()
        : null;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Historial: ${order['code']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            if (createdAt != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.add_shopping_cart, color: Colors.orange),
                title: const Text('Pedido Realizado (Pendiente)',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                ),
              ),
            if (history.isNotEmpty)
              ...history.map((h) {
                final st = h['status']?.toString() ?? '';
                final dt = h['changed_at'] != null
                    ? DateTime.tryParse(h['changed_at'].toString())?.toLocal()
                    : null;
                final dtStr = dt != null
                    ? '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                    : '';

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    st == 'entregado'
                        ? Icons.check_circle
                        : (st == 'enRuta' ? Icons.local_shipping : Icons.sync),
                    color: _getStatusColor(st),
                  ),
                  title: Text(
                    'Cambio a: ${_formatStatus(st)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    h['note'] != null && h['note'].toString().isNotEmpty
                        ? '$dtStr • ${h['note']}'
                        : dtStr,
                  ),
                );
              }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seguimiento de Pedidos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.shopping_bag_outlined,
                      size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No tienes pedidos en curso.',
                      style: TextStyle(color: AppColors.subtitleGrey)),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              final code = order['code'] ?? 'ORD-000';
              final supplierName = order['supplier_name'] ?? 'PRUEBA';
              final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
              final status = order['status'] ?? 'pendiente';
              final items = (order['order_items'] as List<dynamic>?) ?? [];

              return Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.storefront,
                                      size: 14, color: AppColors.primaryBlue),
                                  const SizedBox(width: 4),
                                  Text(
                                    supplierName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _showTimelineDialog(order),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color:
                                    _getStatusColor(status).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _formatStatus(status),
                                    style: TextStyle(
                                      color: _getStatusColor(status),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.history,
                                      size: 14,
                                      color: _getStatusColor(status)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      ...items.map((it) {
                        final pName = it['product_name'] ?? 'Insumo';
                        final qty = it['quantity'] ?? 1;
                        final price =
                            (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('$qty x $pName',
                                  style: const TextStyle(fontSize: 13)),
                              Text('\$${(qty * price).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        );
                      }),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Pago contra entrega',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.subtitleGrey)),
                          Text(
                            'Total: \$${total.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showTimelineDialog(order),
                              icon: const Icon(Icons.access_time, size: 16),
                              label: const Text('Trazabilidad'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                              ),
                              onPressed: () {
                                final orderObj = OrderModel(
                                  id: order['id'].toString(),
                                  code: code,
                                  restaurantName: 'Mi Restaurante',
                                  supplierName: supplierName,
                                  supplierPhone: order['supplier_phone'] ?? '',
                                  items: items
                                      .map((i) => OrderItem(
                                            productName:
                                                i['product_name'] ?? '',
                                            quantity: (i['quantity'] as num?)
                                                    ?.toInt() ??
                                                1,
                                            unitPrice: (i['unit_price']
                                                        as num?)
                                                    ?.toDouble() ??
                                                0.0,
                                          ))
                                      .toList(),
                                  totalAmount: total,
                                  status: status == 'enRuta'
                                      ? OrderStatus.enRuta
                                      : (status == 'entregado'
                                          ? OrderStatus.entregado
                                          : OrderStatus.pendiente),
                                  deliveryDate: DateTime.now(),
                                );

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrderChatScreen(
                                      order: orderObj,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.chat_bubble_outline,
                                  color: Colors.white, size: 16),
                              label: const Text('Chat',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                      if (status.toLowerCase() == 'entregado') ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber.shade900,
                              side: BorderSide(color: Colors.amber.shade600),
                            ),
                            icon: const Icon(Icons.star_outline, size: 18),
                            label: const Text('Calificar Distribuidor'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => ReviewDialog(
                                  targetId: order['supplier_id'].toString(),
                                  targetName: supplierName,
                                  targetRole: 'supplier',
                                  orderId: order['id'].toString(),
                                ),
                              ).then((updated) {
                                if (updated == true) _refresh();
                              });
                            },
                          ),
                        ),
                      ],
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