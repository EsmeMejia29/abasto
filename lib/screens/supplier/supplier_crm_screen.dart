import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';
import '../../config/session_manager.dart';

enum SupplierTimePeriod { thisWeek, thisMonth, last3Months, allTime }

class SupplierCrmScreen extends StatefulWidget {
  const SupplierCrmScreen({super.key});

  @override
  State<SupplierCrmScreen> createState() => _SupplierCrmScreenState();
}

class _SupplierCrmScreenState extends State<SupplierCrmScreen> {
  RealtimeChannel? _realtimeSubscription;
  SupplierTimePeriod _selectedPeriod = SupplierTimePeriod.thisMonth;
  bool _isLoading = true;

  double _totalRevenue = 0.0;
  int _ordersCount = 0;
  double _averageTicket = 0.0;
  String _topClientName = 'N/A';
  double _topClientShare = 0.0;

  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topClients = [];

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _fetchSupplierCrmData();
    _setupRealtime();
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    _realtimeSubscription = supabase
        .channel('public:supplier_crm_orders_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (_) {
            if (mounted) _fetchSupplierCrmData();
          },
        )
        .subscribe();
  }

  DateTime? _getPeriodStartDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case SupplierTimePeriod.thisWeek:
        final daysToSubtract = now.weekday - 1;
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: daysToSubtract));
        return monday;
      case SupplierTimePeriod.thisMonth:
        return DateTime(now.year, now.month, 1);
      case SupplierTimePeriod.last3Months:
        return DateTime(now.year, now.month - 2, 1);
      case SupplierTimePeriod.allTime:
        return null;
    }
  }

  Future<void> _fetchSupplierCrmData() async {
    setState(() => _isLoading = true);

    try {
      final startDate = _getPeriodStartDate();
      var query = supabase
          .from('orders')
          .select('''
            id,
            total_amount,
            restaurant_id,
            status,
            created_at,
            order_items (
              product_name,
              quantity,
              unit_price
            )
          ''')
          .eq('supplier_id', _currentUserId)
          .neq('status', 'cancelado');

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }

      final res = await query.order('created_at', ascending: false);
      final orders = List<Map<String, dynamic>>.from(res);

      double revenue = 0.0;
      final productMap = <String, double>{};
      final clientStatsMap = <String, Map<String, dynamic>>{};

      for (var o in orders) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        revenue += total;

        final rId = o['restaurant_id']?.toString() ?? 'Desconocido';
        if (!clientStatsMap.containsKey(rId)) {
          clientStatsMap[rId] = {'count': 0, 'total': 0.0};
        }
        clientStatsMap[rId]!['count'] = (clientStatsMap[rId]!['count'] as int) + 1;
        clientStatsMap[rId]!['total'] = (clientStatsMap[rId]!['total'] as double) + total;

        final items = (o['order_items'] as List<dynamic>?) ?? [];
        for (var it in items) {
          final pName = (it['product_name'] ?? 'Insumo').toString();
          final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
          final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          final subtotal = qty * price;
          productMap[pName] = (productMap[pName] ?? 0.0) + subtotal;
        }
      }

      // Obtener nombres reales de los restaurantes
      final clientIds = clientStatsMap.keys.where((id) => id != 'Desconocido').toList();
      final clientNames = <String, String>{};

      if (clientIds.isNotEmpty) {
        try {
          final profs = await supabase
              .from('profiles')
              .select('id, business_name')
              .filter('id', 'in', clientIds);

          for (var p in (profs as List<dynamic>)) {
            clientNames[p['id'].toString()] =
                p['business_name']?.toString() ?? 'Restaurante';
          }
        } catch (_) {}
      }

      // Ordenar productos por facturación
      final sortedProducts = productMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Ordenar clientes por monto total comprado
      final sortedClients = clientStatsMap.entries.toList()
        ..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double));

      String topClient = 'N/A';
      double topShare = 0.0;
      if (sortedClients.isNotEmpty && revenue > 0) {
        final topEntry = sortedClients.first;
        topClient = clientNames[topEntry.key] ?? 'Restaurante';
        topShare = ((topEntry.value['total'] as double) / revenue) * 100;
      }

      if (mounted) {
        setState(() {
          _totalRevenue = revenue;
          _ordersCount = orders.length;
          _averageTicket = orders.isNotEmpty ? (revenue / orders.length) : 0.0;
          _topClientName = topClient;
          _topClientShare = topShare;

          _topProducts = sortedProducts.map((e) => {
            'name': e.key,
            'amount': e.value,
          }).toList();

          _topClients = sortedClients.map((e) => {
            'id': e.key,
            'name': clientNames[e.key] ?? 'Restaurante',
            'orders_count': e.value['count'],
            'amount': e.value['total'],
          }).toList();

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica distribuidor: $e");
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
    bool isClient = false,
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
              final ordersCount = it['orders_count'];
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
                          isClient && ordersCount != null
                              ? '$ordersCount pedidos (\$${amount.toStringAsFixed(2)})'
                              : '\$${amount.toStringAsFixed(2)}',
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
        title: const Text('CRM & Rendimiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchSupplierCrmData,
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
                    onRefresh: _fetchSupplierCrmData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Selector de Periodos
                          Center(
                            child: SegmentedButton<SupplierTimePeriod>(
                              showSelectedIcon: false,
                              segments: const [
                                ButtonSegment(
                                  value: SupplierTimePeriod.thisWeek,
                                  label: Text('Semana'),
                                ),
                                ButtonSegment(
                                  value: SupplierTimePeriod.thisMonth,
                                  label: Text('Este Mes'),
                                ),
                                ButtonSegment(
                                  value: SupplierTimePeriod.last3Months,
                                  label: Text('3 Meses'),
                                ),
                                ButtonSegment(
                                  value: SupplierTimePeriod.allTime,
                                  label: Text('Histórico'),
                                ),
                              ],
                              selected: {_selectedPeriod},
                              onSelectionChanged: (val) {
                                setState(() {
                                  _selectedPeriod = val.first;
                                });
                                _fetchSupplierCrmData();
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

                          // 2. Tarjetas de Métricas (KPIs para Distribuidor)
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
                                    title: 'Facturación Total',
                                    value: '\$${_totalRevenue.toStringAsFixed(2)}',
                                    icon: Icons.payments_outlined,
                                    iconColor: const Color(0xFF26A69A),
                                  ),
                                  _buildKpiCard(
                                    title: 'Despachos Realizados',
                                    value: '$_ordersCount',
                                    icon: Icons.local_shipping_outlined,
                                    iconColor: AppColors.primaryBlue,
                                  ),
                                  _buildKpiCard(
                                    title: 'Ticket Promedio Venta',
                                    value: '\$${_averageTicket.toStringAsFixed(2)}',
                                    icon: Icons.analytics_outlined,
                                    iconColor: Colors.purple,
                                    subtitle: 'Por cada despacho',
                                  ),
                                  _buildKpiCard(
                                    title: 'Cliente Principal',
                                    value: _topClientName,
                                    icon: Icons.storefront_outlined,
                                    iconColor: Colors.orange.shade800,
                                    subtitle: _topClientShare > 0
                                        ? '${_topClientShare.toStringAsFixed(0)}% de tus ingresos'
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // 3. Dos Columnas en Computadora / Vertical en Celular
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;

                              final productsWidget = _buildBarsSection(
                                title: 'Insumos Más Vendidos',
                                items: _topProducts,
                                barColor: AppColors.primaryBlue,
                                itemIcon: Icons.inventory_2_outlined,
                              );

                              final clientsWidget = _buildBarsSection(
                                title: 'Top Restaurantes (Frecuencia y Monto)',
                                items: _topClients,
                                barColor: const Color(0xFF26A69A),
                                itemIcon: Icons.restaurant_outlined,
                                isClient: true,
                              );

                              if (isDesktop) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: productsWidget),
                                    const SizedBox(width: 20),
                                    Expanded(child: clientsWidget),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  productsWidget,
                                  const SizedBox(height: 20),
                                  clientsWidget,
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