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
  String _searchQuery = '';
  
  // Filtros principales
  String _statusFilter = 'con_saldo'; // 'con_saldo', 'pagados', 'todos', 'al_dia'
  String _weekFilter = 'todas';       // 'todas', 'esta_semana', 'semana_1', 'semana_2', 'semana_3', 'semana_4'
  bool _showCalendar = true;          // Ocultar/Mostrar calendario
  
  DateTime _calendarMonth = DateTime.now();
  String? _selectedDateIso; // Fecha seleccionada en formato YYYY-MM-DD

  static const double _restaurantFeeRate = 0.02; // 2% al restaurante
  static const double _supplierFeeRate = 0.05;   // 5% al distribuidor

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetchSettlementsAndBankBalance();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
    // 1. Distribuidores registrados
    final profilesRes = await supabase
        .from('profiles')
        .select('*')
        .eq('role', 'supplier')
        .order('business_name', ascending: true);

    final suppliers = List<Map<String, dynamic>>.from(profilesRes);
    final supplierIds = suppliers.map((s) => s['id'].toString()).toList();
    final Map<String, String> supplierNamesMap = {
      for (var s in suppliers) s['id'].toString(): s['business_name']?.toString() ?? 'Distribuidor'
    };

    // 2. Órdenes entregadas reales
    final ordersRes = await supabase
        .from('orders')
        .select('id, code, supplier_id, restaurant_id, total_amount, status, created_at')
        .filter('supplier_id', 'in', supplierIds)
        .eq('status', 'entregado')
        .order('created_at', ascending: false);

    final deliveredOrders = List<Map<String, dynamic>>.from(ordersRes);

    // Obtener nombres de los restaurantes
    final restaurantIds = deliveredOrders
        .map((o) => o['restaurant_id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .toSet()
        .toList();

    final Map<String, String> restaurantNamesMap = {};
    if (restaurantIds.isNotEmpty) {
      try {
        final restProfiles = await supabase
            .from('profiles')
            .select('id, business_name')
            .filter('id', 'in', restaurantIds);

        for (var p in (restProfiles as List<dynamic>)) {
          restaurantNamesMap[p['id'].toString()] =
              p['business_name']?.toString() ?? 'Restaurante';
        }
      } catch (_) {}
    }

    // 3. Pagos ya transferidos registrados en supplier_payouts
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

    // 4. Mapear pedidos por fecha ISO para el calendario
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

    // 5. Agrupar órdenes pendientes por distribuidor
    final Map<String, List<Map<String, dynamic>>> pendingOrdersBySupplier = {};
    for (var ord in deliveredOrders) {
      final ordId = ord['id'].toString();
      final suppId = ord['supplier_id'].toString();

      if (paidOrderIds.contains(ordId)) continue;

      if (!pendingOrdersBySupplier.containsKey(suppId)) {
        pendingOrdersBySupplier[suppId] = [];
      }
      pendingOrdersBySupplier[suppId]!.add(ord);
    }

    // 6. Resumen consolidado por distribuidora
    final List<Map<String, dynamic>> summaryList = [];
    double totalPendingToPayOut = 0.0;
    double totalHistoricalGross = 0.0;
    double totalHistoricalAlreadyPaid = 0.0;

    for (var s in suppliers) {
      final sId = s['id'].toString();
      final suppPendingOrders = pendingOrdersBySupplier[sId] ?? [];
      final suppPaidRecords = paidPayoutsBySupplier[sId] ?? [];

      // Pendiente actual
      double pendingGross = 0.0;
      final List<DateTime> pendingDates = [];
      for (var ord in suppPendingOrders) {
        pendingGross += (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
        if (ord['created_at'] != null) {
          final d = DateTime.tryParse(ord['created_at'].toString())?.toLocal();
          if (d != null) pendingDates.add(d);
        }
      }
      final double pendingFee = pendingGross * _supplierFeeRate;
      final double pendingNet = pendingGross - pendingFee;
      totalPendingToPayOut += pendingNet;

      // Ya transferido históricamente
      double alreadyPaidNet = 0.0;
      double alreadyPaidGross = 0.0;
      DateTime? lastPaidDate;
      final List<DateTime> paidDates = [];

      for (var pr in suppPaidRecords) {
        alreadyPaidNet += (pr['net_payout'] as num?)?.toDouble() ?? 0.0;
        alreadyPaidGross += (pr['gross_amount'] as num?)?.toDouble() ?? 0.0;
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

      totalHistoricalGross += (pendingGross + alreadyPaidGross);
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

    final double realTotalInflows = totalHistoricalGross * (1 + _restaurantFeeRate);
    final double totalPlatformProfit = totalHistoricalGross * (_restaurantFeeRate + _supplierFeeRate);
    final double shouldBeInBankNow = realTotalInflows - totalHistoricalAlreadyPaid;

    return {
      'suppliers': summaryList,
      'bankTotalInflows': realTotalInflows,
      'shouldBeInBankNow': shouldBeInBankNow,
      'totalPendingToPayOut': totalPendingToPayOut,
      'totalPlatformProfit': totalPlatformProfit,
      'totalHistoricalAlreadyPaid': totalHistoricalAlreadyPaid,
      'orderDatesIso': orderDatesIso,
      'paymentDatesIso': paymentDatesIso,
      'ordersByDate': ordersByDate,
      'nextFriday': _getNextPayoutFriday(),
    };
  }

  // Verifica si una lista de fechas coincide con el filtro de semana seleccionado
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

  Widget _buildOperationsCalendar(Map<String, dynamic> data) {
    final Set<String> orderDates = data['orderDatesIso'] ?? {};
    final Set<String> paymentDates = data['paymentDatesIso'] ?? {};
    final Map<String, List<Map<String, dynamic>>> ordersByDate = data['ordersByDate'] ?? {};
    final DateTime nextFriday = data['nextFriday'] ?? _getNextPayoutFriday();
    final String nextFridayIso =
        '${nextFriday.year}-${nextFriday.month.toString().padLeft(2, '0')}-${nextFriday.day.toString().padLeft(2, '0')}';

    final daysInMonth = DateUtils.getDaysInMonth(_calendarMonth.year, _calendarMonth.month);
    final firstDayWeekday = DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday; // 1 = Lunes

    const monthNames = [
      'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
      'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
    ];

    final selectedOrders = _selectedDateIso != null ? (ordersByDate[_selectedDateIso] ?? []) : <Map<String, dynamic>>[];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
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
              Row(
                children: [
                  const Icon(Icons.calendar_month, color: AppColors.primaryBlue, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Calendario de Entregas y Liquidaciones - ${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark),
                  ),
                ],
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
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendItem(const Color(0xFF2563EB), 'Día de Pedidos Recibidos'),
              _buildLegendItem(const Color(0xFF16A34A), 'Día en que se Transfirió Dinero'),
              _buildLegendItem(Colors.amber.shade700, 'Próximo Corte de Pago (Viernes)'),
            ],
          ),
          const SizedBox(height: 16),

          // Días de la semana
          Row(
            children: const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const Divider(height: 16),

          // Grilla de días
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: (firstDayWeekday - 1) + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 44,
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontWeight: (hasOrder || hasPayment || isNextFriday || isSelected)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      if (hasOrder || hasPayment || isNextFriday)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (hasOrder)
                              Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Color(0xFF2563EB), shape: BoxShape.circle)),
                            if (hasPayment)
                              Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle)),
                            if (isNextFriday)
                              Container(width: 5, height: 5, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: Colors.amber.shade700, shape: BoxShape.circle)),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          // PANEL DESPLEGABLE: Lista de pedidos del día seleccionado
          if (_selectedDateIso != null) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
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
                      Row(
                        children: [
                          const Icon(Icons.receipt_long, color: AppColors.primaryBlue, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Pedidos del $_selectedDateIso (${selectedOrders.length})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.navyDark),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _selectedDateIso = null),
                        tooltip: 'Cerrar detalle',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (selectedOrders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No hubo órdenes entregadas en este día específico.',
                        style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
                      ),
                    )
                  else ...[
                    ...selectedOrders.map((ord) {
                      final code = ord['code'] ?? 'ORD-000';
                      final supplierName = ord['supplier_name'] ?? 'Distribuidor';
                      final restaurantName = ord['restaurant_name'] ?? 'Restaurante';
                      final double amount = (ord['total_amount'] as num?)?.toDouble() ?? 0.0;
                      final double fee = amount * _supplierFeeRate;
                      final double netPayout = amount - fee;
                      final bool isPaid = ord['is_paid'] == true;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      code,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navyDark),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPaid ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        isPaid ? 'Liquidado' : 'Por Liquidar',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isPaid ? const Color(0xFF16A34A) : const Color(0xFFB45309),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Distribuidor: $supplierName',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                ),
                                Text(
                                  'Cliente: $restaurantName',
                                  style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Bruto: \$${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey),
                                ),
                                Text(
                                  'Neto: \$${netPayout.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                                ),
                                Text(
                                  'Comisión (5%): -\$${fee.toStringAsFixed(2)}',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFF0284C7)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Total Facturado el Día: \$${selectedOrders.fold<double>(0.0, (acc, cur) => acc + ((cur['total_amount'] as num?)?.toDouble() ?? 0.0)).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navyDark),
                        ),
                      ],
                    ),
                  ],
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
      ],
    );
  }

  Widget _buildBankReconciliationCard(Map<String, dynamic> data) {
    final double shouldBeInBank = data['shouldBeInBankNow'] ?? 0.0;
    final double pendingPayouts = data['totalPendingToPayOut'] ?? 0.0;
    final double totalProfit = data['totalPlatformProfit'] ?? 0.0;
    final double totalAlreadyPaid = data['totalHistoricalAlreadyPaid'] ?? 0.0;

    final double totalReference = shouldBeInBank > 0 ? shouldBeInBank : 1.0;
    final double supplierRatio = (pendingPayouts / totalReference).clamp(0.0, 1.0);
    final double profitRatio = (totalProfit / totalReference).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
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
                        'Cuenta Banco Agrícola (Cálculo sobre entregas reales)',
                        style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Saldo que DEBE haber en tu cuenta hoy:',
                      style: TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                  Text(
                    '\$${shouldBeInBank.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 14,
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
          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'De Distribuidores (Por transferir)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${pendingPayouts.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                      const Text('Dinero en custodia (Corte viernes)',
                          style: TextStyle(fontSize: 10, color: Color(0xFFB45309))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ganancia Abasto (2% + 5%)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${totalProfit.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                      ),
                      const Text('Fondos propios disponibles',
                          style: TextStyle(fontSize: 10, color: Color(0xFF059669))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ya Transferido a Distribuidores',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${totalAlreadyPaid.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                      ),
                      const Text('Completado por Transfer365',
                          style: TextStyle(fontSize: 10, color: AppColors.subtitleGrey)),
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

  Future<void> _requestBankInfoWhatsApp(Map<String, dynamic> item) async {
    final rawPhone = (item['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
    final name = item['business_name'];
    final double amount = item['pending_net'];

    if (rawPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta distribuidora no tiene un número registrado.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final formattedPhone = rawPhone.startsWith('503') ? rawPhone : '503$rawPhone';
    final message = Uri.encodeComponent(
      '¡Hola $name! Te saludamos desde Abasto El Salvador. '
      'Tenemos listo tu pago semanal de \$${amount.toStringAsFixed(2)} por las entregas completadas en la plataforma. '
      'Por favor, proporciónanos tu cuenta bancaria (Banco, tipo y titular) en la app para emitirte la transferencia bancaria.',
    );

    final url = Uri.parse('https://wa.me/$formattedPhone?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _requestBankInfoEmail(Map<String, dynamic> item) async {
    final email = (item['email'] ?? '').toString().trim();
    final name = item['business_name'];
    final double amount = item['pending_net'];

    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay correo registrado.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final subject = Uri.encodeComponent('Liquidación semanal Abasto - \$${amount.toStringAsFixed(2)}');
    final body = Uri.encodeComponent(
      'Estimado equipo de $name,\n\n'
      'Te notificamos que tienes un saldo acumulado de \$${amount.toStringAsFixed(2)} en Abasto por pedidos entregados.\n\n'
      'Por favor registra tus datos bancarios en tu perfil para emitirte la transferencia bancaria.\n\n'
      'Saludos cordiales,\nEquipo de Finanzas Abasto SV',
    );

    final url = Uri.parse('mailto:$email?subject=$subject&body=$body');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  void _showSupplierDetailsModal(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront, color: AppColors.primaryBlue, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      item['business_name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyDark),
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Teléfono / WhatsApp', style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(item['phone'].toString().isNotEmpty ? item['phone'] : 'No registrado',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.email_outlined, color: AppColors.primaryBlue),
              title: const Text('Correo Electrónico', style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(item['email'].toString().isNotEmpty ? item['email'] : 'No registrado',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.location_on_outlined, color: Colors.redAccent),
              title: const Text('Dirección Comercial', style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(item['address'], style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined, color: Colors.orange),
              title: const Text('NIT / NRC', style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
              subtitle: Text(item['nrc_nit'], style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
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
            Text(
              '¿Confirmas que ya transferiste \$${amount.toStringAsFixed(2)} a $name?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Banco: ${item['bank_name']} (${item['account_type']})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Cuenta: ${item['account_number']}', style: const TextStyle(fontSize: 13)),
                  Text('Titular: ${item['holder_name']} • Doc: ${item['holder_doc']}',
                      style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
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
          final fee = gross * _supplierFeeRate;
          final net = gross - fee;

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
            SnackBar(
              content: Text('Pago de \$${amount.toStringAsFixed(2)} a $name marcado como transferido.'),
              backgroundColor: AppColors.tealMint,
            ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Liquidación Semanal a Distribuidores'),
        actions: [
          IconButton(tooltip: 'Actualizar saldos', icon: const Icon(Icons.refresh), onPressed: _refresh),
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
          final List<Map<String, dynamic>> allSuppliers = data['suppliers'] ?? [];

          int conSaldoCount = 0;
          int pagadosCount = 0;
          int alDiaCount = 0;

          for (var s in allSuppliers) {
            if (s['has_balance'] == true) conSaldoCount++;
            if (s['is_paid_out'] == true) pagadosCount++;
            if (s['has_balance'] == false) alDiaCount++;
          }

          // Filtrado multidimensional: Estado + Semana + Búsqueda de texto
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

            // Filtrado por fechas de semana
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

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1150),
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // 1. Tarjeta con Conciliación Bancaria
                  _buildBankReconciliationCard(data),

                  // Barra con botón para Ocultar / Mostrar Calendario
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.event_note, color: AppColors.primaryBlue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Calendario y Flujo de Fechas',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: AppColors.primaryBlue),
                        icon: Icon(_showCalendar ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                        label: Text(_showCalendar ? 'Ocultar Calendario' : 'Mostrar Calendario'),
                        onPressed: () => setState(() => _showCalendar = !_showCalendar),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 2. Calendario de Operaciones (Plegable)
                  if (_showCalendar) _buildOperationsCalendar(data),

                  // 3. BARRA DE FILTROS AVANZADA
                  Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Buscador
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Buscar distribuidora o titular de cuenta...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchCtrl.clear())
                                : null,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Filtros por Estado
                        const Text(
                          'Estado de liquidación:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(value: 'con_saldo', label: Text('Por Pagar ($conSaldoCount)')),
                              ButtonSegment(value: 'pagados', label: Text('Pagos Realizados ($pagadosCount)')),
                              ButtonSegment(value: 'todos', label: Text('Todas (${allSuppliers.length})')),
                              ButtonSegment(value: 'al_dia', label: Text('Al Día ($alDiaCount)')),
                            ],
                            selected: {_statusFilter},
                            onSelectionChanged: (val) => setState(() => _statusFilter = val.first),
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: AppColors.primaryBlue,
                              selectedForegroundColor: Colors.white,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Filtros por Semana del Mes
                        const Text(
                          'Filtrar por período semanal:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Wrap(
                            spacing: 8,
                            children: [
                              _buildWeekFilterChip('Cualquier semana', 'todas'),
                              _buildWeekFilterChip('Esta semana en curso', 'esta_semana'),
                              _buildWeekFilterChip('Semana 1 (Días 1-7)', 'semana_1'),
                              _buildWeekFilterChip('Semana 2 (Días 8-14)', 'semana_2'),
                              _buildWeekFilterChip('Semana 3 (Días 15-21)', 'semana_3'),
                              _buildWeekFilterChip('Semana 4+ (Días 22+)', 'semana_4'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 4. Listado de Distribuidoras
                  if (filtered.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      alignment: Alignment.center,
                      child: Column(
                        children: const [
                          Icon(Icons.check_circle_outline, size: 54, color: Colors.green),
                          SizedBox(height: 12),
                          Text('No hay distribuidoras que coincidan con estos filtros.',
                              style: TextStyle(color: AppColors.subtitleGrey, fontSize: 14)),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((item) {
                      final name = item['business_name'];
                      final double pendingToPay = item['pending_net'];
                      final double pendingGross = item['pending_gross'];
                      final double pendingFee = item['pending_fee'];
                      final double alreadyPaid = item['already_paid_net'];
                      final DateTime? lastPaidDate = item['last_paid_date'];
                      final int count = item['pending_orders_count'];
                      final bool hasBalance = item['has_balance'];
                      final hasBankConfigured = item['account_number'] != 'Sin registrar' &&
                          item['bank_name'] != 'No configurado' &&
                          item['account_number'].toString().trim().isNotEmpty;

                      return Card(
                        elevation: 1.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: hasBalance ? AppColors.primaryBlue.withOpacity(0.3) : const Color(0xFFE2E8F0),
                            width: hasBalance ? 1.5 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: hasBalance ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                        child: Icon(Icons.storefront,
                                            color: hasBalance ? const Color(0xFF16A34A) : Colors.grey, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(name,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDark)),
                                              const SizedBox(width: 6),
                                              InkWell(
                                                onTap: () => _showSupplierDetailsModal(item),
                                                child: const Icon(Icons.info_outline, size: 16, color: AppColors.primaryBlue),
                                              ),
                                            ],
                                          ),
                                          Text('${item['phone']} • ${item['email']}',
                                              style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        hasBalance ? 'Pendiente por Transferir' : 'Estado de Cuenta',
                                        style: const TextStyle(fontSize: 11, color: AppColors.subtitleGrey),
                                      ),
                                      Text(
                                        '\$${(hasBalance ? pendingToPay : 0.0).toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: hasBalance ? const Color(0xFF16A34A) : Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 20),

                              // Estado de Transferencia Previa
                              if (alreadyPaid > 0) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF5),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFA7F3D0)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Ya transferido: \$${alreadyPaid.toStringAsFixed(2)}${lastPaidDate != null ? ' (Última: ${lastPaidDate.day}/${lastPaidDate.month}/${lastPaidDate.year})' : ''}',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF065F46)),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('Transferido', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Desglose de liquidación pendiente
                              if (hasBalance) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Ventas Brutas Pendientes:', style: TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                                            const SizedBox(height: 2),
                                            Text('\$${pendingGross.toStringAsFixed(2)} ($count pedidos)', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Comisión Abasto (5% Retenido):', style: TextStyle(fontSize: 11, color: AppColors.subtitleGrey)),
                                            const SizedBox(height: 2),
                                            Text('-\$${pendingFee.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Datos Bancarios
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: hasBankConfigured ? const Color(0xFFF1F5F9) : const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: hasBankConfigured ? const Color(0xFFCBD5E1) : Colors.amber.shade300),
                                ),
                                child: hasBankConfigured
                                    ? Row(
                                        children: [
                                          const Icon(Icons.account_balance, color: AppColors.primaryBlue, size: 24),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${item['bank_name']} (${item['account_type']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.navyDark)),
                                                const SizedBox(height: 2),
                                                Text('No. Cuenta: ${item['account_number']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                                Text('Titular: ${item['holder_name']} • Doc: ${item['holder_doc']}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                                              ],
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: const [
                                              Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 22),
                                              SizedBox(width: 8),
                                              Text('Sin cuenta bancaria registrada por la distribuidora', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB45309))),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          const Text('Solicita los datos de transferencia:', style: TextStyle(fontSize: 12, color: Color(0xFF78350F))),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                                icon: const Icon(Icons.chat, size: 16),
                                                label: const Text('Pedir Cuenta por WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                onPressed: () => _requestBankInfoWhatsApp(item),
                                              ),
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryBlue, side: const BorderSide(color: AppColors.primaryBlue), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                                icon: const Icon(Icons.email_outlined, size: 16),
                                                label: const Text('Enviar Correo', style: TextStyle(fontSize: 12)),
                                                onPressed: () => _requestBankInfoEmail(item),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                              ),

                              if (hasBalance) ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 42,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: hasBankConfigured ? const Color(0xFF16A34A) : Colors.grey.shade400,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.check_circle_outline, size: 18),
                                    label: Text(
                                      hasBankConfigured
                                          ? 'Marcar Transferencia de \$${pendingToPay.toStringAsFixed(2)} como Realizada'
                                          : 'Registra los datos bancarios para liquidar (\$${pendingToPay.toStringAsFixed(2)})',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    onPressed: hasBankConfigured ? () => _markAsTransferred(item) : null,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildWeekFilterChip(String label, String value) {
    final isSelected = _weekFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : const Color(0xFF475569),
      ),
      selectedColor: const Color(0xFF26A69A),
      backgroundColor: const Color(0xFFF1F5F9),
      onSelected: (val) {
        if (val) setState(() => _weekFilter = value);
      },
    );
  }
}