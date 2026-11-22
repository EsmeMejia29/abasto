import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import '../welcome_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/csv_exporter.dart';

class AdminSettlementsScreen extends StatefulWidget {
  const AdminSettlementsScreen({super.key});

  @override
  State<AdminSettlementsScreen> createState() => _AdminSettlementsScreenState();
}

class _AdminSettlementsScreenState extends State<AdminSettlementsScreen> {
  late Future<Map<String, dynamic>> _dataFuture;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _restaurantSearchCtrl = TextEditingController();
  final TextEditingController _commerceSearchCtrl = TextEditingController();
  final TextEditingController _globalOrderSearchCtrl = TextEditingController();
  final TextEditingController _chatSearchCtrl = TextEditingController();
  String _searchQuery = '';
  String _restaurantSearchQuery = '';
  String _commerceSearchQuery = '';
  String _globalOrderSearchQuery = '';
  String _chatSearchQuery = '';
  String _commerceRoleFilter = 'todos'; // 'todos', 'supplier', 'restaurant', 'pendiente_verif'
  String _globalOrderFilter = 'todos'; // 'todos', 'sin_dte', 'pendiente', 'entregado'
  String? _selectedChatOrderId;

  // Control de pestañas: 0 = Liquidaciones, 1 = Restaurantes, 2 = Comercios, 3 = Órdenes & DTE, 4 = Chats B2B
  int _currentNavIndex = 0;

  // Filtros principales
  String _statusFilter = 'con_saldo';
  String _weekFilter = 'todas';
  bool _showCalendar = true;

  DateTime _calendarMonth = DateTime.now();
  String? _selectedDateIso;

  static const double _restaurantFeeRate = 0.03; // 3% al restaurante
  static const double _supplierFeeRate = 0.05;   // 5% al distribuidor sobre precio base

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
    _commerceSearchCtrl.addListener(() {
      setState(() => _commerceSearchQuery = _commerceSearchCtrl.text.trim().toLowerCase());
    });
    _globalOrderSearchCtrl.addListener(() {
      setState(() => _globalOrderSearchQuery = _globalOrderSearchCtrl.text.trim().toLowerCase());
    });
    _chatSearchCtrl.addListener(() {
      setState(() => _chatSearchQuery = _chatSearchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _restaurantSearchCtrl.dispose();
    _commerceSearchCtrl.dispose();
    _globalOrderSearchCtrl.dispose();
    _chatSearchCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _dataFuture = _fetchSettlementsAndBankBalance();
    });
  }

