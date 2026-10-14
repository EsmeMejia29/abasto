import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
  RealtimeChannel? _ordersSubscription;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  // Tarifa del 2% al restaurante
  static const double _platformFeeRate = 0.02;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
    _setupRealtime();
  }

  void _setupRealtime() {
    _ordersSubscription = supabase
        .channel('public:restaurant_orders_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('Actualización en orders: ${payload.eventType}');
            if (mounted) _refresh();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _ordersSubscription?.unsubscribe();
    super.dispose();
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
      case 'en ruta':
        return 'En Ruta';
      case 'entregado':
        return 'Entregado';
      case 'confirmado':
        return 'Confirmado';
      case 'pendiente':
        return 'Pendiente';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  // Wompi Checkout con cálculo del 2%
  Future<void> _payOrderWithWompi(Map<String, dynamic> order) async {
    final code = order['code'] ?? 'ORD-000';
    final subtotal = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final fee = subtotal * _platformFeeRate;
    final totalToPay = double.parse((subtotal + fee).toStringAsFixed(2));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generando enlace de pago seguro en Wompi...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final userEmail = supabase.auth.currentUser?.email ?? 'restaurante@abasto.sv';

      final FunctionResponse response = await supabase.functions.invoke(
        'create-wompi-payment',
        body: {
          'orderId': order['id'],
          'orderCode': code,
          'amount': totalToPay,
          'customerEmail': userEmail,
        },
      );

      final data = response.data;
      if (response.status != 200 || data == null || data['url'] == null) {
        final errorMsg = data != null ? data['error'] : 'Error al procesar con Wompi';
        throw Exception(errorMsg ?? 'No se recibió la URL de pago');
      }

      final String paymentUrl = data['url'];
      final uri = Uri.parse(paymentUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('No se pudo abrir el navegador');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Cancelar Orden
  Future<void> _confirmCancelOrder(Map<String, dynamic> order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cancelar Pedido?'),
        content: Text(
            '¿Estás seguro de que deseas cancelar la orden ${order['code']}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Regresar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Cancelar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final orderId = order['id'].toString();
        final currentHistory = (order['status_history'] as List<dynamic>?) ?? [];
        final newHistory = List<dynamic>.from(currentHistory)
          ..add({
            'status': 'cancelado',
            'changed_at': DateTime.now().toUtc().toIso8601String(),
            'note': 'Cancelado por el restaurante antes de procesar pago',
          });

        await supabase.from('orders').update({
          'status': 'cancelado',
          'status_history': newHistory,
        }).eq('id', orderId);

        _refresh();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El pedido ha sido cancelado exitosamente.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al cancelar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // Modificar cantidades de insumos
  void _showEditOrderModal(Map<String, dynamic> order) {
    final items = List<Map<String, dynamic>>.from(
      ((order['order_items'] as List<dynamic>?) ?? []).map((i) => Map<String, dynamic>.from(i)),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          double newSubtotal = 0;
          for (var it in items) {
            final q = (it['quantity'] as num?)?.toInt() ?? 1;
            final p = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
            newSubtotal += q * p;
          }

          final newFee = newSubtotal * _platformFeeRate;
          final newTotal = newSubtotal + newFee;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Modificar Pedido ${order['code']}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                const Text(
                  'Ajusta las cantidades de los insumos antes de realizar tu pago:',
                  style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final name = item['product_name'] ?? 'Insumo';
                      final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final qty = (item['quantity'] as num?)?.toInt() ?? 1;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('\$${price.toStringAsFixed(2)} c/u',
                                      style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                  onPressed: qty > 1
                                      ? () {
                                          setModalState(() {
                                            item['quantity'] = qty - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text('$qty',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, color: AppColors.primaryBlue),
                                  onPressed: () {
                                    setModalState(() {
                                      item['quantity'] = qty + 1;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal Insumos:', style: TextStyle(color: AppColors.subtitleGrey)),
                    Text('\$${newSubtotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tarifa de Servicio Abasto (2%):',
                        style: TextStyle(color: AppColors.subtitleGrey)),
                    Text('\$${newFee.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryBlue)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Nuevo Total:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('\$${newTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                    onPressed: () async {
                      try {
                        for (var it in items) {
                          await supabase
                              .from('order_items')
                              .update({'quantity': it['quantity']})
                              .eq('id', it['id']);
                        }

                        await supabase
                            .from('orders')
                            .update({'total_amount': newSubtotal})
                            .eq('id', order['id']);

                        Navigator.pop(ctx);
                        _refresh();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Pedido actualizado correctamente.'),
                              backgroundColor: AppColors.tealMint,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: Colors.red),
                        );
                      }
                    },
                    child: const Text('Guardar Cambios',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                leading: const Icon(Icons.add_shopping_cart, color: Colors.orange),
                title: const Text('Pedido Realizado (Pendiente)', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        : (st == 'enRuta'
                            ? Icons.local_shipping
                            : (st == 'cancelado' ? Icons.cancel : Icons.sync)),
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

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final code = order['code'] ?? 'ORD-000';
    final supplierName = order['supplier_name'] ?? 'PRUEBA';
    final subtotal = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    
    // Cálculo porcentual del 2%
    final fee = subtotal * _platformFeeRate;
    final totalConTarifa = subtotal + fee;

    final status = (order['status'] ?? 'pendiente').toString();
    final items = (order['order_items'] as List<dynamic>?) ?? [];
    final isPendiente = status.toLowerCase() == 'pendiente';

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
          mainAxisSize: MainAxisSize.min,
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
                        const Icon(Icons.storefront, size: 14, color: AppColors.primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          supplierName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => _showTimelineDialog(order),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.12),
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
                        Icon(Icons.history, size: 14, color: _getStatusColor(status)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 14),

            // Insumos
            ...items.take(3).map((it) {
              final pName = it['product_name'] ?? 'Insumo';
              final qty = it['quantity'] ?? 1;
              final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$qty x $pName', style: const TextStyle(fontSize: 13)),
                    Text('\$${(qty * price).toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              );
            }),
            if (items.length > 3)
              Text('+ ${items.length - 3} insumos adicionales...',
                  style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.subtitleGrey)),

            const Divider(height: 14),

            // Desglose de precios con tarifa porcentual del 2%
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal Insumos:', style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                Text('\$${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tarifa de Servicio Abasto (2%):',
                    style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                Text('\$${fee.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total a Pagar:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                Text(
                  '\$${totalConTarifa.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Acciones para órdenes pendientes
            if (isPendiente) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () => _showEditOrderModal(order),
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: const Text('Modificar', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => _confirmCancelOrder(order),
                      icon: const Icon(Icons.cancel_outlined, size: 15),
                      label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text('Pagar con Wompi (\$${totalConTarifa.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _payOrderWithWompi(order),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Botones de Trazabilidad y Chat
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
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                    onPressed: () {
                      final orderObj = OrderModel(
                        id: order['id'].toString(),
                        code: code,
                        restaurantName: 'Mi Restaurante',
                        supplierName: supplierName,
                        supplierPhone: order['supplier_phone'] ?? '',
                        items: items
                            .map((i) => OrderItem(
                                  productName: i['product_name'] ?? '',
                                  quantity: (i['quantity'] as num?)?.toInt() ?? 1,
                                  unitPrice: (i['unit_price'] as num?)?.toDouble() ?? 0.0,
                                ))
                            .toList(),
                        totalAmount: totalConTarifa,
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
                          builder: (context) => OrderChatScreen(order: orderObj),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 16),
                    label: const Text('Chat', style: TextStyle(color: Colors.white)),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          final orders = snapshot.data ?? [];
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No tienes pedidos en curso.', style: TextStyle(color: AppColors.subtitleGrey)),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 850;

              if (isDesktop) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        mainAxisExtent: 410,
                      ),
                      itemCount: orders.length,
                      itemBuilder: (context, index) => _buildOrderCard(orders[index]),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _buildOrderCard(orders[index]),
              );
            },
          );
        },
      ),
    );
  }
}