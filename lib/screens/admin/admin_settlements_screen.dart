import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';

class AdminSettlementsScreen extends StatefulWidget {
  const AdminSettlementsScreen({super.key});

  @override
  State<AdminSettlementsScreen> createState() => _AdminSettlementsScreenState();
}

class _AdminSettlementsScreenState extends State<AdminSettlementsScreen> {
  late Future<Map<String, dynamic>> _dataFuture;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _restaurantSearchCtrl = TextEditingController();
  String _searchQuery = '';
  String _restaurantSearchQuery = '';

  // Control de pestañas: 0 = Distribuidores & Banco, 1 = Restaurantes & Cobros
  int _currentNavIndex = 0;

  // Filtros principales
  String _statusFilter = 'con_saldo';
  String _weekFilter = 'todas';
  bool _showCalendar = true;

  DateTime _calendarMonth = DateTime.now();
  String? _selectedDateIso;

  static const double _restaurantFeeRate = 0.02; // 2% al restaurante
  static const double _supplierFeeRate = 0.05;   // 5% al distribuidor

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchSettlementsAndBankBalance();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _restaurantSearchCtrl.addListener(() {
      setState(() => _restaurantSearchQuery = _restaurantSearchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _restaurantSearchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _dataFuture = _fetchSettlementsAndBankBalance();
    });
  }

  DateTime _getNextPayoutFriday() {
    final now = DateTime.now();
    int daysUntilFriday = (DateTime.friday - now.weekday) % 7;
    if (daysUntilFriday == 0 && now.hour >= 18) {
      daysUntilFriday = 7;
    }
    return DateTime(now.year, now.month, now.day).add(Duration(days: daysUntilFriday));
  }

