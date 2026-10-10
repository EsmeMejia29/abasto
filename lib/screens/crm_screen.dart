import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';

enum TimePeriod { thisWeek, thisMonth, last3Months, allTime }

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  RealtimeChannel? _realtimeSubscription;
  TimePeriod _selectedPeriod = TimePeriod.thisMonth;
  bool _isLoading = true;

  double _totalSpent = 0.0;
  int _ordersCount = 0;
  double _averageTicket = 0.0;
  String _topSupplierName = 'N/A';
  double _topSupplierShare = 0.0;

  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topSuppliers = [];

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchCrmData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    _realtimeSubscription = supabase
        .channel('public:restaurant_crm_orders_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) _fetchCrmData();
          },
        )
        .subscribe();
  }

  DateTime? _getPeriodStartDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case TimePeriod.thisWeek:
        // Lunes de la semana actual
        final daysToSubtract = now.weekday - 1;
        final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysToSubtract));
        return monday;
      case TimePeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case TimePeriod.last3Months:
        return DateTime(now.year, now.month - 2, 1);
      case TimePeriod.allTime:
        return null;
    }
  }

  Future<void> _fetchCrmData() async {
    setState(() => _isLoading = true);

    try {
      final startDate = _getPeriodStartDate();
      var query = supabase
          .from('orders')
          .select('''
            id,
            total_amount,
            supplier_id,
            status,
            created_at,
            order_items (
              product_name,
              quantity,
              unit_price
            )
          ''')
          .eq('restaurant_id', _currentUserId)
          .neq('status', 'cancelado');

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }

      final res = await query.order('created_at', ascending: false);
      final orders = List<Map<String, dynamic>>.from(res);

      double spent = 0.0;
      final productMap = <String, double>{};
      final supplierExpenseMap = <String, double>{};

      for (var o in orders) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        spent += total;

        final sId = o['supplier_id']?.toString() ?? 'Desconocido';
        supplierExpenseMap[sId] = (supplierExpenseMap[sId] ?? 0.0) + total;

        final items = (o['order_items'] as List<dynamic>?) ?? [];
        for (var it in items) {
          final pName = (it['product_name'] ?? 'Insumo').toString();
          final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
          final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          final subtotal = qty * price;
          productMap[pName] = (productMap[pName] ?? 0.0) + subtotal;
        }
      }

      // Obtener nombres de distribuidores
      final supplierIds = supplierExpenseMap.keys.where((id) => id != 'Desconocido').toList();
      final supplierNames = <String, String>{};

      if (supplierIds.isNotEmpty) {
        try {
          final profs = await supabase
              .from('profiles')
              .select('id, business_name')
              .filter('id', 'in', supplierIds);

          for (var p in (profs as List<dynamic>)) {
            supplierNames[p['id'].toString()] = p['business_name']?.toString() ?? 'Distribuidor';
          }
        } catch (_) {}
      }

      // Ordenar productos de mayor a menor
      final sortedProducts = productMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Ordenar distribuidores de mayor a menor
      final sortedSuppliers = supplierExpenseMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      String topSupplier = 'N/A';
      double topShare = 0.0;
      if (sortedSuppliers.isNotEmpty && spent > 0) {
        final topEntry = sortedSuppliers.first;
        topSupplier = supplierNames[topEntry.key] ?? 'Distribuidor';
        topShare = (topEntry.value / spent) * 100;
      }

      if (mounted) {
        setState(() {
          _totalSpent = spent;
          _ordersCount = orders.length;
          _averageTicket = orders.isNotEmpty ? (spent / orders.length) : 0.0;
          _topSupplierName = topSupplier;
          _topSupplierShare = topShare;

          _topProducts = sortedProducts.map((e) => {
            'name': e.key,
            'amount': e.value,
          }).toList();

          _topSuppliers = sortedSuppliers.map((e) => {
            'id': e.key,
            'name': supplierNames[e.key] ?? 'Distribuidor',
            'amount': e.value,
          }).toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.subtitleGrey,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarsSection({
    required String title,
    required List<Map<String, dynamic>> items,
    required Color barColor,
    required IconData itemIcon,
  }) {
    final maxAmount = items.isNotEmpty ? (items.first['amount'] as double) : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No hay registros para este periodo.',
                  style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
                ),
              ),
            )
          else
            ...items.map((it) {
              final name = it['name'] ?? '';
              final amount = it['amount'] as double;
              final progress = maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(itemIcon, size: 14, color: barColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.navyDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '\$${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: barColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: Colors.grey.shade100,
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('CRM & Analítica'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCrmData,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchCrmData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Selector de Periodos
                          Center(
                            child: SegmentedButton<TimePeriod>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: TimePeriod.thisWeek,
                                  label: Text('Semana'),
                                ),
                                ButtonSegment(
                                  value: TimePeriod.thisMonth,
                                  label: Text('Este Mes'),
                                ),
                                ButtonSegment(
                                  value: TimePeriod.last3Months,
                                  label: Text('3 Meses'),
                                ),
                                ButtonSegment(
                                  value: TimePeriod.allTime,
                                  label: Text('Histórico'),
                                ),
                              ],
                              selected: {_selectedPeriod},
                              onSelectionChanged: (val) {
                                setState(() {
                                  _selectedPeriod = val.first;
                                });
                                _fetchCrmData();
                              },
                              style: SegmentedButton.styleFrom(
                                selectedBackgroundColor: AppColors.primaryBlue,
                                selectedForegroundColor: Colors.white,
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF475569),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // 2. Tarjetas de Métricas (KPIs)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 750;
                              return GridView.count(
                                crossAxisCount: isDesktop ? 4 : 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: isDesktop ? 1.4 : 1.3,
                                children: [
                                  _buildKpiCard(
                                    title: 'Gasto Total',
                                    value: '\$${_totalSpent.toStringAsFixed(2)}',
                                    icon: Icons.account_balance_wallet_outlined,
                                    iconColor: const Color(0xFF26A69A),
                                  ),
                                  _buildKpiCard(
                                    title: 'Pedidos Hechos',
                                    value: '$_ordersCount',
                                    icon: Icons.receipt_long_outlined,
                                    iconColor: AppColors.primaryBlue,
                                  ),
                                  _buildKpiCard(
                                    title: 'Ticket Promedio',
                                    value: '\$${_averageTicket.toStringAsFixed(2)}',
                                    icon: Icons.query_stats_outlined,
                                    iconColor: Colors.purple,
                                    subtitle: 'Por cada compra',
                                  ),
                                  _buildKpiCard(
                                    title: 'Mayor Proveedor',
                                    value: _topSupplierName,
                                    icon: Icons.local_shipping_outlined,
                                    iconColor: Colors.orange.shade800,
                                    subtitle: _topSupplierShare > 0
                                        ? '${_topSupplierShare.toStringAsFixed(0)}% del presupuesto'
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // 3. Gráficos de barras (2 Columnas en desktop, 1 en mobile)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;

                              final productsWidget = _buildBarsSection(
                                title: 'Insumos Más Pedidos (Monto)',
                                items: _topProducts,
                                barColor: AppColors.primaryBlue,
                                itemIcon: Icons.shopping_basket_outlined,
                              );

                              final suppliersWidget = _buildBarsSection(
                                title: 'Distribuidores Principales',
                                items: _topSuppliers,
                                barColor: const Color(0xFF26A69A),
                                itemIcon: Icons.storefront_outlined,
                              );

                              if (isDesktop) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: productsWidget),
                                    const SizedBox(width: 20),
                                    Expanded(child: suppliersWidget),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  productsWidget,
                                  const SizedBox(height: 20),
                                  suppliersWidget,
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}