import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../models/order.dart';
import '../../theme/app_theme.dart';
import '../../config/session_manager.dart';
import '../order_chat_screen.dart';
import '../../widgets/review_dialog.dart';

class SupplierIncomingOrdersScreen extends StatefulWidget {
  const SupplierIncomingOrdersScreen({super.key});

  @override
  State<SupplierIncomingOrdersScreen> createState() =>
      _SupplierIncomingOrdersScreenState();
}

class _SupplierIncomingOrdersScreenState
    extends State<SupplierIncomingOrdersScreen> {
  RealtimeChannel? _ordersSubscription;
  late Future<List<Map<String, dynamic>>> _ordersFuture;

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedStatusFilter = 'todos';
  String _searchQuery = '';

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
  }

  @override
  void dispose() {
    _ordersSubscription?.unsubscribe();
    _searchCtrl.dispose();
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

        // 5. Teléfono
        o['restaurant_phone'] = det?['contact_phone'] ??
            prof?['phone'] ??
            'Sin teléfono registrado';

        // 6. Dirección
        o['restaurant_address'] = det?['delivery_address'] ??
            prof?['address'] ??
            'Sin dirección registrada';

        // 7. Enlace / Redes
        o['restaurant_website'] = prof?['website'] ?? det?['website'];

        // 8. Horarios de atención
        o['business_hours'] = prof?['business_hours'] ??
            det?['business_hours'] ??
            'Lunes a Sábado: 7:00 AM - 5:00 PM';

        // 9. Sucursales
        o['branch_count'] = det?['branch_count']?.toString() ?? '1';

        // 10. Verificación
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

  void _showRestaurantProfileModal(Map<String, dynamic> order) {
    final rName = order['restaurant_name'] ?? 'Restaurante';
    final rNit = order['restaurant_nit'] ?? 'Sin NIT / NRC registrado';
    final rEmail = order['restaurant_email'] ?? 'Sin correo registrado';
    final rPhone = order['restaurant_phone'] ?? 'Sin teléfono registrado';
    final rAddress = order['restaurant_address'] ?? 'Sin dirección registrada';
    final rWebsite = order['restaurant_website']?.toString().trim();
    final rHours =
        order['business_hours'] ?? 'Lunes a Sábado: 7:00 AM - 5:00 PM';
    final branches = order['branch_count'] ?? '1';
    final rAvatar = order['restaurant_avatar']?.toString().trim();
    final bool isVerified = order['is_verified'] == true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.9,
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
                    Icon(Icons.badge_outlined,
                        color: AppColors.primaryBlue, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Ficha del Restaurante',
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
            const Divider(height: 20),
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
                      const SizedBox(height: 4),
                      Text(
                        'Cliente comercial • $branches sucursal(es)',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.subtitleGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFFBEB),
                child: Icon(Icons.receipt_long,
                    color: Color(0xFFD97706), size: 20),
              ),
              title: const Text('NRC / NIT',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(
                rNit,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.navyDark),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFECFDF5),
                child: Icon(Icons.phone, color: Color(0xFF10B981), size: 20),
              ),
              title: const Text('Teléfono de Contacto',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(rPhone,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF1F5F9),
                child: Icon(Icons.email_outlined,
                    color: Color(0xFF475569), size: 20),
              ),
              title: const Text('Correo Electrónico',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(rEmail,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFEF3C7),
                child: Icon(Icons.access_time, color: Colors.orange, size: 20),
              ),
              title: const Text('Horario de Recepción',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(rHours,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFEF2F2),
                child: Icon(Icons.location_on, color: Colors.redAccent, size: 20),
              ),
              title: const Text('Dirección de Entrega',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(rAddress,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
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
                        fontSize: 12, color: AppColors.subtitleGrey)),
                subtitle: Text(rWebsite,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ),
            const SizedBox(height: 16),
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
    final total = (order['total_amount'] as num?)?.toDouble() ?? 0.0;
    final status = (order['status'] ?? 'pendiente').toString();
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
                                'Ver Cliente',
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
            const Text(
              'Insumos solicitados:',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.subtitleGrey,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            ...items.take(2).map((it) {
              final pName = it['product_name'] ?? 'Insumo';
              final qty = it['quantity'] ?? 1;
              return Text('• $qty x $pName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, height: 1.25));
            }),
            if (items.length > 2)
              Text(
                '+ ${items.length - 2} insumos más...',
                style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppColors.subtitleGrey),
              ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total orden:',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                Text(
                  '\$${total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
              ],
            ),
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
                      value: 'confirmado',
                      child: Text('Confirmar Pedido'),
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
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber.shade900,
                    side: BorderSide(color: Colors.amber.shade600),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.star, size: 15),
                  label: const Text('Calificar Restaurante',
                      style: TextStyle(fontSize: 12)),
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
          final countConfirmados = allOrders
              .where((o) =>
                  (o['status'] ?? '').toString().toLowerCase() == 'confirmado')
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
                  Container(
                    color: Colors.white,
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
                                  'Confirmados', 'confirmado', countConfirmados),
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
                                    mainAxisExtent: 315,
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