  Future<Map<String, dynamic>> _fetchSettlementsAndBankBalance() async {
    // 1. Obtener perfiles de distribuidores y restaurantes
    final allProfilesRes = await supabase
        .from('profiles')
        .select('*')
        .order('business_name', ascending: true);

    final allProfiles = List<Map<String, dynamic>>.from(allProfilesRes);

    final suppliers = allProfiles.where((p) => p['role'] == 'supplier').toList();
    final restaurants = allProfiles.where((p) => p['role'] == 'restaurant').toList();

    final supplierIds = suppliers.map((s) => s['id'].toString()).toList();
    final Map<String, String> supplierNamesMap = {
      for (var s in suppliers) s['id'].toString(): s['business_name']?.toString() ?? 'Distribuidor'
    };

    final Map<String, String> restaurantNamesMap = {
      for (var r in restaurants) r['id'].toString(): r['business_name']?.toString() ?? 'Restaurante'
    };

    // 2. Traer información complementaria de restaurant_details
    Map<String, Map<String, dynamic>> restaurantDetailsMap = {};
    try {
      final restDetailsRes = await supabase.from('restaurant_details').select('*');
      for (var rd in (restDetailsRes as List<dynamic>)) {
        restaurantDetailsMap[rd['profile_id'].toString()] = rd as Map<String, dynamic>;
      }
    } catch (_) {}

    // 3. Órdenes: Traemos todas las órdenes pagadas ('confirmado' y 'entregado')
    final ordersRes = await supabase
        .from('orders')
        .select('''
          id, 
          code, 
          supplier_id, 
          restaurant_id, 
          total_amount, 
          subtotal,
          platform_fee,
          status, 
          created_at,
          order_items (*)
        ''')
        .filter('status', 'in', ['confirmado', 'entregado'])
        .order('created_at', ascending: false);

    final allRelevantOrders = List<Map<String, dynamic>>.from(ordersRes);

    // REGLA 1 (Distribuidores): Solo se liquidan órdenes efectivamente 'entregado'
    final deliveredOrders = allRelevantOrders.where((o) => o['status'] == 'entregado').toList();

    // REGLA 2 (Restaurantes): Muestra todas las órdenes pagadas ('confirmado' y las que ya pasaron a 'entregado')
    final restaurantPaidOrders = allRelevantOrders;

    // 4. Pagos ya transferidos a distribuidores (liquidado)
    final paidPayoutsRes = await supabase
        .from('supplier_payouts')
        .select('id, order_id, supplier_id, net_payout, gross_amount, paid_at, status')
        .eq('status', 'liquidado')
        .order('paid_at', ascending: false);

    final paidPayoutsList = List<Map<String, dynamic>>.from(paidPayoutsRes);

    final Set<String> paidOrderIds = {};
    final Map<String, List<Map<String, dynamic>>> paidPayoutsBySupplier = {};
    final Set<String> paymentDatesIso = {};

    for (var p in paidPayoutsList) {
      final ordId = p['order_id']?.toString();
      if (ordId != null) paidOrderIds.add(ordId);

      final sId = p['supplier_id']?.toString() ?? '';
      if (!paidPayoutsBySupplier.containsKey(sId)) {
        paidPayoutsBySupplier[sId] = [];
      }
      paidPayoutsBySupplier[sId]!.add(p);

      if (p['paid_at'] != null) {
        final d = DateTime.tryParse(p['paid_at'].toString())?.toLocal();
        if (d != null) {
          paymentDatesIso.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        }
      }
    }

    // 5. Mapear pedidos entregados por fecha ISO para el calendario
    final Set<String> orderDatesIso = {};
    final Map<String, List<Map<String, dynamic>>> ordersByDate = {};

    for (var ord in deliveredOrders) {
      if (ord['created_at'] != null) {
        final d = DateTime.tryParse(ord['created_at'].toString())?.toLocal();
        if (d != null) {
          final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          orderDatesIso.add(iso);

          if (!ordersByDate.containsKey(iso)) {
            ordersByDate[iso] = [];
          }

          final sId = ord['supplier_id']?.toString() ?? '';
          final rId = ord['restaurant_id']?.toString() ?? '';
          final ordId = ord['id'].toString();
          final isPaid = paidOrderIds.contains(ordId);

          ordersByDate[iso]!.add({
            ...ord,
            'supplier_name': supplierNamesMap[sId] ?? 'Distribuidor',
            'restaurant_name': restaurantNamesMap[rId] ?? 'Restaurante',
            'is_paid': isPaid,
          });
        }
      }
    }

    // 6. Agrupar órdenes entregadas pendientes por distribuidor
    final Map<String, List<Map<String, dynamic>>> pendingOrdersBySupplier = {};
    for (var ord in deliveredOrders) {
      final ordId = ord['id'].toString();
      final suppId = ord['supplier_id']?.toString() ?? '';

      if (paidOrderIds.contains(ordId)) continue;

      if (!pendingOrdersBySupplier.containsKey(suppId)) {
        pendingOrdersBySupplier[suppId] = [];
      }
      pendingOrdersBySupplier[suppId]!.add(ord);
    }

    // 7. Resumen consolidado por distribuidora (Venta bruta directa de la orden: 18.67 - 0.93 = 17.74)
    final List<Map<String, dynamic>> summaryList = [];
    double totalPendingToPayOut = 0.0;
    double totalHistoricalAlreadyPaid = 0.0;

    for (var s in suppliers) {
      final sId = s['id'].toString();
      final suppPendingOrders = pendingOrdersBySupplier[sId] ?? [];
      final suppPaidRecords = paidPayoutsBySupplier[sId] ?? [];

      double pendingGross = 0.0;
      final List<DateTime> pendingDates = [];
      for (var ord in suppPendingOrders) {
        final ordAmount = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
        pendingGross += ordAmount;

        if (ord['created_at'] != null) {
          final d = DateTime.tryParse(ord['created_at'].toString())?.toLocal();
          if (d != null) pendingDates.add(d);
        }
      }

      final double pendingFee = double.parse((pendingGross * _supplierFeeRate).toStringAsFixed(2));
      final double pendingNet = double.parse((pendingGross - pendingFee).toStringAsFixed(2));
      totalPendingToPayOut += pendingNet;

      double alreadyPaidNet = 0.0;
      DateTime? lastPaidDate;
      final List<DateTime> paidDates = [];

      for (var pr in suppPaidRecords) {
        alreadyPaidNet += (pr['net_payout'] as num?)?.toDouble() ?? 0.0;
        if (pr['paid_at'] != null) {
          final dt = DateTime.tryParse(pr['paid_at'].toString())?.toLocal();
          if (dt != null) {
            paidDates.add(dt);
            if (lastPaidDate == null || dt.isAfter(lastPaidDate)) {
              lastPaidDate = dt;
            }
          }
        }
      }

      totalHistoricalAlreadyPaid += alreadyPaidNet;

      summaryList.add({
        'supplier_id': sId,
        'business_name': s['business_name'] ?? 'Distribuidor Sin Nombre',
        'phone': s['phone'] ?? '',
        'email': s['email'] ?? '',
        'address': s['address'] ?? 'Sin dirección registrada',
        'nrc_nit': s['nrc_nit'] ?? 'Sin NRC/NIT registrado',
        'bank_name': s['bank_name'] ?? 'No configurado',
        'account_type': s['account_type'] ?? 'Ahorros',
        'account_number': s['account_number'] ?? 'Sin registrar',
        'holder_name': s['account_holder_name'] ?? s['business_name'] ?? 'N/A',
        'holder_doc': s['account_holder_document'] ?? 'N/A',
        'pending_orders_count': suppPendingOrders.length,
        'pending_gross': pendingGross,
        'pending_fee': pendingFee,
        'pending_net': pendingNet,
        'already_paid_net': alreadyPaidNet,
        'last_paid_date': lastPaidDate,
        'pending_dates': pendingDates,
        'paid_dates': paidDates,
        'pending_orders': suppPendingOrders,
        'has_balance': pendingNet > 0,
        'is_paid_out': alreadyPaidNet > 0,
      });
    }

    summaryList.sort((a, b) {
      if (a['has_balance'] && !b['has_balance']) return -1;
      if (!a['has_balance'] && b['has_balance']) return 1;
      return (b['pending_net'] as double).compareTo(a['pending_net'] as double);
    });

    // 8. Consolidar Estadísticas por Restaurante (incluyendo pedidos confirmados Y entregados)
    final Map<String, List<Map<String, dynamic>>> ordersByRestaurant = {};
    for (var ord in restaurantPaidOrders) {
      final rId = ord['restaurant_id']?.toString() ?? '';
      if (!ordersByRestaurant.containsKey(rId)) {
        ordersByRestaurant[rId] = [];
      }
      final sId = ord['supplier_id']?.toString() ?? '';
      ordersByRestaurant[rId]!.add({
        ...ord,
        'supplier_name': supplierNamesMap[sId] ?? 'Distribuidora',
      });
    }

    final List<Map<String, dynamic>> restaurantSummaryList = [];
    double totalCollectedFromRestaurants = 0.0;
    double totalRestaurantFees = 0.0;

    for (var r in restaurants) {
      final rId = r['id'].toString();
      final restOrders = ordersByRestaurant[rId] ?? [];
      final details = restaurantDetailsMap[rId] ?? {};

      double realTotalPaid = 0.0;
      double restPlatformFees = 0.0;
      double restInsumosBase = 0.0;

      for (var o in restOrders) {
        final orderTotal = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        final orderSubtotal = (o['subtotal'] as num?)?.toDouble() ??
            double.parse((orderTotal / (1 + _restaurantFeeRate)).toStringAsFixed(2));
        final orderFee = (o['platform_fee'] as num?)?.toDouble() ??
            double.parse((orderTotal - orderSubtotal).toStringAsFixed(2));

        realTotalPaid += orderTotal;
        restInsumosBase += orderSubtotal;
        restPlatformFees += orderFee;
      }

      totalCollectedFromRestaurants += realTotalPaid;
      totalRestaurantFees += restPlatformFees;

      restaurantSummaryList.add({
        'restaurant_id': rId,
        'business_name': r['business_name'] ?? 'Restaurante Sin Nombre',
        'phone': r['phone'] ?? '',
        'email': r['email'] ?? '',
        'address': r['address'] ?? 'Dirección no especificada',
        'nrc_nit': r['nrc_nit'] ?? 'Sin registro',
        'branch_count': details['branch_count'] ?? 1,
        'monthly_budget': (details['monthly_budget'] as num?)?.toDouble() ?? 0.0,
        'orders_count': restOrders.length,
        'gross_spent': restInsumosBase,
        'platform_fee_2pct': restPlatformFees,
        'total_paid': realTotalPaid,
        'orders': restOrders,
      });
    }

    restaurantSummaryList.sort((a, b) => (b['total_paid'] as double).compareTo(a['total_paid'] as double));

    // Saldo que DEBE haber en cuenta = Total de dinero recaudado por Wompi menos lo transferido
    final double shouldBeInBankNow = totalCollectedFromRestaurants - totalHistoricalAlreadyPaid;
    final double totalPlatformProfit = totalRestaurantFees + (totalPendingToPayOut * (_supplierFeeRate / (1 - _supplierFeeRate)));

    return {
      'suppliers': summaryList,
      'restaurants': restaurantSummaryList,
      'bankTotalInflows': totalCollectedFromRestaurants,
      'shouldBeInBankNow': shouldBeInBankNow,
      'totalPendingToPayOut': totalPendingToPayOut,
      'totalPlatformProfit': totalPlatformProfit,
      'totalHistoricalAlreadyPaid': totalHistoricalAlreadyPaid,
      'totalCollectedFromRestaurants': totalCollectedFromRestaurants,
      'totalRestaurantFees': totalRestaurantFees,
      'orderDatesIso': orderDatesIso,
      'paymentDatesIso': paymentDatesIso,
      'ordersByDate': ordersByDate,
      'nextFriday': _getNextPayoutFriday(),
    };
  }

