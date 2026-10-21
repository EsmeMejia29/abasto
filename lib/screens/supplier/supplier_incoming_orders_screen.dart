import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import '../../models/order.dart';
import '../../theme/app_theme.dart';
import '../../config/session_manager.dart';
import '../order_chat_screen.dart';
import '../../widgets/review_dialog.dart';
import 'supplier_bank_settings_screen.dart';

import '../../services/notification_service.dart';

class SupplierIncomingOrdersScreen extends StatefulWidget {
  const SupplierIncomingOrdersScreen({super.key});

  @override
  State<SupplierIncomingOrdersScreen> createState() =>
      _SupplierIncomingOrdersScreenState();
}

class _SupplierIncomingOrdersScreenState
    extends State<SupplierIncomingOrdersScreen> {
  RealtimeChannel? _ordersSubscription;
  RealtimeChannel? _payoutsSubscription;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedStatusFilter = 'todos';
  String _searchQuery = '';

  static const double _supplierCommissionRate = 0.05; // 5% comisión Abasto
  Set<String> _paidOrderIds = {}; // Órdenes ya liquidadas por el admin

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _ordersFuture = _fetchOrders();
    _setupRealtime();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
    NotificationService.initializeAndRegisterToken();
  }

  void _setupRealtime() {
    _ordersSubscription = supabase
        .channel('public:supplier_incoming_orders_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('Actualización de pedidos recibida en distribuidor');
            if (mounted) _refresh();
          },
        )
        .subscribe();

    _payoutsSubscription = supabase
        .channel('public:supplier_payouts_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'supplier_payouts',
          callback: (payload) {
            debugPrint('Actualización en billetera de distribuidor recibida');
            if (mounted) _refresh();
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _ordersSubscription?.unsubscribe();
    _payoutsSubscription?.unsubscribe();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _ordersFuture = _fetchOrders();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchOrders() async {
    try {
      final paidRes = await supabase
          .from('supplier_payouts')
          .select('order_id')
          .eq('supplier_id', _currentUserId)
          .eq('status', 'liquidado');

      _paidOrderIds = (paidRes as List<dynamic>)
          .map((p) => p['order_id']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toSet();
    } catch (e) {
      debugPrint("Error obteniendo pagos liquidados: $e");
    }

    final res = await supabase
        .from('orders')
        .select('''
          *,
          order_items (*)
        ''')
        .eq('supplier_id', _currentUserId)
        .order('created_at', ascending: false);

    final orders = List<Map<String, dynamic>>.from(res);

    final restaurantIds = orders
        .map((o) => o['restaurant_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    if (restaurantIds.isNotEmpty) {
      Map<String, dynamic> profMap = {};
      Map<String, dynamic> detailsMap = {};

      try {
        final profs = await supabase
            .from('profiles')
            .select()
            .filter('id', 'in', restaurantIds);

        profMap = {
          for (var p in (profs as List<dynamic>))
            p['id'].toString(): p as Map<String, dynamic>
        };
      } catch (e) {
        debugPrint("Error consultando profiles: $e");
      }

      try {
        final details = await supabase
            .from('restaurant_details')
            .select()
            .filter('profile_id', 'in', restaurantIds);

        detailsMap = {
          for (var d in (details as List<dynamic>))
            d['profile_id'].toString(): d as Map<String, dynamic>
        };
      } catch (e) {
        debugPrint("Error consultando restaurant_details: $e");
      }

      for (var o in orders) {
        final rId = o['restaurant_id']?.toString();
        final prof = rId != null ? profMap[rId] : null;
        final det = rId != null ? detailsMap[rId] : null;

        // 1. Nombre comercial
        final resolvedName = o['restaurant_name'] ??
            prof?['business_name'] ??
            det?['restaurant_name'] ??
            prof?['full_name'] ??
            o['customer_name'];
        if (resolvedName != null && resolvedName.toString().trim().isNotEmpty) {
          o['restaurant_name'] = resolvedName.toString().trim();
        }

        // 2. NRC / NIT
        o['restaurant_nit'] = prof?['nrc_nit'] ??
            det?['nrc_nit'] ??
            det?['nit'] ??
            'Sin NIT / NRC registrado';

        // 3. Avatar / Logo del comercio
        o['restaurant_avatar'] = prof?['avatar_url'] ?? det?['avatar_url'];

        // 4. Correo
        o['restaurant_email'] =
            prof?['email'] ?? det?['email'] ?? 'Sin correo registrado';

        // 5. Dirección Comercial y Dirección de Entrega
        o['restaurant_address'] = prof?['address'] ??
            det?['restaurant_address'] ??
            det?['delivery_address'] ??
            'Sin dirección física registrada';

        o['delivery_address'] = det?['delivery_address'] ??
            prof?['address'] ??
            det?['restaurant_address'] ??
            o['restaurant_address'];

        // 6. Zona / Municipio
        o['delivery_zone'] = det?['delivery_zone'] ??
            prof?['location'] ??
            'Área Metropolitana';

        // 7. Instrucciones para repartidor
        o['delivery_instructions'] = det?['delivery_instructions'] ??
            'Entrada de proveedores por portón lateral de servicio';

        // 8. Coordenadas de GPS
        final latRaw = det?['delivery_latitude'];
        final lngRaw = det?['delivery_longitude'];
        o['delivery_latitude'] =
            latRaw != null ? double.tryParse(latRaw.toString()) : null;
        o['delivery_longitude'] =
            lngRaw != null ? double.tryParse(lngRaw.toString()) : null;

        // 9. Enlace / Redes
        o['restaurant_website'] = prof?['website'] ?? det?['website'];

        // 10. Horario de Recepción y Atención
        o['delivery_window'] = det?['delivery_window'] ??
            prof?['business_hours'] ??
            'Mañanas (7:00 AM - 11:00 AM)';
        o['business_hours'] = prof?['business_hours'] ??
            det?['business_hours'] ??
            'Lunes a Sábado: 7:00 AM - 5:00 PM';

        // 11. Giro / Especialidad
        o['restaurant_type'] = det?['restaurant_type'] ?? 'Restaurante';

        // 12. Sucursales
        o['branch_count'] = det?['branch_count']?.toString() ?? '1';

        // 13. Verificación
        o['is_verified'] =
            prof?['is_verified'] == true || det?['is_verified'] == true;
      }
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
      case 'pendiente':
        return 'Pendiente';
      case 'cancelado':
        return 'Cancelado';
      default:
        return status;
    }
  }

  Future<void> _updateOrderStatus(
      Map<String, dynamic> order, String newStatus) async {
    try {
      final orderId = order['id'].toString();
      final currentHistory =
          (order['status_history'] as List<dynamic>?) ?? [];

      final newHistory = List<dynamic>.from(currentHistory)
        ..add({
          'status': newStatus,
          'changed_at': DateTime.now().toUtc().toIso8601String(),
          'note': 'Actualizado por distribuidor',
        });

      await supabase.from('orders').update({
        'status': newStatus,
        'status_history': newHistory,
      }).eq('id', orderId);

      _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Estado actualizado a: ${_formatStatus(newStatus)}'),
            backgroundColor: AppColors.tealMint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildWalletCard(List<Map<String, dynamic>> allOrders) {
    double totalPorLiquidar = 0.0;

    for (var ord in allOrders) {
      final st = (ord['status'] ?? '').toString().toLowerCase();
      final ordId = ord['id'].toString();

      if (st == 'entregado' && !_paidOrderIds.contains(ordId)) {
        final subtotal = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
        final commission = subtotal * _supplierCommissionRate;
        totalPorLiquidar += (subtotal - commission);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Saldo por Liquidar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Corte semanal: Viernes',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Text(
                '\$${totalPorLiquidar.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Color(0xFF4ADE80),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF334155), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Retención Abasto por pedido: 5%',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SupplierBankSettingsScreen(),
                    ),
                  ).then((_) => _refresh());
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    children: const [
                      Icon(Icons.account_balance, color: Colors.white70, size: 14),
                      SizedBox(width: 5),
                      Text(
                        'Configurar Cuenta Bancaria',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // MODAL PARA VER LA LISTA COMPLETA DE INSUMOS SOLICITADOS
  void _showAllItemsModal(Map<String, dynamic> order) {
    final code = order['code'] ?? 'Pedido';
    final restaurantName = order['restaurant_name'] ?? 'Restaurante';
    final items = (order['order_items'] as List<dynamic>?) ?? [];
    final totalFacturado = (order['total_amount'] as num?)?.toDouble() ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.shopping_basket_outlined,
                            color: AppColors.primaryBlue, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Insumos: $code',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                          Text(
                            'Cliente: $restaurantName • ${items.length} producto(s)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.subtitleGrey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final it = items[index];
                  final name = it['product_name'] ?? 'Producto';
                  final qty = it['quantity'] ?? 1;

                  // Precio unitario registrado en la orden (incluye el 2%)
                  final precioUnitario =
                      (it['unit_price'] as num?)?.toDouble() ?? 0.0;

                  // Precio original sin el 2%
                  final precioOriginal = (precioUnitario / 1.02);
                  final totalItem = qty * precioUnitario;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            '${qty}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    'Original: \$${precioOriginal.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.navyDark,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      '+2% Abasto',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '(\$${precioUnitario.toStringAsFixed(2)} c/u)',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.subtitleGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '\$${totalItem.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.5,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total del Pedido:',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  Text(
                    '\$${totalFacturado.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRestaurantProfileModal(Map<String, dynamic> order) {
    final rName = order['restaurant_name'] ?? 'Restaurante';
    final rNit = order['restaurant_nit'] ?? 'Sin NIT / NRC registrado';
    final rEmail = order['restaurant_email'] ?? 'Sin correo registrado';
    final rAddress = order['restaurant_address'] ?? 'Sin dirección registrada';
    final rDeliveryAddress = order['delivery_address'] ?? rAddress;
    final rZone = order['delivery_zone'] ?? 'Área Metropolitana';
    final rDeliveryInstructions = order['delivery_instructions'] ?? 'Sin notas';
    final rDeliveryWindow =
        order['delivery_window'] ?? 'Mañanas (7:00 AM - 11:00 AM)';
    final rType = order['restaurant_type'] ?? 'Restaurante';
    final rWebsite = order['restaurant_website']?.toString().trim();
    final branches = order['branch_count'] ?? '1';
    final rAvatar = order['restaurant_avatar']?.toString().trim();
    final bool isVerified = order['is_verified'] == true;

    final double? rLat = order['delivery_latitude'];
    final double? rLng = order['delivery_longitude'];
    final bool hasCoordinates = rLat != null && rLng != null;

    final String mapQuery = hasCoordinates
        ? '$rLat,$rLng'
        : Uri.encodeComponent('$rDeliveryAddress, $rZone, El Salvador');

    final String mapIframeId =
        'supplier-order-map-${order['id']}-${DateTime.now().millisecondsSinceEpoch}';

    ui_web.platformViewRegistry.registerViewFactory(mapIframeId, (int viewId) {
      final iframe = html.IFrameElement()
        ..src =
            'https://maps.google.com/maps?q=$mapQuery&t=&z=15&ie=UTF8&iwloc=&output=embed'
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = false;
      return iframe;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.local_shipping,
                        color: AppColors.primaryBlue, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Hoja de Reparto y Cliente',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(height: 18),

            // Encabezado del Comercio
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFEFF6FF),
                  backgroundImage: (rAvatar != null && rAvatar.isNotEmpty)
                      ? NetworkImage(rAvatar)
                      : null,
                  child: (rAvatar == null || rAvatar.isEmpty)
                      ? const Icon(Icons.storefront,
                          size: 30, color: AppColors.primaryBlue)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              rName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified,
                                size: 18, color: Color(0xFF26A69A)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$rType • $branches sucursal(es)',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.subtitleGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // BOTÓN DE RUTA DE NAVEGACIÓN DIRECTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.navigation,
                    size: 16, color: Color(0xFF38BDF8)),
                label: const Text(
                  'Ruta en Google Maps',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () async {
                  final url = Uri.parse(hasCoordinates
                      ? 'https://www.google.com/maps/dir/?api=1&destination=$rLat,$rLng'
                      : 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent('$rDeliveryAddress, $rZone, El Salvador')}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ),
            const SizedBox(height: 18),

            // VISOR DE GOOGLE MAPS EMBEBIDO
            const Text(
              'Ubicación en Mapa para Entrega:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: HtmlElementView(viewType: mapIframeId),
              ),
            ),
            const SizedBox(height: 18),

            // TARJETA DE DATOS LOGÍSTICOS
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Punto y Dirección de Entrega',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.subtitleGrey,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(rDeliveryAddress,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.navyDark)),
                            Text('Zona: $rZone',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notes,
                          color: Colors.blueGrey, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Instrucciones para Repartidor',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.subtitleGrey,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(rDeliveryInstructions,
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.navyDark)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Horario de Descarga en Cocina',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.subtitleGrey,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(rDeliveryWindow,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.navyDark)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // DATOS FISCALES Y DE CONTACTO
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFFBEB),
                child: Icon(Icons.receipt_long,
                    color: Color(0xFFD97706), size: 20),
              ),
              title: const Text('NRC / NIT para Facturación / DTE',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.subtitleGrey)),
              subtitle: Text(
                rNit,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navyDark),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1F5F9),
                child: Icon(Icons.email_outlined,
                    color: Color(0xFF475569), size: 20),
              ),
              title: const Text('Correo Electrónico',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.subtitleGrey)),
              subtitle: Text(rEmail,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            if (rWebsite != null && rWebsite.isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E8FF),
                  child: Icon(Icons.language, color: Colors.purple, size: 20),
                ),
                title: const Text('Redes / Web',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.subtitleGrey)),
                subtitle: Text(rWebsite,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, int count) {
    final isSelected = _selectedStatusFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text('$label ($count)'),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : const Color(0xFF475569),
        ),
        backgroundColor: Colors.white,
        selectedColor: AppColors.primaryBlue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? AppColors.primaryBlue : Colors.grey.shade300,
          ),
        ),
        onSelected: (_) {
          setState(() {
            _selectedStatusFilter = value;
          });
        },
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final code = order['code'] ?? 'ORD-000';
    final restaurantName = order['restaurant_name'] ?? 'Restaurante';
    final subtotal = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final commission = subtotal * _supplierCommissionRate;
    final netEarnings = subtotal - commission;

    final status = (order['status'] ?? 'pendiente').toString();
    final items = (order['order_items'] as List<dynamic>?) ?? [];
    final bool isLiquidado = _paidOrderIds.contains(order['id'].toString());

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
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _showRestaurantProfileModal(order),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront,
                                size: 14, color: AppColors.primaryBlue),
                            const SizedBox(width: 5),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                restaurantName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Ver Ficha y Mapa',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            const Divider(height: 16),

            // SECCIÓN CLICKEABLE DE INSUMOS SOLICITADOS
            InkWell(
              onTap: () => _showAllItemsModal(order),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Insumos solicitados:',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.subtitleGrey,
                              fontWeight: FontWeight.bold),
                        ),
                        Row(
                          children: const [
                            Text(
                              'Ver lista',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryBlue),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.open_in_new,
                                size: 11, color: AppColors.primaryBlue),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...items.take(2).map((it) {
                      final pName = it['product_name'] ?? 'Insumo';
                      final qty = it['quantity'] ?? 1;
                      return Text('• $qty x $pName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, height: 1.25));
                    }),
                    if (items.length > 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '+ ${items.length - 2} insumos más (toca para ver todos)',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 14),

            // Desglose de liquidación por orden
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Venta bruta:',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.subtitleGrey)),
                Text('\$${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Uso Abasto (5%):',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.subtitleGrey)),
                Text('-\$${commission.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade700)),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Tu pago neto a recibir:',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark)),
                Text(
                  '\$${netEarnings.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),

            if (status.toLowerCase() == 'entregado') ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isLiquidado
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLiquidado ? Icons.check_circle : Icons.schedule,
                      size: 14,
                      color: isLiquidado
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFB45309),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isLiquidado
                          ? 'Transferido a tu banco'
                          : 'Pendiente de liquidación (Viernes)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isLiquidado
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final orderObj = OrderModel(
                          id: order['id'].toString(),
                          code: code,
                          restaurantName: restaurantName,
                          supplierName: 'Mi Empresa',
                          supplierPhone: '',
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
                          totalAmount: subtotal,
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
                              otherPartyName: restaurantName,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 15),
                      label: const Text('Chat', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (newSt) => _updateOrderStatus(order, newSt),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'pendiente',
                      child: Text('Marcar Pendiente'),
                      
                    ),
                    const PopupMenuItem(
                      value: 'enRuta',
                      child: Text('Despachar En Ruta'),
                    ),
                    const PopupMenuItem(
                      value: 'entregado',
                      child: Text('Marcar Entregado'),
                    ),
                    const PopupMenuItem(
                      value: 'cancelado',
                      child: Text('Cancelar Pedido',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Estado',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down,
                            color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (status.toLowerCase() == 'entregado') ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 36,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade600),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.star, size: 16),
                  label: const Text(
                    'Calificar Restaurante',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => ReviewDialog(
                        targetId: order['restaurant_id'].toString(),
                        targetName: restaurantName,
                        targetRole: 'restaurant',
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
        title: const Text('Despacho de Pedidos'),
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
              child: Text('Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red)),
            );
          }

          final allOrders = snapshot.data ?? [];

          final countTodos = allOrders.length;
          final countPendientes = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() == 'pendiente')
              .length;
          
          final countEnRuta = allOrders
              .where((o) => ['enruta', 'en ruta']
                  .contains((o['status'] ?? '').toString().toLowerCase()))
              .length;
          final countEntregados = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() == 'entregado')
              .length;
          final countCancelados = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() == 'cancelado')
              .length;

          final filteredOrders = allOrders.where((o) {
            final st = (o['status'] ?? '').toString().toLowerCase();
            final matchesStatus = _selectedStatusFilter == 'todos' ||
                (_selectedStatusFilter == 'enruta'
                    ? ['enruta', 'en ruta'].contains(st)
                    : st == _selectedStatusFilter);

            final code = (o['code'] ?? '').toString().toLowerCase();
            final restName =
                (o['restaurant_name'] ?? '').toString().toLowerCase();
            final matchesSearch = _searchQuery.isEmpty ||
                code.contains(_searchQuery) ||
                restName.contains(_searchQuery);

            return matchesStatus && matchesSearch;
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                children: [
                  _buildWalletCard(allOrders),
                  Container(
                    color: Colors.white,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'Buscar por código (ej. ORD-2026-676) o restaurante...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => _searchCtrl.clear(),
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('Todos', 'todos', countTodos),
                              _buildFilterChip(
                                  'Pendientes', 'pendiente', countPendientes),
                              _buildFilterChip(
                                  'En Ruta', 'enruta', countEnRuta),
                              _buildFilterChip(
                                  'Entregados', 'entregado', countEntregados),
                              _buildFilterChip(
                                  'Cancelados', 'cancelado', countCancelados),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.inbox_outlined,
                                    size: 56, color: Colors.grey),
                                SizedBox(height: 12),
                                Text(
                                  'No se encontraron pedidos con estos filtros.',
                                  style:
                                      TextStyle(color: AppColors.subtitleGrey),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;

                              if (isDesktop) {
                                return GridView.builder(
                                  padding: const EdgeInsets.all(20),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 18,
                                    mainAxisSpacing: 18,
                                    mainAxisExtent: 430,
                                  ),
                                  itemCount: filteredOrders.length,
                                  itemBuilder: (context, index) =>
                                      _buildOrderCard(filteredOrders[index]),
                                );
                              }

                              return ListView.separated(
                                padding: const EdgeInsets.all(14),
                                itemCount: filteredOrders.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) =>
                                    _buildOrderCard(filteredOrders[index]),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}