  DateTime _getNextPayoutFriday() {
    final now = DateTime.now();
    int daysUntilFriday = (5 - now.weekday) % 7;
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

    final Map<String, String> supplierNamesMap = {
      for (var s in suppliers) s['id'].toString(): s['business_name']?.toString() ?? 'Distribuidor'
    };

    final Map<String, String> restaurantNamesMap = {
      for (var r in restaurants) r['id'].toString(): r['business_name']?.toString() ?? 'Restaurante'
    };

    // 2. Traer información complementaria de restaurant_details y supplier_details
    Map<String, Map<String, dynamic>> restaurantDetailsMap = {};
    try {
      final restDetailsRes = await supabase.from('restaurant_details').select('*');
      for (var rd in (restDetailsRes as List<dynamic>)) {
        restaurantDetailsMap[rd['profile_id'].toString()] = rd as Map<String, dynamic>;
      }
    } catch (_) {}

    Map<String, Map<String, dynamic>> supplierDetailsMap = {};
    try {
      final suppDetailsRes = await supabase
          .from('supplier_details')
          .select('profile_id, is_featured, featured_until');
      for (var sd in (suppDetailsRes as List<dynamic>)) {
        supplierDetailsMap[sd['profile_id'].toString()] =
            Map<String, dynamic>.from(sd as Map);
      }
    } catch (_) {}

    // 3. Órdenes globales de toda la plataforma
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
          tax_document_type,
          dte_generation_code,
          dte_pdf_url,
          has_incident,
          incident_note,
          created_at,
          order_items (*)
        ''')
        .order('created_at', ascending: false);

    final allPlatformOrders = List<Map<String, dynamic>>.from(ordersRes);
    final allRelevantOrders = allPlatformOrders
        .where((o) => ['confirmado', 'entregado'].contains(o['status']))
        .toList();

    // Órdenes retenidas por incidencia abierta
    final disputedOrders = allRelevantOrders
        .where((o) => o['has_incident'] == true)
        .map((o) => {
              ...o,
              'supplier_name':
                  supplierNamesMap[o['supplier_id']?.toString() ?? ''] ??
                      'Distribuidor',
              'restaurant_name':
                  restaurantNamesMap[o['restaurant_id']?.toString() ?? ''] ??
                      'Restaurante',
            })
        .toList();

    // REGLA 1 (Distribuidores): Solo se liquidan órdenes 'entregado' SIN incidencia abierta
    final deliveredOrders = allRelevantOrders
        .where((o) => o['status'] == 'entregado' && o['has_incident'] != true)
        .toList();

    // REGLA 2 (Restaurantes): Muestra todas las órdenes pagadas ('confirmado' y 'entregado')
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

    // 7. Resumen consolidado por distribuidora (Base neta de insumos sin el 3% de Abasto)
    final List<Map<String, dynamic>> summaryList = [];
    double totalPendingToPayOut = 0.0;
    double totalHistoricalAlreadyPaid = 0.0;
    double totalSupplierFeesPending = 0.0;

    for (var s in suppliers) {
      final sId = s['id'].toString();
      final suppPendingOrders = pendingOrdersBySupplier[sId] ?? [];
      final suppPaidRecords = paidPayoutsBySupplier[sId] ?? [];

      double pendingBaseInsumos = 0.0;
      final List<DateTime> pendingDates = [];
      for (var ord in suppPendingOrders) {
        final ordTotal = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
        final ordBase = (ord['subtotal'] as num?)?.toDouble() ??
            double.parse((ordTotal / (1 + _restaurantFeeRate)).toStringAsFixed(2));
        pendingBaseInsumos += ordBase;

        if (ord['created_at'] != null) {
          final d = DateTime.tryParse(ord['created_at'].toString())?.toLocal();
          if (d != null) pendingDates.add(d);
        }
      }

      final double pendingFee = double.parse((pendingBaseInsumos * _supplierFeeRate).toStringAsFixed(2));
      final double pendingNet = double.parse((pendingBaseInsumos - pendingFee).toStringAsFixed(2));
      totalPendingToPayOut += pendingNet;
      totalSupplierFeesPending += pendingFee;

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
        'pending_gross': pendingBaseInsumos,
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

    // 8. Consolidar Estadísticas por Restaurante
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

    final double shouldBeInBankNow = totalCollectedFromRestaurants - totalHistoricalAlreadyPaid;
    final double totalPlatformProfit = totalRestaurantFees + totalSupplierFeesPending;

    final Map<String, String> supplierPhonesMap = {
      for (var s in suppliers)
        s['id'].toString(): (s['phone'] ?? '').toString()
    };

    final globalOrders = allPlatformOrders.map((o) {
      final sId = o['supplier_id']?.toString() ?? '';
      final rId = o['restaurant_id']?.toString() ?? '';
      return {
        ...o,
        'supplier_name': supplierNamesMap[sId] ?? 'Distribuidor',
        'supplier_phone': supplierPhonesMap[sId] ?? '',
        'restaurant_name': restaurantNamesMap[rId] ?? 'Restaurante',
      };
    }).toList();

    final allCommerces = allProfiles
        .where((p) => p['role'] == 'supplier' || p['role'] == 'restaurant')
        .map((p) {
      final det = supplierDetailsMap[p['id'].toString()];
      return {
        ...p,
        'is_featured': det?['is_featured'] == true,
        'featured_until': det?['featured_until'],
      };
    }).toList();

    List<dynamic> allChatMessages = [];
    try {
      final msgsRes = await supabase
          .from('order_messages')
          .select('*')
          .order('created_at', ascending: true);
      allChatMessages = List<dynamic>.from(msgsRes);
    } catch (_) {}

    return {
      'suppliers': summaryList,
      'restaurants': restaurantSummaryList,
      'allCommerces': allCommerces,
      'globalOrders': globalOrders,
      'allChatMessages': allChatMessages,
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
      'disputedOrders': disputedOrders,
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

  // --- MODAL: PEDIDOS DEL RESTAURANTE ---
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
                      final double fee3pct = (ord['platform_fee'] as num?)?.toDouble() ??
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
                                Text('Tarifa Abasto (3% incluida): \$${fee3pct.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
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
    final pendingOrders = item['pending_orders'] as List<dynamic>? ?? [];
    final name = item['business_name'];
    final double amount = item['pending_net'];
    final supplierId = item['supplier_id'].toString();

    final refCtrl = TextEditingController();
    String? receiptUrl;
    bool isUploadingReceipt = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirmar Liquidación Transfer365'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¿Confirmas que ya transferiste \$${amount.toStringAsFixed(2)} a $name?',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Banco: ${item['bank_name']} (${item['account_type']})',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text('Cuenta: ${item['account_number']}',
                          style: const TextStyle(fontSize: 13)),
                      Text(
                        'Titular: ${item['holder_name']} • Doc: ${item['holder_doc']}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.subtitleGrey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'N° Referencia Transfer365 / Banco',
                    hintText: 'Ej. TR365-20261117-8842',
                    prefixIcon: Icon(Icons.tag),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                  icon: Icon(
                    receiptUrl != null
                        ? Icons.check_circle
                        : Icons.upload_file_outlined,
                    size: 18,
                    color: receiptUrl != null
                        ? const Color(0xFF16A34A)
                        : AppColors.primaryBlue,
                  ),
                  label: Text(
                    isUploadingReceipt
                        ? 'Subiendo comprobante...'
                        : (receiptUrl != null
                            ? 'Comprobante Adjunto (Cambiar)'
                            : 'Adjuntar Captura / PDF Transferencia (Opcional)'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: isUploadingReceipt
                      ? null
                      : () {
                          final input = html.FileUploadInputElement()
                            ..accept = 'image/*,application/pdf';
                          input.click();
                          input.onChange.listen((_) async {
                            final file = input.files?.first;
                            if (file == null) return;
                            setDialogState(() => isUploadingReceipt = true);
                            try {
                              final reader = html.FileReader();
                              reader.readAsArrayBuffer(file);
                              await reader.onLoad.first;
                              final bytes = reader.result as List<int>;
                              final ext = file.name.split('.').last;
                              final path =
                                  '$supplierId/${DateTime.now().millisecondsSinceEpoch}.$ext';

                              await supabase.storage
                                  .from('payout-receipts')
                                  .uploadBinary(path, bytes as dynamic);
                              final url = supabase.storage
                                  .from('payout-receipts')
                                  .getPublicUrl(path);
                              setDialogState(() {
                                receiptUrl = url;
                                isUploadingReceipt = false;
                              });
                            } catch (e) {
                              setDialogState(() => isUploadingReceipt = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Error subiendo comprobante: $e'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            }
                          });
                        },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploadingReceipt ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A)),
              onPressed: isUploadingReceipt ? null : () => Navigator.pop(ctx, true),
              child: const Text('Sí, Liquidar Semana',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final nowIso = DateTime.now().toUtc().toIso8601String();
        final refText = refCtrl.text.trim();
        final inserts = pendingOrders.map((ord) {
          final totalOrd = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
          final baseOrd = (ord['subtotal'] as num?)?.toDouble() ??
              double.parse(
                  (totalOrd / (1 + _restaurantFeeRate)).toStringAsFixed(2));
          final fee =
              double.parse((baseOrd * _supplierFeeRate).toStringAsFixed(2));
          final net = double.parse((baseOrd - fee).toStringAsFixed(2));

          return {
            'supplier_id': supplierId,
            'order_id': ord['id'],
            'order_code': ord['code'] ?? 'ORD-000',
            'gross_amount': baseOrd,
            'commission_fee': fee,
            'net_payout': net,
            'status': 'liquidado',
            'paid_at': nowIso,
            if (refText.isNotEmpty) 'transfer_reference': refText,
            if (receiptUrl != null) 'receipt_url': receiptUrl,
          };
        }).toList();

        if (inserts.isNotEmpty) {
          await supabase.from('supplier_payouts').insert(inserts);
        }

        _refresh();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Pago de \$${amount.toStringAsFixed(2)} a $name liquidado.'),
              backgroundColor: AppColors.tealMint,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al procesar: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _adminResolveDispute(
      Map<String, dynamic> order, {required bool cancelOrder}) async {
    final actionText = cancelOrder
        ? 'Anular Pedido y Reembolsar al Restaurante'
        : 'Liberar Pedido para Liquidación al Distribuidor';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(actionText,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          cancelOrder
              ? 'La orden ${order['code']} pasará a estado Cancelado y NO se transferirá al distribuidor.'
              : 'La incidencia de ${order['code']} se marcará como resuelta por Administración y el saldo pasará a liquidación.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Volver')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    cancelOrder ? Colors.red : const Color(0xFF16A34A)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar Resolución',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('orders').update({
          'has_incident': false,
          'incident_status': cancelOrder ? 'anulado_admin' : 'resuelta_admin',
          if (cancelOrder) 'status': 'cancelado',
        }).eq('id', order['id'].toString());

        _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Resolución aplicada a ${order['code']}.'),
              backgroundColor: AppColors.tealMint,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Error al resolver disputa: $e'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _exportFridaySettlementCsv() async {
    try {
      final data = await _dataFuture;
      final suppliers = (data['suppliers'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      final rows = suppliers.map((s) {
        return [
          s['business_name'] ?? '',
          s['nrc_nit'] ?? '',
          s['bank_name'] ?? '',
          s['account_type'] ?? '',
          s['account_number'] ?? '',
          s['holder_name'] ?? '',
          s['pending_orders_count'] ?? 0,
          (s['pending_gross'] as double).toStringAsFixed(2),
          (s['pending_fee'] as double).toStringAsFixed(2),
          (s['pending_net'] as double).toStringAsFixed(2),
          (s['already_paid_net'] as double).toStringAsFixed(2),
        ];
      }).toList();

      CsvExporter.downloadCsv(
        filename:
            'Abasto_Corte_Liquidaciones_${DateTime.now().toIso8601String().split('T').first}.csv',
        headers: [
          'Distribuidora',
          'Registro Fiscal',
          'Banco',
          'Tipo Cuenta',
          'Numero Cuenta',
          'Titular',
          'Pedidos Pendientes',
          'Ventas Base (\$)',
          'Comision 5% (\$)',
          'Neto a Transferir (\$)',
          'Historico Liquidado (\$)',
        ],
        rows: rows,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error exportando corte: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- TARJETA DE CONCILIACIÓN BANCARIA ---
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
                Expanded(child: _buildBankSubCard('Ganancia Abasto (3% + 5%)', totalProfit, 'Fondos disponibles', const Color(0xFFECFDF5), const Color(0xFFA7F3D0), const Color(0xFF047857))),
                const SizedBox(width: 12),
                Expanded(child: _buildBankSubCard('Ya Transferido a Distribuidores', totalAlreadyPaid, 'Por Transfer365', const Color(0xFFF1F5F9), const Color(0xFFCBD5E1), AppColors.navyDark)),
              ],
            )
          else
            Column(
              children: [
                _buildBankSubCard('De Distribuidores (Por transferir)', pendingPayouts, 'Corte de viernes (Entregados)', const Color(0xFFFFFBEB), Colors.amber.shade200, Colors.amber.shade900),
                const SizedBox(height: 8),
                _buildBankSubCard('Ganancia Abasto (3% + 5%)', totalProfit, 'Fondos disponibles', const Color(0xFFECFDF5), const Color(0xFFA7F3D0), const Color(0xFF047857)),
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
                      final double ordTotal = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final double ordBase = (ord['subtotal'] as num?)?.toDouble() ??
                          double.parse((ordTotal / (1 + _restaurantFeeRate)).toStringAsFixed(2));
                      final double netPayout = double.parse((ordBase * (1 - _supplierFeeRate)).toStringAsFixed(2));
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

  Widget _buildResponsiveCardGrid({
    required List<Map<String, dynamic>> items,
    required Widget Function(Map<String, dynamic>) itemBuilder,
    required bool isDesktop,
    double desktopExtent = 250,
  }) {
    if (!isDesktop) {
      return Column(
        children: items.map((e) => itemBuilder(e)).toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 14,
        mainAxisExtent: desktopExtent,
      ),
      itemCount: items.length,
      itemBuilder: (_, idx) => itemBuilder(items[idx]),
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

    final disputedOrders = (data['disputedOrders'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (disputedOrders.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.gpp_maybe_outlined,
                        color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Pedidos Retenidos de Liquidación por Incidencia (${disputedOrders.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...disputedOrders.map((d) => Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '• ${d['code']} (${d['restaurant_name']} → ${d['supplier_name']}): ${d['incident_note'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7F1D1D)),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF16A34A),
                                  side: const BorderSide(
                                      color: Color(0xFF16A34A)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                ),
                                icon: const Icon(Icons.check_circle_outline,
                                    size: 14),
                                label: const Text('Liberar Pago',
                                    style: TextStyle(fontSize: 11.5)),
                                onPressed: () => _adminResolveDispute(d,
                                    cancelOrder: false),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                ),
                                icon:
                                    const Icon(Icons.cancel_outlined, size: 14),
                                label: const Text('Anular y Reembolsar',
                                    style: TextStyle(fontSize: 11.5)),
                                onPressed: () =>
                                    _adminResolveDispute(d, cancelOrder: true),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),

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
          child: isDesktop
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar distribuidora o titular de cuenta...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => _searchCtrl.clear())
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                            value: 'con_saldo',
                            label: Text('Por Pagar ($conSaldoCount)')),
                        ButtonSegment(
                            value: 'pagados',
                            label: Text('Pagados ($pagadosCount)')),
                        ButtonSegment(
                            value: 'todos',
                            label: Text('Todos (${allSuppliers.length})')),
                        ButtonSegment(
                            value: 'al_dia',
                            label: Text('Al Día ($alDiaCount)')),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (val) =>
                          setState(() => _statusFilter = val.first),
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor: const Color(0xFF001A2C),
                        selectedForegroundColor: Colors.white,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Buscar distribuidora o titular de cuenta...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => _searchCtrl.clear())
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                              value: 'con_saldo',
                              label: Text('Por Pagar ($conSaldoCount)')),
                          ButtonSegment(
                              value: 'pagados',
                              label: Text('Pagados ($pagadosCount)')),
                          ButtonSegment(
                              value: 'todos',
                              label: Text('Todos (${allSuppliers.length})')),
                          ButtonSegment(
                              value: 'al_dia',
                              label: Text('Al Día ($alDiaCount)')),
                        ],
                        selected: {_statusFilter},
                        onSelectionChanged: (val) =>
                            setState(() => _statusFilter = val.first),
                        style: SegmentedButton.styleFrom(
                          selectedBackgroundColor: const Color(0xFF001A2C),
                          selectedForegroundColor: Colors.white,
                        ),
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
          _buildResponsiveCardGrid(
            items: filtered,
            isDesktop: isDesktop,
            desktopExtent: 285,
            itemBuilder: (item) => _buildSupplierCard(item, isDesktop),
          ),
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
                            Text('Registro Fiscal: ${item['nrc_nit']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryBlue),
),
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
                          const Text('Ventas Catálogo (Insumos):', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
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
                    Expanded(child: _buildBankSubCard('Tarifa Abasto (3% incluida)', totalFees, 'Comisión recaudada', const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), const Color(0xFF1D4ED8))),
                    const SizedBox(width: 12),
                    Expanded(child: _buildBankSubCard('Restaurantes Registrados', allRestaurants.length.toDouble(), 'Clientes activos', const Color(0xFFF8FAFC), const Color(0xFFCBD5E1), AppColors.navyDark)),
                  ],
                )
              else
                Column(
                  children: [
                    _buildBankSubCard('Total Compras Pagadas', totalCollected, 'Ingreso real en órdenes', const Color(0xFFF0FDF4), const Color(0xFFBBF7D0), const Color(0xFF15803D)),
                    const SizedBox(height: 8),
                    _buildBankSubCard('Tarifa Abasto (3% incluida)', totalFees, 'Comisión recaudada', const Color(0xFFEFF6FF), const Color(0xFFBFDBFE), const Color(0xFF1D4ED8)),
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
          _buildResponsiveCardGrid(
            items: filtered,
            isDesktop: isDesktop,
            desktopExtent: 295,
            itemBuilder: (rest) => _buildRestaurantCard(rest, isDesktop),
          ),
      ],
    );
  }

  Widget _buildRestaurantCard(Map<String, dynamic> rest, bool isDesktop) {
    final name = rest['business_name'];
    final double totalPaid = rest['total_paid'];
    final double grossSpent = rest['gross_spent'];
    final double fee3pct = rest['platform_fee_2pct'];
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
                            Text('NRC / NIT: ${rest['nrc_nit']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primaryBlue),
                            ),
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
                        const Text('Tarifa Abasto (3% incluida):', style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
                        Text('\$${fee3pct.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF16A34A))),
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

  Future<void> _toggleCommerceVerification(
      String profileId, String name, bool currentVerified) async {
    try {
      await supabase
          .from('profiles')
          .update({'is_verified': !currentVerified}).eq('id', profileId);

      // Sincronizar también en tablas de detalle si existen
      try {
        await supabase
            .from('supplier_details')
            .update({'is_verified': !currentVerified}).eq('profile_id', profileId);
      } catch (_) {}
      try {
        await supabase
            .from('restaurant_details')
            .update({'is_verified': !currentVerified}).eq('profile_id', profileId);
      } catch (_) {}

      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentVerified
                ? '$name ahora está Verificado en Abasto'
                : 'Se revocó la verificación de $name'),
            backgroundColor:
                !currentVerified ? AppColors.tealMint : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al actualizar verificación: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _adjustPromoCredits(
      Map<String, dynamic> profile, int delta) async {
    final bool isSupplier = profile['role'] == 'supplier';
    final String column = isSupplier
        ? 'supplier_free_commission_orders'
        : 'free_commission_orders';
    final int currentVal = (profile[column] as num?)?.toInt() ?? 0;
    final int nextVal = (currentVal + delta).clamp(0, 99);

    try {
      await supabase
          .from('profiles')
          .update({column: nextVal}).eq('id', profile['id'].toString());
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Créditos 0% comisión de ${profile['business_name']}: $nextVal'),
            duration: const Duration(seconds: 1),
            backgroundColor: AppColors.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error actualizando bonos: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleSupplierFeatured(
      String supplierId, String name, bool currentlyFeatured) async {
    try {
      final nextState = !currentlyFeatured;
      final untilIso = nextState
          ? DateTime.now()
              .add(const Duration(days: 30))
              .toUtc()
              .toIso8601String()
          : null;

      await supabase.from('supplier_details').update({
        'is_featured': nextState,
        'featured_until': untilIso,
      }).eq('profile_id', supplierId);

      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextState
                ? '$name ahora es Distribuidor Destacado por 30 días'
                : 'Se desactivó el espacio Destacado de $name'),
            backgroundColor: nextState ? AppColors.tealMint : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error actualizando destacado: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- SECCIÓN 3: VERIFICACIÓN DE COMERCIOS Y BONOS PROMOCIONALES ---
  Widget _buildCommercesTab(Map<String, dynamic> data, bool isDesktop) {
    final allCommerces = (data['allCommerces'] as List<Map<String, dynamic>>? ?? []);

    final filtered = allCommerces.where((c) {
      final role = (c['role'] ?? '').toString();
      final isVerified = c['is_verified'] == true;
      final name = (c['business_name'] ?? '').toString().toLowerCase();
      final legal = (c['legal_name'] ?? '').toString().toLowerCase();
      final nrc = (c['nrc'] ?? c['nrc_nit'] ?? '').toString().toLowerCase();

      final matchesSearch = _commerceSearchQuery.isEmpty ||
          name.contains(_commerceSearchQuery) ||
          legal.contains(_commerceSearchQuery) ||
          nrc.contains(_commerceSearchQuery);

      bool matchesFilter = true;
      if (_commerceRoleFilter == 'supplier') {
        matchesFilter = role == 'supplier';
      } else if (_commerceRoleFilter == 'restaurant') {
        matchesFilter = role == 'restaurant';
      } else if (_commerceRoleFilter == 'pendiente_verif') {
        matchesFilter = !isVerified;
      }

      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Auditoría B2B, Verificación y Créditos Promocionales',
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _commerceSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar por comercio, razón social o NRC/NIT...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'todos',
                        label: Text('Todos (${allCommerces.length})')),
                    const ButtonSegment(
                        value: 'pendiente_verif', label: Text('Sin Verificar')),
                    const ButtonSegment(
                        value: 'supplier', label: Text('Distribuidores')),
                    const ButtonSegment(
                        value: 'restaurant', label: Text('Restaurantes')),
                  ],
                  selected: {_commerceRoleFilter},
                  onSelectionChanged: (v) =>
                      setState(() => _commerceRoleFilter = v.first),
                ),
              ),
            ],
          ),
        ),
        _buildResponsiveCardGrid(
          items: filtered,
          isDesktop: isDesktop,
          desktopExtent: 265,
          itemBuilder: (c) {
            final isSupplier = c['role'] == 'supplier';
            final isVerified = c['is_verified'] == true;
            final name = c['business_name'] ?? 'Comercio';
            final legalName = (c['legal_name'] ?? '').toString();
            final nrc = (c['nrc'] ?? '').toString();
            final nit = (c['nit'] ?? '').toString();
            final legacy = (c['nrc_nit'] ?? '').toString();
            final credits = (c[isSupplier
                        ? 'supplier_free_commission_orders'
                        : 'free_commission_orders'] as num?)
                    ?.toInt() ??
                0;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: isVerified
                        ? const Color(0xFFA7F3D0)
                        : const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isSupplier
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFE0F2FE),
                          child: Icon(
                            isSupplier ? Icons.storefront : Icons.restaurant,
                            size: 18,
                            color: isSupplier
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF0369A1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.navyDark),
                                    ),
                                  ),
                                  if (isVerified) ...[
                                    const SizedBox(width: 5),
                                    const Icon(Icons.verified,
                                        size: 17, color: AppColors.tealMint),
                                  ],
                                ],
                              ),
                              Text(
                                '${isSupplier ? 'Distribuidor' : 'Restaurante'} • ${c['phone'] ?? ''} • ${c['email'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.subtitleGrey),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: isVerified,
                          activeColor: AppColors.tealMint,
                          onChanged: (_) => _toggleCommerceVerification(
                              c['id'].toString(), name, isVerified),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Text(
                      'Razón Social: ${legalName.isNotEmpty ? legalName : 'No registrada'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      (nrc.isNotEmpty || nit.isNotEmpty)
                          ? 'NRC: ${nrc.isNotEmpty ? nrc : 'N/A'}  •  NIT: ${nit.isNotEmpty ? nit : 'N/A'}'
                          : 'Registro Fiscal: ${legacy.isNotEmpty ? legacy : 'Sin registrar'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pedidos sin comisión disponibles: $credits',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark),
                          ),
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Quitar 1 bono',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red, size: 20),
                                onPressed: credits > 0
                                    ? () => _adjustPromoCredits(c, -1)
                                    : null,
                              ),
                              IconButton(
                                tooltip: 'Otorgar +1 pedido sin comisión',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.add_circle_outline,
                                    color: Color(0xFF16A34A), size: 20),
                                onPressed: () => _adjustPromoCredits(c, 1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isSupplier) ...[
                      const SizedBox(height: 8),
                      Builder(
                        builder: (_) {
                          final until = c['featured_until'] != null
                              ? DateTime.tryParse(
                                  c['featured_until'].toString())
                              : null;
                          final isFeaturedActive = c['is_featured'] == true &&
                              (until == null || until.isAfter(DateTime.now()));
                          return SizedBox(
                            width: double.infinity,
                            height: 34,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isFeaturedActive
                                    ? const Color(0xFF001A2C)
                                    : Colors.white,
                                foregroundColor: isFeaturedActive
                                    ? AppColors.tealMint
                                    : AppColors.navyDark,
                                side: BorderSide(
                                  color: isFeaturedActive
                                      ? AppColors.tealMint
                                      : const Color(0xFFCBD5E1),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.bolt_rounded, size: 16),
                              label: Text(
                                isFeaturedActive
                                    ? 'Destacado Activo (30d) • Desactivar'
                                    : 'Activar Destacado (30 días)',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () => _toggleSupplierFeatured(
                                  c['id'].toString(), name, isFeaturedActive),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // --- SECCIÓN 4: MONITOR GLOBAL DE PEDIDOS Y AUDITORÍA DTE ---
  Widget _buildGlobalOrdersTab(Map<String, dynamic> data, bool isDesktop) {
    final globalOrders = (data['globalOrders'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final missingDteCount = globalOrders.where((o) {
      final st = (o['status'] ?? '').toString().toLowerCase();
      final pdf = (o['dte_pdf_url'] ?? '').toString();
      final code = (o['dte_generation_code'] ?? '').toString();
      return st == 'entregado' && pdf.isEmpty && code.isEmpty;
    }).length;

    final filtered = globalOrders.where((o) {
      final st = (o['status'] ?? '').toString().toLowerCase();
      final pdf = (o['dte_pdf_url'] ?? '').toString();
      final gen = (o['dte_generation_code'] ?? '').toString();
      final code = (o['code'] ?? '').toString().toLowerCase();
      final rest = (o['restaurant_name'] ?? '').toString().toLowerCase();
      final supp = (o['supplier_name'] ?? '').toString().toLowerCase();

      final matchesSearch = _globalOrderSearchQuery.isEmpty ||
          code.contains(_globalOrderSearchQuery) ||
          rest.contains(_globalOrderSearchQuery) ||
          supp.contains(_globalOrderSearchQuery);

      bool matchesFilter = true;
      if (_globalOrderFilter == 'sin_dte') {
        matchesFilter = st == 'entregado' && pdf.isEmpty && gen.isEmpty;
      } else if (_globalOrderFilter == 'pendiente') {
        matchesFilter = st == 'pendiente';
      } else if (_globalOrderFilter == 'entregado') {
        matchesFilter = st == 'entregado';
      }

      return matchesSearch && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Monitor Global de Órdenes y Auditoría DTE',
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _globalOrderSearchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar por ORD-..., restaurante o distribuidor...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                        value: 'todos',
                        label: Text('Todas (${globalOrders.length})')),
                    ButtonSegment(
                        value: 'sin_dte',
                        label: Text('Sin DTE ($missingDteCount)')),
                    const ButtonSegment(
                        value: 'pendiente', label: Text('Sin Pagar')),
                    const ButtonSegment(
                        value: 'entregado', label: Text('Entregadas')),
                  ],
                  selected: {_globalOrderFilter},
                  onSelectionChanged: (v) =>
                      setState(() => _globalOrderFilter = v.first),
                ),
              ),
            ],
          ),
        ),
        _buildResponsiveCardGrid(
          items: filtered,
          isDesktop: isDesktop,
          desktopExtent: 145,
          itemBuilder: (ord) {
            final st = (ord['status'] ?? 'pendiente').toString();
            final total = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
            final dtePdf = (ord['dte_pdf_url'] ?? '').toString();
            final dteCode = (ord['dte_generation_code'] ?? '').toString();
            final hasDte = dtePdf.isNotEmpty || dteCode.isNotEmpty;
            final taxLabel = (ord['tax_document_type'] ?? 'factura') == 'ccf'
                ? 'CCF (DTE-03)'
                : 'Factura (DTE-01)';

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${ord['code']} • $st',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.navyDark),
                        ),
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primaryBlue),
                        ),
                      ],
                    ),
                    Text(
                      '${ord['restaurant_name']}  →  ${ord['supplier_name']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasDte
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            hasDte
                                ? '$taxLabel Adjunto'
                                : '$taxLabel Pendiente de subir',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: hasDte
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                        if (dtePdf.isNotEmpty)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.picture_as_pdf, size: 15),
                            label: const Text('Ver DTE',
                                style: TextStyle(fontSize: 11.5)),
                            onPressed: () =>
                                html.window.open(dtePdf, '_blank'),
                          )
                        else if (st.toLowerCase() == 'entregado')
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.chat,
                                size: 15, color: Color(0xFF25D366)),
                            label: const Text('Recordar DTE',
                                style: TextStyle(fontSize: 11.5)),
                            onPressed: () => _contactViaWhatsApp(
                              (ord['supplier_phone'] ?? '').toString(),
                              (ord['supplier_name'] ?? '').toString(),
                              'Hola ${ord['supplier_name']}, te recordamos subir el $taxLabel de la orden ${ord['code']} en Abasto para completar el respaldo fiscal del restaurante.',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatAdminChatTime(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.parse(raw.toString()).toLocal();
      final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      final min = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month} $h:$min $ampm';
    } catch (_) {
      return '';
    }
  }

  String _formatReadableMessagePreview(String rawText) {
    if (rawText.startsWith('[LOCATION]|')) {
      final parts = rawText.split('|');
      return '📍 Ubicación GPS: ${parts.length > 3 ? parts[3] : 'Coordenadas enviadas'}';
    }
    if (rawText.startsWith('[ADDRESS]|')) {
      return '📍 Dirección: ${rawText.replaceFirst('[ADDRESS]|', '')}';
    }
    if (rawText.startsWith('[IMAGE]|')) {
      return '📷 Fotografía adjunta';
    }
    if (rawText.startsWith('[ETA]|')) {
      return '🚚 Llegada estimada: ${rawText.replaceFirst('[ETA]|', '')}';
    }
    return rawText;
  }

  Widget _buildAdminChatBubble(
      Map<String, dynamic> msg, Map<String, dynamic> order) {
    final senderId = msg['sender_id']?.toString() ?? '';
    final isSupplierSender = senderId == order['supplier_id']?.toString();
    final senderName = (msg['sender_name'] ??
            (isSupplierSender
                ? order['supplier_name']
                : order['restaurant_name']))
        .toString();
    final rawText = (msg['message'] ?? msg['content'] ?? '').toString();
    final timeStr = _formatAdminChatTime(msg['created_at']);

    Widget contentWidget;
    if (rawText.startsWith('[LOCATION]|')) {
      final parts = rawText.split('|');
      final lat = parts.length > 1 ? parts[1] : '13.6929';
      final lng = parts.length > 2 ? parts[2] : '-89.2182';
      final label = parts.length > 3 ? parts[3] : 'Ubicación GPS compartida';
      final mapsUrl =
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
      contentWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 15, color: Colors.red),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isSupplierSender ? Colors.white : AppColors.navyDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.navyDark,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
            ),
            icon: const Icon(Icons.map_outlined, size: 14),
            label: const Text('Abrir en Google Maps',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
            onPressed: () => html.window.open(mapsUrl, '_blank'),
          ),
        ],
      );
    } else if (rawText.startsWith('[IMAGE]|')) {
      final url = rawText.replaceFirst('[IMAGE]|', '').trim();
      contentWidget = InkWell(
        onTap: () => html.window.open(url, '_blank'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            height: 160,
            width: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Text('Imagen no disponible'),
          ),
        ),
      );
    } else if (rawText.startsWith('[ETA]|')) {
      final eta = rawText.replaceFirst('[ETA]|', '').trim();
      contentWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping_rounded,
              size: 16, color: AppColors.tealMint),
          const SizedBox(width: 6),
          Text(
            'Tiempo estimado de llegada: $eta',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isSupplierSender ? Colors.white : AppColors.navyDark,
            ),
          ),
        ],
      );
    } else {
      final cleanText = rawText.startsWith('[ADDRESS]|')
          ? '📍 ${rawText.replaceFirst('[ADDRESS]|', '')}'
          : rawText;
      contentWidget = Text(
        cleanText,
        style: TextStyle(
          fontSize: 13.5,
          color: isSupplierSender ? Colors.white : const Color(0xFF1E293B),
          height: 1.35,
        ),
      );
    }

    return Align(
      alignment:
          isSupplierSender ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSupplierSender ? const Color(0xFF001A2C) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isSupplierSender
              ? null
              : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSupplierSender
                        ? AppColors.tealMint.withOpacity(0.18)
                        : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSupplierSender ? 'DISTRIBUIDOR' : 'RESTAURANTE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: isSupplierSender
                          ? AppColors.tealMint
                          : const Color(0xFF0369A1),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSupplierSender
                          ? Colors.white70
                          : AppColors.subtitleGrey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            contentWidget,
            if (timeStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSupplierSender
                        ? Colors.white60
                        : Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

Widget _buildChatsMonitorTab(Map<String, dynamic> data, bool isDesktop) {
    final List<dynamic> globalOrders = data['globalOrders'] ?? [];
    final List<dynamic> allMessages = data['allChatMessages'] ?? [];

    final Map<String, List<dynamic>> msgsByOrder = {};
    for (final m in allMessages) {
      final oid = m['order_id']?.toString() ?? '';
      if (oid.isEmpty) continue;
      msgsByOrder.putIfAbsent(oid, () => []).add(m);
    }

    // Órdenes que tienen conversación activa, ordenadas por último mensaje
    final threads = globalOrders
        .where((o) => msgsByOrder.containsKey(o['id'].toString()))
        .where((o) {
      if (_chatSearchQuery.isEmpty) return true;
      final code = (o['code'] ?? '').toString().toLowerCase();
      final rest = (o['restaurant_name'] ?? '').toString().toLowerCase();
      final supp = (o['supplier_name'] ?? '').toString().toLowerCase();
      return code.contains(_chatSearchQuery) ||
          rest.contains(_chatSearchQuery) ||
          supp.contains(_chatSearchQuery);
    }).toList();

    threads.sort((a, b) {
      final aLast = msgsByOrder[a['id'].toString()]!.last['created_at'] ?? '';
      final bLast = msgsByOrder[b['id'].toString()]!.last['created_at'] ?? '';
      return bLast.toString().compareTo(aLast.toString());
    });

    if (threads.isNotEmpty &&
        (_selectedChatOrderId == null ||
            !threads.any((t) => t['id'].toString() == _selectedChatOrderId))) {
      _selectedChatOrderId = threads.first['id'].toString();
    }

    Map<String, dynamic>? selectedOrder;
    if (threads.isNotEmpty) {
      selectedOrder = Map<String, dynamic>.from(threads.first);
      for (final t in threads) {
        if (t['id'].toString() == _selectedChatOrderId) {
          selectedOrder = Map<String, dynamic>.from(t);
          break;
        }
      }
    }

    final List<dynamic> selectedMessages = selectedOrder != null
        ? (msgsByOrder[selectedOrder['id'].toString()] ?? [])
        : [];

    Widget threadListPanel = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _chatSearchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar orden, restaurante o distribuidor...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          if (threads.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'Aún no hay conversaciones registradas entre comercios.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
              ),
            )
          else
            SizedBox(
              height: isDesktop ? 520 : 240,
              child: ListView.separated(
                itemCount: threads.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final ord = threads[idx];
                  final oid = ord['id'].toString();
                  final msgs = msgsByOrder[oid] ?? [];
                  final lastMsg = msgs.isNotEmpty ? msgs.last : null;
                  final isSelected = oid == _selectedChatOrderId;
                  final hasIncident = ord['has_incident'] == true;

                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: const Color(0xFFF1F5F9),
                    onTap: () => setState(() => _selectedChatOrderId = oid),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              ord['code'] ?? 'ORD',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: AppColors.navyDark,
                              ),
                            ),
                            if (hasIncident) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'INCIDENCIA',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF001A2C),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${msgs.length}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.tealMint,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          '${ord['restaurant_name']} ↔ ${ord['supplier_name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        if (lastMsg != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _formatReadableMessagePreview(
                                (lastMsg['message'] ?? '').toString()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.subtitleGrey,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );

    Widget conversationPanel = Container(
      height: isDesktop ? 585 : 440,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: selectedOrder == null
          ? const Center(
              child: Text(
                'Selecciona una orden para auditar sus mensajes.',
                style: TextStyle(color: AppColors.subtitleGrey),
              ),
            )
          : Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: const Color(0xFF001A2C),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selectedOrder['code']} • ${selectedOrder['restaurant_name']} ↔ ${selectedOrder['supplier_name']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'Estado: ${(selectedOrder['status'] ?? '').toString().toUpperCase()} • Total: \$${((selectedOrder['total_amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.tealMint,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Chip(
                        backgroundColor: Color(0xFF1B3452),
                        side: BorderSide.none,
                        label: Text(
                          'Solo Lectura',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: selectedMessages.length,
                    itemBuilder: (_, i) => _buildAdminChatBubble(
                      Map<String, dynamic>.from(selectedMessages[i]),
                      selectedOrder!,
                    ),
                  ),
                ),
              ],
            ),
    );

    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 4, child: threadListPanel),
          const SizedBox(width: 18),
          Expanded(flex: 6, child: conversationPanel),
        ],
      );
    }

    return Column(
      children: [
        threadListPanel,
        const SizedBox(height: 14),
        conversationPanel,
      ],
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final navItems = const [
      {
        'icon': Icons.account_balance_wallet_outlined,
        'selectedIcon': Icons.account_balance_wallet,
        'label': 'Liquidaciones',
        'title': 'Liquidación a Distribuidores',
      },
      {
        'icon': Icons.restaurant_outlined,
        'selectedIcon': Icons.restaurant,
        'label': 'Restaurantes',
        'title': 'Cobranza y Restaurantes',
      },
      {
        'icon': Icons.verified_user_outlined,
        'selectedIcon': Icons.verified_user,
        'label': 'Comercios',
        'title': 'Comercios & Bonos',
      },
      {
        'icon': Icons.receipt_long_outlined,
        'selectedIcon': Icons.receipt_long,
        'label': 'Órdenes & DTE',
        'title': 'Monitor Global & DTEs',
      },
      {
        'icon': Icons.forum_outlined,
        'selectedIcon': Icons.forum,
        'label': 'Chats B2B',
        'title': 'Auditoría de Chats B2B',
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          appBar: AppBar(
            backgroundColor: const Color(0xFF001A2C),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              tooltip: 'Volver a la pantalla principal',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
                (route) => false,
              ),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.tealMint.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.admin_panel_settings_rounded,
                      color: AppColors.tealMint, size: 19),
                ),
                const SizedBox(width: 10),
                Text(
                  navItems[_currentNavIndex]['title'] as String,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 18),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onPressed: _exportFridaySettlementCsv,
                  icon: const Icon(Icons.download_rounded, size: 17),
                  label: Text(
                    isDesktop ? 'Exportar Corte Viernes (CSV)' : 'CSV',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Actualizar saldos',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refresh,
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _currentNavIndex,
                  onDestinationSelected: (idx) =>
                      setState(() => _currentNavIndex = idx),
                  destinations: navItems
                      .map((item) => NavigationDestination(
                            icon: Icon(item['icon'] as IconData),
                            selectedIcon:
                                Icon(item['selectedIcon'] as IconData),
                            label: item['label'] as String,
                          ))
                      .toList(),
                ),
          body: Row(
            children: [
              if (isDesktop)
                Container(
                  width: 230,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(18, 20, 18, 8),
                        child: Text(
                          'PANEL ADMINISTRATIVO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                      ),
                      ...navItems.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final item = entry.value;
                        final selected = _currentNavIndex == idx;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Material(
                            color: selected
                                ? const Color(0xFF001A2C)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  setState(() => _currentNavIndex = idx),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      (selected
                                          ? item['selectedIcon']
                                          : item['icon']) as IconData,
                                      color: selected
                                          ? AppColors.tealMint
                                          : const Color(0xFF475569),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item['label'] as String,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: selected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.navyDark,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                      const Spacer(),
                      Container(
                        margin: const EdgeInsets.all(14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Abasto SV • Finanzas',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Conciliación Banco Agrícola y cortes Transfer365.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.subtitleGrey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: FutureBuilder<dynamic>(
                  future: _dataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Error al cargar datos: ${snapshot.error}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      );
                    }

                    final data = snapshot.data ?? {};

                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: ListView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 28 : 14,
                            vertical: 20,
                          ),
                          children: [
                            if (_currentNavIndex == 0)
                              _buildSuppliersTab(data, isDesktop)
                            else if (_currentNavIndex == 1)
                              _buildRestaurantsTab(data, isDesktop)
                            else if (_currentNavIndex == 2)
                              _buildCommercesTab(data, isDesktop)
                            else if (_currentNavIndex == 3)
                              _buildGlobalOrdersTab(data, isDesktop)
                            else
                              _buildChatsMonitorTab(data, isDesktop),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