  bool _matchesWeekFilter(List<DateTime> dates) {
    if (_weekFilter == 'todas') return true;
    if (dates.isEmpty) return false;

    final now = DateTime.now();

    for (var d in dates) {
      if (_weekFilter == 'esta_semana') {
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59));
        if (d.isAfter(startOfWeek.subtract(const Duration(seconds: 1))) &&
            d.isBefore(endOfWeek.add(const Duration(seconds: 1)))) {
          return true;
        }
      } else if (_weekFilter == 'semana_1') {
        if (d.month == now.month && d.year == now.year && d.day >= 1 && d.day <= 7) return true;
      } else if (_weekFilter == 'semana_2') {
        if (d.month == now.month && d.year == now.year && d.day >= 8 && d.day <= 14) return true;
      } else if (_weekFilter == 'semana_3') {
        if (d.month == now.month && d.year == now.year && d.day >= 15 && d.day <= 21) return true;
      } else if (_weekFilter == 'semana_4') {
        if (d.month == now.month && d.year == now.year && d.day >= 22) return true;
      }
    }
    return false;
  }

  Future<void> _contactViaWhatsApp(String phone, String businessName, String messageText) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay teléfono registrado para esta empresa.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final formatted = cleanPhone.startsWith('503') ? cleanPhone : '503$cleanPhone';
    final url = Uri.parse('https://wa.me/$formatted?text=${Uri.encodeComponent(messageText)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _contactViaEmail(String email, String subject, String body) async {
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay correo electrónico válido registrado.'), backgroundColor: Colors.orange),
      );
      return;
    }
    final url = Uri.parse('mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  // --- MODAL: PEDIDOS DEL RESTAURANTE (CONFIRMADOS Y ENTREGADOS) ---
  void _showRestaurantOrdersModal(Map<String, dynamic> rest) {
    final orders = List<Map<String, dynamic>>.from(rest['orders'] ?? []);
    final name = rest['business_name'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.82,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, color: AppColors.primaryBlue, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        'Pedidos de $name',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.navyDark),
                      ),
                    ],
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Text(
                'Órdenes registradas y pagadas (${orders.length})',
                style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
              ),
              const Divider(height: 20),

              if (orders.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Este restaurante aún no registra órdenes.', style: TextStyle(color: AppColors.subtitleGrey)),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final ord = orders[index];
                      final code = ord['code'] ?? 'ORD-000';
                      final supplierName = ord['supplier_name'] ?? 'Distribuidora';
                      final status = ord['status'] ?? 'confirmado';
                      final bool isEntregado = status == 'entregado';

                      final double totalPagado = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final double subtotalInsumos = (ord['subtotal'] as num?)?.toDouble() ??
                          double.parse((totalPagado / (1 + _restaurantFeeRate)).toStringAsFixed(2));
                      final double fee2pct = (ord['platform_fee'] as num?)?.toDouble() ??
                          double.parse((totalPagado - subtotalInsumos).toStringAsFixed(2));

                      final items = (ord['order_items'] as List<dynamic>?) ?? [];

                      DateTime? createdDate;
                      if (ord['created_at'] != null) {
                        createdDate = DateTime.tryParse(ord['created_at'].toString())?.toLocal();
                      }

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyDark)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isEntregado ? const Color(0xFFE0E7FF) : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isEntregado ? 'Entregado' : 'Confirmado',
                                        style: TextStyle(
                                          color: isEntregado ? const Color(0xFF4338CA) : const Color(0xFF16A34A),
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '\$${totalPagado.toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('Distribuidor: $supplierName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                            if (createdDate != null)
                              Text('Fecha: ${createdDate.day}/${createdDate.month}/${createdDate.year} - ${createdDate.hour.toString().padLeft(2, '0')}:${createdDate.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                            const SizedBox(height: 8),

                            if (items.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...items.map((it) {
                                      final pName = it['product_name'] ?? 'Insumo';
                                      final qty = it['quantity'] ?? 1;
                                      final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('$qty x $pName', style: const TextStyle(fontSize: 12)),
                                            Text('\$${(qty * price).toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Insumos base: \$${subtotalInsumos.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                                Text('Tarifa Abasto (2% incluida): \$${fee2pct.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markAsTransferred(Map<String, dynamic> item) async {
    final pendingOrders = item['pending_orders'] as List<Map<String, dynamic>>;
    final name = item['business_name'];
    final double amount = item['pending_net'];
    final supplierId = item['supplier_id'].toString();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmar Liquidación Semanal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Confirmas que ya transferiste \$${amount.toStringAsFixed(2)} a $name?', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Banco: ${item['bank_name']} (${item['account_type']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Cuenta: ${item['account_number']}', style: const TextStyle(fontSize: 13)),
                  Text('Titular: ${item['holder_name']} • Doc: ${item['holder_doc']}', style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, Liquidar Semana', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final inserts = pendingOrders.map((ord) {
          final gross = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
          final fee = double.parse((gross * _supplierFeeRate).toStringAsFixed(2));
          final net = double.parse((gross - fee).toStringAsFixed(2));

          return {
            'supplier_id': supplierId,
            'order_id': ord['id'],
            'order_code': ord['code'] ?? 'ORD-000',
            'gross_amount': gross,
            'commission_fee': fee,
            'net_payout': net,
            'status': 'liquidado',
            'paid_at': nowIso,
          };
        }).toList();

        if (inserts.isNotEmpty) {
          await supabase.from('supplier_payouts').insert(inserts);
        }

        _refresh();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pago de \$${amount.toStringAsFixed(2)} a $name liquidado.'), backgroundColor: AppColors.tealMint),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al procesar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // --- TARJETA DE CONCILIACIÓN BANCARIA (RESPONSIVA) ---
  Widget _buildBankReconciliationCard(Map<String, dynamic> data, bool isDesktop) {
    final double shouldBeInBank = data['shouldBeInBankNow'] ?? 0.0;
    final double pendingPayouts = data['totalPendingToPayOut'] ?? 0.0;
    final double totalProfit = data['totalPlatformProfit'] ?? 0.0;
    final double totalAlreadyPaid = data['totalHistoricalAlreadyPaid'] ?? 0.0;

    final double totalReference = shouldBeInBank > 0 ? shouldBeInBank : 1.0;
    final double supplierRatio = (pendingPayouts / totalReference).clamp(0.0, 1.0);
    final double profitRatio = (totalProfit / totalReference).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: EdgeInsets.all(isDesktop ? 22 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.account_balance, color: AppColors.primaryBlue, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Conciliación Bancaria Abasto',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                        ),
                        Text(
                          'Cuenta Banco Agrícola (Fondos recaudados vs. liquidaciones)',
                          style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Saldo que DEBE haber en cuenta hoy:', style: TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                    Text(
                      '\$${shouldBeInBank.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                    ),
                  ],
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance, color: AppColors.primaryBlue, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Conciliación Bancaria Abasto',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Saldo que DEBE haber en cuenta hoy:', style: TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                  Text(
                    '\$${shouldBeInBank.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  if (supplierRatio > 0)
                    Expanded(
                      flex: (supplierRatio * 100).toInt().clamp(1, 100),
                      child: Container(color: Colors.amber.shade700),
                    ),
                  if (profitRatio > 0)
                    Expanded(
                      flex: (profitRatio * 100).toInt().clamp(1, 100),
                      child: Container(color: const Color(0xFF10B981)),
                    ),
                  if (shouldBeInBank == 0)
                    Expanded(child: Container(color: Colors.grey.shade200)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (isDesktop)
            Row(
              children: [
                Expanded(child: _buildBankSubCard('De Distribuidores (Por transferir)', pendingPayouts, 'Corte de viernes (Entregados)', const Color(0xFFFFFBEB), Colors.amber.shade200, Colors.amber.shade900)),
                const SizedBox(width: 12),
                Expanded(child: _buildBankSubCard('Ganancia Abasto (2% + 5%)', totalProfit, 'Fondos disponibles', const Color(0xFFECFDF5), const Color(0xFFA7F3D0), const Color(0xFF047857))),
                const SizedBox(width: 12),
                Expanded(child: _buildBankSubCard('Ya Transferido a Distribuidores', totalAlreadyPaid, 'Por Transfer365', const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), AppColors.navyDark)),
              ],
            )
          else
            Column(
              children: [
                _buildBankSubCard('De Distribuidores (Por transferir)', pendingPayouts, 'Corte de viernes (Entregados)', const Color(0xFFFFFBEB), Colors.amber.shade200, Colors.amber.shade900),
                const SizedBox(height: 8),
                _buildBankSubCard('Ganancia Abasto (2% + 5%)', totalProfit, 'Fondos disponibles', const Color(0xFFECFDF5), const Color(0xFFA7F3D0), const Color(0xFF047857)),
                const SizedBox(height: 8),
                _buildBankSubCard('Ya Transferido a Distribuidores', totalAlreadyPaid, 'Por Transfer365', const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), AppColors.navyDark),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildBankSubCard(String title, double amount, String subtitle, Color bg, Color border, Color textCol) {
    return Container(
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textCol)),
          const SizedBox(height: 4),
          Text('\$${amount.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textCol)),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
        ],
      ),
    );
  }

  // --- CALENDARIO PLEGABLE ---
  Widget _buildOperationsCalendar(Map<String, dynamic> data) {
    final Set<String> orderDates = data['orderDatesIso'] ?? {};
    final Set<String> paymentDates = data['paymentDatesIso'] ?? {};
    final Map<String, List<Map<String, dynamic>>> ordersByDate = data['ordersByDate'] ?? {};
    final DateTime nextFriday = data['nextFriday'] ?? _getNextPayoutFriday();
    final String nextFridayIso =
        '${nextFriday.year}-${nextFriday.month.toString().padLeft(2, '0')}-${nextFriday.day.toString().padLeft(2, '0')}';

    final daysInMonth = DateUtils.getDaysInMonth(_calendarMonth.year, _calendarMonth.month);
    final firstDayWeekday = DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday;

    const monthNames = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];

    final selectedOrders = _selectedDateIso != null ? (ordersByDate[_selectedDateIso] ?? []) : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: AppColors.primaryBlue, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1);
                        _selectedDateIso = null;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () {
                      setState(() {
                        _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                        _selectedDateIso = null;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegendItem(const Color(0xFF2563EB), 'Pedidos Entregados'),
              _buildLegendItem(const Color(0xFF16A34A), 'Liquidación Transferida'),
              _buildLegendItem(Colors.amber.shade700, 'Próximo Corte (Viernes)'),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const Divider(height: 16),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (firstDayWeekday - 1) + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 40,
            ),
            itemBuilder: (context, index) {
              if (index < firstDayWeekday - 1) {
                return const SizedBox.shrink();
              }
              final dayNumber = index - (firstDayWeekday - 1) + 1;
              final dayDateIso =
                  '${_calendarMonth.year}-${_calendarMonth.month.toString().padLeft(2, '0')}-${dayNumber.toString().padLeft(2, '0')}';

              final hasOrder = orderDates.contains(dayDateIso);
              final hasPayment = paymentDates.contains(dayDateIso);
              final isNextFriday = dayDateIso == nextFridayIso;
              final isSelected = _selectedDateIso == dayDateIso;

              Color? bg;
              Color textColor = AppColors.navyDark;

              if (hasPayment) {
                bg = const Color(0xFFDCFCE7);
                textColor = const Color(0xFF16A34A);
              } else if (isNextFriday) {
                bg = const Color(0xFFFEF3C7);
                textColor = const Color(0xFFB45309);
              } else if (hasOrder) {
                bg = const Color(0xFFDBEAFE);
                textColor = const Color(0xFF1D4ED8);
              }

              return InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedDateIso == dayDateIso) {
                      _selectedDateIso = null;
                    } else {
                      _selectedDateIso = dayDateIso;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: bg ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryBlue
                          : (isNextFriday ? Colors.amber.shade600 : Colors.transparent),
                      width: isSelected ? 2 : (isNextFriday ? 1.5 : 1),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        fontWeight: (hasOrder || hasPayment || isNextFriday || isSelected)
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 12,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          if (_selectedDateIso != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pedidos entregados del $_selectedDateIso (${selectedOrders.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navyDark),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _selectedDateIso = null),
                      ),
                    ],
                  ),
                  if (selectedOrders.isEmpty)
                    const Text('No hubo pedidos entregados en esta fecha.', style: TextStyle(color: AppColors.subtitleGrey, fontSize: 12))
                  else
                    ...selectedOrders.map((ord) {
                      final double amount = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final double netPayout = double.parse((amount * (1 - _supplierFeeRate)).toStringAsFixed(2));
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${ord['code']} • ${ord['supplier_name']}', style: const TextStyle(fontSize: 12)),
                            Text('\$${netPayout.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
      ],
    );
  }

  // --- SECCIÓN 1: VISTA DE DISTRIBUIDORES ---
  Widget _buildSuppliersTab(Map<String, dynamic> data, bool isDesktop) {
    final List<Map<String, dynamic>> allSuppliers = data['suppliers'] ?? [];

    int conSaldoCount = 0;
    int pagadosCount = 0;
    int alDiaCount = 0;

    for (var s in allSuppliers) {
      if (s['has_balance'] == true) conSaldoCount++;
      if (s['is_paid_out'] == true) pagadosCount++;
      if (s['has_balance'] == false) alDiaCount++;
    }

    final filtered = allSuppliers.where((s) {
      final name = (s['business_name'] ?? '').toString().toLowerCase();
      final bank = (s['bank_name'] ?? '').toString().toLowerCase();
      final holder = (s['holder_name'] ?? '').toString().toLowerCase();

      final matchesQuery = _searchQuery.isEmpty ||
          name.contains(_searchQuery) ||
          bank.contains(_searchQuery) ||
          holder.contains(_searchQuery);

      bool matchesStatus = true;
      if (_statusFilter == 'con_saldo') {
        matchesStatus = (s['has_balance'] == true);
      } else if (_statusFilter == 'pagados') {
        matchesStatus = (s['is_paid_out'] == true);
      } else if (_statusFilter == 'al_dia') {
        matchesStatus = (s['has_balance'] == false);
      }

      final List<DateTime> relevantDates = [];
      if (_statusFilter == 'pagados') {
        relevantDates.addAll(s['paid_dates'] as List<DateTime>);
      } else {
        relevantDates.addAll(s['pending_dates'] as List<DateTime>);
        if (relevantDates.isEmpty) {
          relevantDates.addAll(s['paid_dates'] as List<DateTime>);
        }
      }
      final matchesWeek = _matchesWeekFilter(relevantDates);

      return matchesQuery && matchesStatus && matchesWeek;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBankReconciliationCard(data, isDesktop),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.event_note, color: AppColors.primaryBlue, size: 20),
                SizedBox(width: 8),
                Text('Calendario de Liquidaciones (Entregas)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark)),
              ],
            ),
            TextButton.icon(
              icon: Icon(_showCalendar ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
              label: Text(_showCalendar ? 'Ocultar' : 'Mostrar'),
              onPressed: () => setState(() => _showCalendar = !_showCalendar),
            ),
          ],
        ),
        const SizedBox(height: 6),

        if (_showCalendar) _buildOperationsCalendar(data),

        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar distribuidora o titular de cuenta...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _searchCtrl.clear())
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(height: 12),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: 'con_saldo', label: Text('Por Pagar ($conSaldoCount)')),
                    ButtonSegment(value: 'pagados', label: Text('Pagados ($pagadosCount)')),
                    ButtonSegment(value: 'todos', label: Text('Todos (${allSuppliers.length})')),
                    ButtonSegment(value: 'al_dia', label: Text('Al Día ($alDiaCount)')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (val) => setState(() => _statusFilter = val.first),
                ),
              ),
            ],
          ),
        ),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(36),
            alignment: Alignment.center,
            child: const Text('No hay distribuidoras que coincidan con estos filtros.', style: TextStyle(color: AppColors.subtitleGrey)),
          )
        else
          ...filtered.map((item) => _buildSupplierCard(item, isDesktop)),
      ],
    );
  }

  Widget _buildSupplierCard(Map<String, dynamic> item, bool isDesktop) {
    final name = item['business_name'];
    final double pendingToPay = item['pending_net'];
    final double pendingGross = item['pending_gross'];
    final double pendingFee = item['pending_fee'];
    final int count = item['pending_orders_count'];
    final bool hasBalance = item['has_balance'];
    final hasBankConfigured = item['account_number'] != 'Sin registrar' &&
        item['bank_name'] != 'No configurado' &&
        item['account_number'].toString().trim().isNotEmpty;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: hasBalance ? AppColors.primaryBlue.withOpacity(0.3) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: hasBalance ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                        child: Icon(Icons.storefront, color: hasBalance ? const Color(0xFF16A34A) : Colors.grey, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.navyDark), overflow: TextOverflow.ellipsis),
                            Text('${item['phone']} • ${item['email']}', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(hasBalance ? 'Por Transferir' : 'Al Día', style: const TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                    Text('\$${(hasBalance ? pendingToPay : 0.0).toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: hasBalance ? const Color(0xFF16A34A) : Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),

            if (hasBalance) ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ventas Entregadas:', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                          Text('\$${pendingGross.toStringAsFixed(2)} ($count pedidos)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Comisión (5% Retenido):', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                          Text('-\$${pendingFee.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0284C7))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasBankConfigured ? const Color(0xFFF1F5F9) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hasBankConfigured ? const Color(0xFFCBD5E1) : Colors.amber.shade300),
              ),
              child: hasBankConfigured
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item['bank_name']} (${item['account_type']}) - No. ${item['account_number']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('Titular: ${item['holder_name']} • Doc: ${item['holder_doc']}', style: const TextStyle(fontSize: 11, color: Color(0xFF475569))),
                      ],
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        const Text('⚠️ Sin cuenta bancaria registrada', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFB45309))),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Pedir cuenta por WhatsApp',
                              icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 20),
                              onPressed: () => _contactViaWhatsApp(item['phone'], name, '¡Hola! Te contactamos desde Abasto para gestionar tu liquidación.'),
                            ),
                            IconButton(
                              tooltip: 'Enviar Correo',
                              icon: const Icon(Icons.email_outlined, color: AppColors.primaryBlue, size: 20),
                              onPressed: () => _contactViaEmail(item['email'], 'Datos Bancarios Abasto', 'Por favor compártenos tus datos bancarios.'),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),

            if (hasBalance) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasBankConfigured ? const Color(0xFF16A34A) : Colors.grey.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text('Confirmar Transferencia (\$${pendingToPay.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: hasBankConfigured ? () => _markAsTransferred(item) : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- SECCIÓN 2: VISTA DE RESTAURANTES (CONFIRMADOS Y ENTREGADOS) ---
  Widget _buildRestaurantsTab(Map<String, dynamic> data, bool isDesktop) {
    final List<Map<String, dynamic>> allRestaurants = data['restaurants'] ?? [];
    final double totalCollected = data['totalCollectedFromRestaurants'] ?? 0.0;
    final double totalFees = data['totalRestaurantFees'] ?? 0.0;

    final filtered = allRestaurants.where((r) {
      final name = (r['business_name'] ?? '').toString().toLowerCase();
      final phone = (r['phone'] ?? '').toString().toLowerCase();
      final email = (r['email'] ?? '').toString().toLowerCase();
      return _restaurantSearchQuery.isEmpty ||
          name.contains(_restaurantSearchQuery) ||
          phone.contains(_restaurantSearchQuery) ||
          email.contains(_restaurantSearchQuery);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: EdgeInsets.all(isDesktop ? 20 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.restaurant, color: Color(0xFF0284C7), size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Text('Resumen de Restaurantes y Pagos Recibidos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                ],
              ),
              const SizedBox(height: 14),

              if (isDesktop)
                Row(
                  children: [
                    Expanded(child: _buildBankSubCard('Total Compras Pagadas', totalCollected, 'Ingreso real en órdenes', const Color(0xFFF0FDF4), const Color(0xFFBBF7D0), const Color(0xFF15803D))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildBankSubCard('Tarifa Abasto (2% incluida)', totalFees, 'Comisión recaudada', const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), const Color(0xFF1D4ED8))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildBankSubCard('Restaurantes Registrados', allRestaurants.length.toDouble(), 'Clientes activos', const Color(0xFFF8FAFC), const Color(0xFFCBD5E1), AppColors.navyDark)),
                  ],
                )
              else
                Column(
                  children: [
                    _buildBankSubCard('Total Compras Pagadas', totalCollected, 'Ingreso real en órdenes', const Color(0xFFF0FDF4), const Color(0xFFBBF7D0), const Color(0xFF15803D)),
                    const SizedBox(height: 8),
                    _buildBankSubCard('Tarifa Abasto (2% incluida)', totalFees, 'Comisión recaudada', const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), const Color(0xFF1D4ED8)),
                  ],
                ),
            ],
          ),
        ),

        Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: _restaurantSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, correo o teléfono de restaurante...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _restaurantSearchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => _restaurantSearchCtrl.clear())
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),

        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: const Text('No se encontraron restaurantes.', style: TextStyle(color: AppColors.subtitleGrey)),
          )
        else
          ...filtered.map((rest) => _buildRestaurantCard(rest, isDesktop)),
      ],
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> rest, bool isDesktop) {
    final name = rest['business_name'];
    final double totalPaid = rest['total_paid']; // Suma directa de las órdenes ($18.67 + $22.35 = $41.02)
    final double grossSpent = rest['gross_spent'];
    final double fee2pct = rest['platform_fee_2pct'];
    final int ordersCount = rest['orders_count'];
    final int branches = rest['branch_count'];
    final phone = rest['phone'] ?? '';
    final email = rest['email'] ?? '';
    final address = rest['address'] ?? '';

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 18,
                        backgroundColor: Color(0xFFE0F2FE),
                        child: Icon(Icons.restaurant, color: Color(0xFF0369A1), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.navyDark), overflow: TextOverflow.ellipsis),
                            Text('$branches sucursal(es) • $ordersCount órdenes pagadas', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Total Pagado', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                    Text('\$${totalPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navyDark)),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),

            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Insumos Facturados:', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                        Text('\$${grossSpent.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tarifa Abasto (2% incluida):', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                        Text('\$${fee2pct.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF16A34A))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryBlue,
                  side: const BorderSide(color: AppColors.primaryBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.receipt_long, size: 16),
                label: Text('Ver Pedidos Realizados ($ordersCount)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _showRestaurantOrdersModal(rest),
              ),
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (phone.isNotEmpty) Text('📞 $phone', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        if (email.isNotEmpty) Text('✉️ $email', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                        if (address.isNotEmpty) Text('📍 $address', style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      if (phone.isNotEmpty)
                        IconButton(
                          tooltip: 'Escribir por WhatsApp',
                          icon: const Icon(Icons.chat, color: Color(0xFF25D366), size: 18),
                          onPressed: () => _contactViaWhatsApp(phone, name, '¡Hola equipo de $name! Te saludamos de soporte Abasto.'),
                        ),
                      if (email.isNotEmpty)
                        IconButton(
                          tooltip: 'Enviar correo',
                          icon: const Icon(Icons.email_outlined, color: AppColors.primaryBlue, size: 18),
                          onPressed: () => _contactViaEmail(email, 'Consulta Abasto SV', 'Estimado cliente de $name:'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 850;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            title: Text(_currentNavIndex == 0 ? 'Liquidación a Distribuidores' : 'Cobranza y Restaurantes'),
            centerTitle: !isDesktop,
            actions: [
              IconButton(tooltip: 'Actualizar saldos', icon: const Icon(Icons.refresh), onPressed: _refresh),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentNavIndex,
            onDestinationSelected: (idx) => setState(() => _currentNavIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: 'Distribuidores & Banco',
              ),
              NavigationDestination(
                icon: Icon(Icons.restaurant_outlined),
                selectedIcon: Icon(Icons.restaurant),
                label: 'Restaurantes & Cobros',
              ),
            ],
          ),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text('Error al cargar datos: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                  ),
                );
              }

              final data = snapshot.data ?? {};

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: isDesktop ? 24 : 14, vertical: 16),
                    children: [
                      if (_currentNavIndex == 0)
                        _buildSuppliersTab(data, isDesktop)
                      else
                        _buildRestaurantsTab(data, isDesktop),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}