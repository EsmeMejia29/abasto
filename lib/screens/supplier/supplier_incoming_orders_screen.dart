import 'package:flutter/material.dart';
import '../../main.dart';
import '../../config/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../models/order.dart';
import '../order_chat_screen.dart';
import '../../widgets/review_dialog.dart';
import '../../widgets/business_info_sheet.dart';

class SupplierIncomingOrdersScreen extends StatefulWidget {
  const SupplierIncomingOrdersScreen({super.key});

  @override
  State<SupplierIncomingOrdersScreen> createState() =>
      _SupplierIncomingOrdersScreenState();
}

class _SupplierIncomingOrdersScreenState
    extends State<SupplierIncomingOrdersScreen> {
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.supplierId;

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
    final userId = _currentUserId;

    String? suppDetailId;
    try {
      final detail = await supabase
          .from('supplier_details')
          .select('profile_id')
          .eq('profile_id', userId)
          .maybeSingle();
      if (detail != null && detail['profile_id'] != null) {
        suppDetailId = detail['profile_id'].toString();
      }
    } catch (_) {}

    final query = supabase.from('orders').select('''
      *,
      order_items (*)
    ''');

    final response = suppDetailId != null
        ? await query
            .or('supplier_id.eq.$userId,supplier_id.eq.$suppDetailId')
            .order('created_at', ascending: false)
        : await query
            .eq('supplier_id', userId)
            .order('created_at', ascending: false);

    final orders = List<Map<String, dynamic>>.from(response);

    final restaurantIds = orders
        .map((o) => o['restaurant_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    if (restaurantIds.isNotEmpty) {
      try {
        final profilesRes = await supabase
            .from('profiles')
            .select('id, business_name, phone, address, nrc_nit')
            .filter('id', 'in', restaurantIds);

        final profileMap = {
          for (var p in (profilesRes as List<dynamic>))
            p['id'].toString(): p as Map<String, dynamic>
        };

        for (var o in orders) {
          final restId = o['restaurant_id']?.toString();
          if (restId != null && profileMap.containsKey(restId)) {
            o['restaurant_name'] = profileMap[restId]!['business_name'];
            o['restaurant_phone'] = profileMap[restId]!['phone'];
            o['restaurant_address'] = profileMap[restId]!['address'];
            o['restaurant_nrc'] = profileMap[restId]!['nrc_nit'];
          } else {
            o['restaurant_name'] = 'Restaurante';
          }
        }
      } catch (_) {}
    }

    return orders;
  }

  Future<void> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      final cur = await supabase
          .from('orders')
          .select('status_history')
          .eq('id', orderId)
          .maybeSingle();

      List<dynamic> history = [];
      if (cur != null && cur['status_history'] != null) {
        history = List<dynamic>.from(cur['status_history']);
      }

      history.add({
        'status': newStatus,
        'changed_at': DateTime.now().toIso8601String(),
        'note': 'Actualizado por distribuidor',
      });

      try {
        await supabase.from('orders').update({
          'status': newStatus,
          'status_history': history,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', orderId);
      } catch (_) {
        await supabase
            .from('orders')
            .update({'status': newStatus}).eq('id', orderId);
      }

      _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado de orden actualizado a: $newStatus'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
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

  OrderStatus _parseToOrderStatus(String status) {
    switch (status.toLowerCase()) {
      case 'enruta':
      case 'en ruta':
        return OrderStatus.enRuta;
      case 'entregado':
        return OrderStatus.entregado;
      case 'confirmado':
        return OrderStatus.confirmado;
      case 'cancelado':
        return OrderStatus.cancelado;
      default:
        return OrderStatus.pendiente;
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
            onPressed: _refresh,
          ),
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
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Error al cargar despachos: ${snapshot.error}',
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
                  Icon(Icons.assignment_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No tienes pedidos pendientes de entrega.',
                    style: TextStyle(
                      color: AppColors.subtitleGrey,
                      fontSize: 15,
                    ),
                  ),
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
              final orderId = order['id']?.toString() ?? '';
              final code = order['code'] ?? 'ORD-000';
              final restaurantName = order['restaurant_name'] ?? 'Restaurante';
              final restaurantId = order['restaurant_id']?.toString() ?? '';
              final totalAmount =
                  (order['total_amount'] as num?)?.toDouble() ?? 0.0;
              final status = order['status'] ?? 'pendiente';
              final items = (order['order_items'] as List<dynamic>?) ?? [];

              return Card(
                elevation: 2,
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
                              const SizedBox(height: 6),
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  BusinessInfoSheet.show(
                                    context,
                                    businessId: restaurantId,
                                    defaultName: restaurantName,
                                    role: 'restaurant',
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.primaryBlue.withOpacity(0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.storefront_outlined,
                                        size: 16,
                                        color: AppColors.primaryBlue,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        restaurantName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primaryBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Text(
                                              'Ver Ficha',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.navyDark,
                                              ),
                                            ),
                                            SizedBox(width: 2),
                                            Icon(
                                              Icons.arrow_forward_ios,
                                              size: 10,
                                              color: AppColors.navyDark,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(status).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _formatStatus(status),
                              style: TextStyle(
                                color: _getStatusColor(status),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      if (items.isNotEmpty) ...[
                        const Text(
                          'Insumos solicitados:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...items.map((item) {
                          final pName = item['product_name'] ?? 'Producto';
                          final qty = item['quantity'] ?? 1;
                          final price =
                              (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('• $qty x $pName',
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
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total orden:',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.subtitleGrey)),
                              Text(
                                '\$${totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  side: const BorderSide(
                                      color: AppColors.primaryBlue),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.chat_bubble_outline,
                                    size: 16),
                                label: const Text('Chat'),
                                onPressed: () {
                                  final orderObj = OrderModel(
                                    id: orderId,
                                    code: code,
                                    restaurantName: restaurantName,
                                    supplierName: 'Mi Distribuidora',
                                    supplierPhone:
                                        order['restaurant_phone'] ?? '',
                                    items: items
                                        .map((i) => OrderItem(
                                              productName:
                                                  i['product_name']?.toString() ??
                                                      'Producto',
                                              quantity: (i['quantity'] as num?)
                                                      ?.toInt() ??
                                                  1,
                                              unitPrice: (i['unit_price']
                                                          as num?)
                                                      ?.toDouble() ??
                                                  0.0,
                                            ))
                                        .toList(),
                                    totalAmount: totalAmount,
                                    status: _parseToOrderStatus(status),
                                    deliveryDate: order['delivery_date'] != null
                                        ? DateTime.tryParse(order['delivery_date']
                                                .toString()) ??
                                            DateTime.now()
                                        : DateTime.now(),
                                    isFinanced: order['is_financed'] ?? false,
                                    installmentsCount:
                                        order['installments_count'] ?? 1,
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
                              ),
                              const SizedBox(width: 8),
                              PopupMenuButton<String>(
                                initialValue: status,
                                onSelected: (newVal) =>
                                    _updateOrderStatus(orderId, newVal),
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'pendiente',
                                    child: Text('Marcar Pendiente'),
                                  ),
                                  PopupMenuItem(
                                    value: 'confirmado',
                                    child: Text('Marcar Confirmado'),
                                  ),
                                  PopupMenuItem(
                                    value: 'enRuta',
                                    child: Text('Marcar En Ruta'),
                                  ),
                                  PopupMenuItem(
                                    value: 'entregado',
                                    child: Text('Marcar Entregado'),
                                  ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryBlue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Estado',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down,
                                          color: Colors.white, size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
                            icon: const Icon(Icons.star_rate, size: 18),
                            label: const Text('Calificar Restaurante'),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => ReviewDialog(
                                  targetId: restaurantId, // El ID de perfil del restaurante
                                  targetName: restaurantName,
                                  targetRole: 'restaurant',
                                  orderId: orderId, // El id de la orden
                                ),
                              ).then((_) => _refresh());
                            }
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