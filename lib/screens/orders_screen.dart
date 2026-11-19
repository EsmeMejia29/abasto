import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'order_chat_screen.dart';
import '../widgets/review_dialog.dart';
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'dart:async';
import '../models/supplier.dart';
import '../utils/csv_exporter.dart';
import 'supplier_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  RealtimeChannel? _ordersSubscription;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

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
        return const Color(0xFF0F766E);
      case 'enruta':
      case 'en ruta':
        return AppColors.primaryBlue;
      case 'confirmado':
        return const Color(0xFF059669);
      case 'pendiente':
        return const Color(0xFFD97706);
      case 'cancelado':
        return const Color(0xFFDC2626);
      default:
        return AppColors.navyDark;
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
        return 'Sin Pagar';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  // Wompi Checkout directo con el totalAmount (ya incluye la tarifa)
  Future<void> _payOrderWithWompi(Map<String, dynamic> order) async {
    final code = order['code'] ?? 'ORD-000';
    final orderId = order['id'].toString();
    final double totalToPay =
        ((order['total_amount'] as num?)?.toDouble() ?? 0.0);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cargando pasarela de pago segura...'),
        duration: Duration(seconds: 2),
      ),
    );

    RealtimeChannel? paymentListener;
    StreamSubscription<html.MessageEvent>? messageSub;
    bool isClosing = false;

    Future<void> handlePaymentSuccess(String txRef) async {
      if (isClosing) return;
      isClosing = true;

      try {
        final currentHistory =
            (order['status_history'] as List<dynamic>?) ?? [];
        final newHistory = List<dynamic>.from(currentHistory)
          ..add({
            'status': 'confirmado',
            'changed_at': DateTime.now().toUtc().toIso8601String(),
            'note':
                'Pago aprobado por Wompi (Ref: $txRef • \$${totalToPay.toStringAsFixed(2)})',
          });

        await supabase.from('orders').update({
          'status': 'confirmado',
          'status_history': newHistory,
        }).eq('id', orderId);
      } catch (_) {}

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '¡Pago verificado por el banco! El pedido $code está Confirmado.'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    try {
      final userEmail =
          supabase.auth.currentUser?.email ?? 'restaurante@abasto.sv';

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
        final errorMsg =
            data != null ? data['error'] : 'Error al procesar con Wompi';
        throw Exception(errorMsg ?? 'No se recibió la URL de pago');
      }

      final String paymentUrl = data['url'];
      final String viewId =
          'wompi-widget-$orderId-${DateTime.now().millisecondsSinceEpoch}';

      ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
        return html.IFrameElement()
          ..src = paymentUrl
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'payment *';
      });

      if (!mounted) return;

      // 1. Escucha cuando Wompi redirige el iframe a abasto-flame.vercel.app con la transacción aprobada
      messageSub = html.window.onMessage.listen((event) {
        final msg = event.data;
        if (msg is Map && msg['type'] == 'WOMPI_PAYMENT_APPROVED') {
          if (msg['orderCode'] == code) {
            final txId = msg['transactionId']?.toString() ?? 'Wompi';
            handlePaymentSuccess(txId);
          }
        }
      });

      // 2. Respaldo en tiempo real por si el Webhook actualiza primero la base de datos
      paymentListener = supabase
          .channel('payment-watch-$orderId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'orders',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: orderId,
            ),
            callback: (payload) {
              final newStatus =
                  payload.newRecord['status']?.toString().toLowerCase();
              if (newStatus == 'confirmado' && mounted && !isClosing) {
                isClosing = true;
                Navigator.of(context, rootNavigator: true).pop();
                _refresh();
              }
            },
          )
          .subscribe();

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: AppColors.navyDark,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: Color(0xFF4ADE80), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Pago Seguro • $code (\$${totalToPay.toStringAsFixed(2)})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: HtmlElementView(viewType: viewId),
                ),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border:
                        Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                      SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Esperando confirmación automática del banco...',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar widget de pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await messageSub?.cancel();
      await paymentListener?.unsubscribe();
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
            child:
                const Text('Sí, Cancelar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final orderId = order['id'].toString();
        final currentHistory =
            (order['status_history'] as List<dynamic>?) ?? [];
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
            SnackBar(
                content: Text('Error al cancelar: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // Modificar cantidades de insumos
  void _showEditOrderModal(Map<String, dynamic> order) {
    final items = List<Map<String, dynamic>>.from(
      ((order['order_items'] as List<dynamic>?) ?? [])
          .map((i) => Map<String, dynamic>.from(i)),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          double newTotal = 0;
          for (var it in items) {
            final q = (it['quantity'] as num?)?.toInt() ?? 1;
            final p = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
            newTotal += q * p;
          }

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
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
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
                  style: TextStyle(
                      fontSize: 12, color: AppColors.subtitleGrey),
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
                      final price =
                          (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                      final qty = (item['quantity'] as num?)?.toInt() ?? 1;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text('\$${price.toStringAsFixed(2)} c/u',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.subtitleGrey)),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: Colors.red),
                                  onPressed: qty > 1
                                      ? () {
                                          setModalState(() {
                                            item['quantity'] = qty - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text('$qty',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      color: AppColors.primaryBlue),
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
                    const Text('Total a Pagar:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('\$${newTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark)),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue),
                    onPressed: () async {
                      try {
                        for (var it in items) {
                          await supabase
                              .from('order_items')
                              .update({'quantity': it['quantity']}).eq(
                                  'id', it['id']);
                        }

                        final double baseSubtotal = double.parse(
                            (newTotal / 1.03).toStringAsFixed(2));
                        final double fee =
                            double.parse((newTotal - baseSubtotal).toStringAsFixed(2));

                        await supabase.from('orders').update({
                          'total_amount': newTotal,
                          'subtotal': baseSubtotal,
                          'platform_fee': fee,
                        }).eq('id', order['id']);

                        Navigator.pop(ctx);
                        _refresh();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Pedido actualizado correctamente.'),
                              backgroundColor: AppColors.tealMint,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                              content: Text('Error al guardar: $e'),
                              backgroundColor: Colors.red),
                        );
                      }
                    },
                    child: const Text('Guardar Cambios',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
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
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Padding(
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
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (createdAt != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.add_shopping_cart, color: Colors.orange),
                            title: const Text('Pedido Realizado', style: TextStyle(fontWeight: FontWeight.bold)),
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
                                        : (st == 'cancelado'
                                            ? Icons.cancel
                                            : Icons.sync)),
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
                ),
              ],
            ),
          ),
        ),
      );
  }

  Future<void> _exportOrdersCsv() async {
    try {
      final orders = await _ordersFuture;
      if (orders.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay pedidos para exportar.')),
          );
        }
        return;
      }

      final rows = orders.map((o) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final sub = (o['subtotal'] as num?)?.toDouble() ??
            double.parse((total / 1.03).toStringAsFixed(2));
        final neto = double.parse((sub / 1.13).toStringAsFixed(2));
        final iva = double.parse((sub - neto).toStringAsFixed(2));
        final fee = (o['platform_fee'] as num?)?.toDouble() ??
            double.parse((total - sub).toStringAsFixed(2));
        return [
          o['code'] ?? '',
          (o['created_at'] ?? '').toString().split('T').first,
          o['supplier_name'] ?? 'Distribuidor',
          _formatStatus((o['status'] ?? '').toString()),
          (o['tax_document_type'] ?? 'factura').toString().toUpperCase(),
          o['dte_generation_code'] ?? 'Pendiente',
          neto.toStringAsFixed(2),
          iva.toStringAsFixed(2),
          fee.toStringAsFixed(2),
          total.toStringAsFixed(2),
        ];
      }).toList();

      CsvExporter.downloadCsv(
        filename: 'Abasto_Compras_Contabilidad_${DateTime.now().year}.csv',
        headers: [
          'Orden',
          'Fecha',
          'Distribuidor',
          'Estado',
          'Tipo DTE',
          'Codigo Generacion DTE',
          'Neto Gravado (\$)',
          'IVA 13% (\$)',
          'Tarifa Abasto 3% (\$)',
          'Total Pagado (\$)',
        ],
        rows: rows,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al exportar CSV: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _repeatOrder(Map<String, dynamic> order) async {
    final supplierId = order['supplier_id']?.toString() ?? '';
    if (supplierId.isEmpty) return;

    final items = (order['order_items'] as List<dynamic>?) ?? [];
    final Map<String, int> initialQty = {};
    for (var it in items) {
      final pid = it['product_id']?.toString() ?? '';
      final q = (it['quantity'] as num?)?.toInt() ?? 0;
      if (pid.isNotEmpty && q > 0) {
        initialQty[pid] = (initialQty[pid] ?? 0) + q;
      }
    }

    try {
      final prof = await supabase
          .from('profiles')
          .select('id, business_name, location, avatar_url, business_hours, is_verified')
          .eq('id', supplierId)
          .maybeSingle();

      final suppDet = await supabase
          .from('supplier_details')
          .select('category, rating, reviews_count')
          .eq('profile_id', supplierId)
          .maybeSingle();

      if (!mounted) return;

      final supplier = Supplier(
        id: supplierId,
        name: prof?['business_name'] ?? order['supplier_name'] ?? 'Distribuidor',
        category: suppDet?['category'] ?? 'Insumos Generales',
        rating: (suppDet?['rating'] as num?)?.toDouble() ?? 5.0,
        reviewsCount: (suppDet?['reviews_count'] as num?)?.toInt() ?? 0,
        location: prof?['location'] ?? 'El Salvador',
        deliveryDays: 'Lunes a Sábado',
        avatarUrl: prof?['avatar_url'],
        businessHours: prof?['business_hours'] ?? 'Lunes a Sábado',
        isVerified: prof?['is_verified'] == true,
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupplierDetailScreen(
            supplier: supplier,
            initialQuantities: initialQty,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo cargar el catálogo: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reportIncidentDialog(Map<String, dynamic> order) async {
    final noteCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reportar Incidencia / Faltante',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Orden ${order['code']} • ${order['supplier_name'] ?? ''}',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.subtitleGrey),
            ),
            const SizedBox(height: 10),
            const Text(
              'Al reportar un faltante o producto dañado, la liquidación de este pedido quedará retenida hasta que el distribuidor lo resuelva contigo.',
              style: TextStyle(fontSize: 12, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Detalle del problema',
                hintText: 'Ej. Faltaron 2 cajas de queso o llegaron dañadas...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () {
              if (noteCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Enviar Reporte',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (submitted == true) {
      try {
        final currentHistory =
            (order['status_history'] as List<dynamic>?) ?? [];
        final newHistory = List<dynamic>.from(currentHistory)
          ..add({
            'status': 'incidencia',
            'changed_at': DateTime.now().toUtc().toIso8601String(),
            'note': 'Incidencia reportada: ${noteCtrl.text.trim()}',
          });

        await supabase.from('orders').update({
          'has_incident': true,
          'incident_status': 'abierta',
          'incident_note': noteCtrl.text.trim(),
          'incident_reported_at': DateTime.now().toUtc().toIso8601String(),
          'status_history': newHistory,
        }).eq('id', order['id']);

        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Incidencia enviada. Liquidación retenida hasta su resolución.'),
              backgroundColor: Colors.deepOrange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al reportar: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final code = order['code'] ?? 'ORD-000';
    final supplierName = order['supplier_name'] ?? 'PRUEBA';
    // El total_amount ya es el precio exacto final pagado por el cliente
    final double totalFinal =
        (order['total_amount'] as num?)?.toDouble() ?? 0.0;

    final status = (order['status'] ?? 'pendiente').toString();
    final items = (order['order_items'] as List<dynamic>?) ?? [];
    final isPendiente = status.toLowerCase() == 'pendiente';

    final statusColor = _getStatusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF001A2C).withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16.5,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.storefront_rounded,
                                size: 13, color: AppColors.primaryBlue),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              supplierName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _showTimelineDialog(order),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.11),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatStatus(status),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.history_rounded,
                            size: 14, color: statusColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Caja de resumen de insumos y total
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.take(3).map((it) {
                    final pName = it['product_name'] ?? 'Insumo';
                    final qty = it['quantity'] ?? 1;
                    final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '$qty x $pName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '\$${(qty * price).toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navyDark,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  if (items.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${items.length - 3} insumos adicionales...',
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.subtitleGrey,
                        ),
                      ),
                    ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total a Pagar:',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                      Text(
                        '\$${totalFinal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Acciones para órdenes pendientes
            if (isPendiente) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navyDark,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      onPressed: () => _showEditOrderModal(order),
                      icon: const Icon(Icons.edit_outlined, size: 15),
                      label: const Text('Modificar',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        backgroundColor: const Color(0xFFFEF2F2),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                      onPressed: () => _confirmCancelOrder(order),
                      icon: const Icon(Icons.cancel_outlined, size: 15),
                      label: const Text('Cancelar',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF001A2C), Color(0xFF1B3452)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF001A2C).withOpacity(0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.lock_outline_rounded,
                      size: 17, color: AppColors.tealMint),
                  label: Text(
                    'Pagar con Wompi (\$${totalFinal.toStringAsFixed(2)})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
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
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navyDark,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showTimelineDialog(order),
                    icon: const Icon(Icons.access_time_rounded,
                        size: 16, color: AppColors.primaryBlue),
                    label: const Text('Trazabilidad',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B3452),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
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
                                  productName: i['product_name'] ?? '',
                                  quantity:
                                      (i['quantity'] as num?)?.toInt() ?? 1,
                                  unitPrice:
                                      (i['unit_price'] as num?)?.toDouble() ??
                                          0.0,
                                ))
                            .toList(),
                        totalAmount: totalFinal,
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
                          builder: (context) =>
                              OrderChatScreen(order: orderObj),
                        ),
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        color: AppColors.tealMint, size: 16),
                    label: const Text('Chat',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),

            // Comprobante Tributario (CCF / Factura DTE)
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final taxType = (order['tax_document_type'] ?? 'factura') == 'ccf'
                    ? 'Crédito Fiscal (CCF)'
                    : 'Factura Electrónica';
                final dteUrl = order['dte_pdf_url']?.toString() ?? '';
                final dteCode = order['dte_generation_code']?.toString() ?? '';
                final hasDte = dteUrl.isNotEmpty || dteCode.isNotEmpty;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: hasDte ? const Color(0xFFECFDF5) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasDte ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasDte ? '$taxType Emitido' : '$taxType Solicitado',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: hasDte
                                    ? const Color(0xFF047857)
                                    : AppColors.navyDark,
                              ),
                            ),
                            Text(
                              dteCode.isNotEmpty
                                  ? 'Cód: $dteCode'
                                  : (hasDte
                                      ? 'Documento PDF disponible'
                                      : 'El distribuidor lo adjuntará al despachar'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10.5, color: AppColors.subtitleGrey),
                            ),
                          ],
                        ),
                      ),
                      if (dteUrl.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => html.window.open(dteUrl, '_blank'),
                          icon: const Icon(Icons.picture_as_pdf,
                              size: 16, color: Color(0xFF047857)),
                          label: const Text(
                            'Descargar',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            if (order['has_incident'] == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFB923C)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.report_problem_outlined,
                        size: 16, color: Colors.deepOrange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Incidencia abierta (liquidación retenida): ${order['incident_note'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (!isPendiente) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlue,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('Repetir Pedido',
                          style: TextStyle(fontSize: 12)),
                      onPressed: () => _repeatOrder(order),
                    ),
                  ),
                  if (status.toLowerCase() == 'entregado' &&
                      order['has_incident'] != true) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrange,
                          side: const BorderSide(color: Colors.deepOrange),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.report_problem_outlined,
                            size: 16),
                        label: const Text('Reportar Faltante',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () => _reportIncidentDialog(order),
                      ),
                    ),
                  ],
                ],
              ),
            ],

            if (status.toLowerCase() == 'entregado') ...[
              const SizedBox(height: 8),
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
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.tealMint.withOpacity(0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.tealMint, size: 19),
            ),
            const SizedBox(width: 10),
            const Text(
              'Mis Pedidos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.10),
                foregroundColor: AppColors.tealMint,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () {
                final message = Uri.encodeComponent(
                  'Hola, equipo de Abasto, necesito ayuda con mis pedidos.',
                );
                html.window.open(
                  'https://wa.me/50360376012?text=$message',
                  '_blank',
                );
              },
              icon: const Icon(Icons.support_agent_rounded, size: 17),
              label: const Text(
                'Ayuda',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Exportar Reporte Contable (CSV / Excel)',
            icon: const Icon(Icons.download_rounded),
            onPressed: _exportOrdersCsv,
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 850;

              if (isDesktop) {
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        mainAxisExtent: 515,
                      ),
                      itemCount: orders.length,
                      itemBuilder: (context, index) =>
                          _buildOrderCard(orders[index]),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildOrderCard(orders[index]),
              );
            },
          );
        },
      ),
    );
  }
}