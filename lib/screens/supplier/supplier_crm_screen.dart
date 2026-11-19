import 'dart:convert';
import 'dart:html' as html;
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
  String _selectedClientZone = 'Todas';
  bool _isLoading = true;

  // KPIs actuales
  double _totalRevenue = 0.0;
  int _ordersCount = 0;
  double _averageTicket = 0.0;
  String _topClientName = 'N/A';
  double _topClientShare = 0.0;

  // Variaciones vs período anterior (%)
  double? _revenueDeltaPct;
  double? _ordersDeltaPct;
  double? _ticketDeltaPct;

  // Listas para gráficas y exportación
  List<dynamic> _rawOrders = [];
  List<dynamic> _topProducts = [];
  List<dynamic> _topClients = [];
  List<dynamic> _categorySales = [];
  List<dynamic> _timelineBars = [];
  List<dynamic> _retentionAlerts = [];

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

  List<DateTime?> _getPeriodRanges() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case SupplierTimePeriod.thisWeek:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final prevMonday = monday.subtract(const Duration(days: 7));
        return [monday, prevMonday];
      case SupplierTimePeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final prevStart = DateTime(now.year, now.month - 1, 1);
        return [start, prevStart];
      case SupplierTimePeriod.last3Months:
        final start = DateTime(now.year, now.month - 2, 1);
        final prevStart = DateTime(now.year, now.month - 5, 1);
        return [start, prevStart];
      case SupplierTimePeriod.allTime:
        return [null, null];
    }
  }

  double? _calcPctChange(double current, double previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous) * 100;
  }

  Future<void> _fetchSupplierCrmData() async {
    setState(() => _isLoading = true);

    try {
      final ranges = _getPeriodRanges();
      final startDate = ranges[0];
      final prevStartDate = ranges[1];

      // Traemos historial de despachos entregados para calcular tendencias y retención de clientes
      var query = supabase
          .from('orders')
          .select('''
            id,
            code,
            total_amount,
            subtotal,
            platform_fee,
            restaurant_id,
            status,
            created_at,
            order_items (
              product_id,
              product_name,
              quantity,
              unit_price
            )
          ''')
          .eq('supplier_id', _currentUserId)
          .eq('status', 'entregado');

      if (_selectedPeriod != SupplierTimePeriod.allTime && prevStartDate != null) {
        query = query.gte('created_at', prevStartDate.toIso8601String());
      }

      final res = await query.order('created_at', ascending: false);
      final allFetchedOrders = List<dynamic>.from(res);

      final List<dynamic> currentOrders = [];
      final List<dynamic> prevOrders = [];

      for (var o in allFetchedOrders) {
        final createdAt = DateTime.tryParse(o['created_at']?.toString() ?? '');
        if (startDate == null || createdAt == null) {
          currentOrders.add(o);
        } else if (!createdAt.isBefore(startDate)) {
          currentOrders.add(o);
        } else if (prevStartDate != null && !createdAt.isBefore(prevStartDate)) {
          prevOrders.add(o);
        }
      }

      // Métricas período anterior
      double prevRevenue = 0.0;
      for (var o in prevOrders) {
        prevRevenue += (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      }
      final prevCount = prevOrders.length;
      final prevAvg = prevCount > 0 ? prevRevenue / prevCount : 0.0;

      // Métricas período actual
      double revenue = 0.0;
      final Map<String, double> productMap = {};
      final Map<String, String> productIdToName = {};
      final Map<String, Map<String, dynamic>> clientStatsMap = {};
      final Map<String, double> timelineMap = {};

      for (var o in currentOrders) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        revenue += total;

        final rId = o['restaurant_id']?.toString() ?? 'Desconocido';
        if (!clientStatsMap.containsKey(rId)) {
          clientStatsMap[rId] = {'count': 0, 'total': 0.0};
        }
        clientStatsMap[rId]!['count'] =
            (clientStatsMap[rId]!['count'] as int) + 1;
        clientStatsMap[rId]!['total'] =
            (clientStatsMap[rId]!['total'] as double) + total;

        final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
        if (dt != null) {
          final key = (_selectedPeriod == SupplierTimePeriod.thisWeek ||
                  _selectedPeriod == SupplierTimePeriod.thisMonth)
              ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}'
              : '${_monthShort(dt.month)} ${dt.year.toString().substring(2)}';
          timelineMap[key] = (timelineMap[key] ?? 0.0) + total;
        }

        final items = (o['order_items'] as List<dynamic>?) ?? [];
        for (var it in items) {
          final pName = (it['product_name'] ?? 'Insumo').toString();
          final pId = it['product_id']?.toString();
          if (pId != null && pId.isNotEmpty) {
            productIdToName[pName] = pId;
          }
          final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
          final price = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          productMap[pName] = (productMap[pName] ?? 0.0) + (qty * price);
        }
      }

      // Obtener nombres de todos los restaurantes (actuales e históricos para retención)
      final allClientIds = allFetchedOrders
          .map((o) => o['restaurant_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty && id != 'Desconocido')
          .toSet()
          .toList();
      final Map<String, String> clientNames = {};
      final Map<String, String> clientLocations = {};

      if (allClientIds.isNotEmpty) {
        try {
          final profs = await supabase
              .from('profiles')
              .select('id, business_name, address, location')
              .filter('id', 'in', allClientIds);

          for (var p in (profs as List<dynamic>)) {
            final pid = p['id'].toString();
            clientNames[pid] =
                p['business_name']?.toString() ?? 'Restaurante';
            clientLocations[pid] = (p['location'] ?? p['address'] ?? 'Sin zona')
                .toString();
          }
        } catch (_) {}
      }

      // Categorías de productos vendidos
      final Map<String, double> categoryMap = {};
      final uniqueProductIds = productIdToName.values.toSet().toList();
      final Map<String, String> productCategories = {};

      if (uniqueProductIds.isNotEmpty) {
        try {
          final prods = await supabase
              .from('products')
              .select('id, category')
              .filter('id', 'in', uniqueProductIds);
          for (var pr in (prods as List<dynamic>)) {
            productCategories[pr['id'].toString()] =
                (pr['category']?.toString().trim().isNotEmpty == true)
                    ? pr['category'].toString()
                    : 'General';
          }
        } catch (_) {}
      }

      productMap.forEach((pName, amount) {
        final pId = productIdToName[pName];
        final cat = (pId != null && productCategories.containsKey(pId))
            ? productCategories[pId]!
            : _inferCategory(pName);
        categoryMap[cat] = (categoryMap[cat] ?? 0.0) + amount;
      });

      // Alertas de Retención de Clientes (Restaurantes que suelen reordenar y están próximos o atrasados)
      final Map<String, List<DateTime>> clientDates = {};
      for (var o in allFetchedOrders) {
        final rId = o['restaurant_id']?.toString() ?? '';
        final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
        if (rId.isEmpty || dt == null) continue;
        clientDates.putIfAbsent(rId, () => []).add(dt);
      }

      final List<dynamic> retention = [];
      final now = DateTime.now();
      clientDates.forEach((rId, dates) {
        if (dates.length >= 2) {
          dates.sort((a, b) => a.compareTo(b));
          int totalDaysDiff = 0;
          for (int i = 1; i < dates.length; i++) {
            totalDaysDiff += dates[i].difference(dates[i - 1]).inDays.clamp(1, 90);
          }
          final avgDays = (totalDaysDiff / (dates.length - 1)).round();
          final daysSinceLast = now.difference(dates.last).inDays;

          if (avgDays > 0 && daysSinceLast >= (avgDays - 1)) {
            retention.add({
              'name': clientNames[rId] ?? 'Restaurante',
              'avgDays': avgDays,
              'daysSinceLast': daysSinceLast,
              'ordersCount': dates.length,
            });
          }
        }
      });

      // Ordenamientos
      final sortedProducts = productMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final sortedClients = clientStatsMap.entries.toList()
        ..sort((a, b) =>
            (b.value['total'] as double).compareTo(a.value['total'] as double));

      final sortedCategories = categoryMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      String topClient = 'N/A';
      double topShare = 0.0;
      if (sortedClients.isNotEmpty && revenue > 0) {
        final topEntry = sortedClients.first;
        topClient = clientNames[topEntry.key] ?? 'Restaurante';
        topShare = ((topEntry.value['total'] as double) / revenue) * 100;
      }

      final avgTicket =
          currentOrders.isNotEmpty ? (revenue / currentOrders.length) : 0.0;

      for (var o in currentOrders) {
        final rId = o['restaurant_id']?.toString() ?? '';
        o['client_name'] = clientNames[rId] ?? 'Restaurante';
      }

      if (mounted) {
        setState(() {
          _rawOrders = currentOrders;
          _totalRevenue = revenue;
          _ordersCount = currentOrders.length;
          _averageTicket = avgTicket;
          _topClientName = topClient;
          _topClientShare = topShare;

          _revenueDeltaPct = _selectedPeriod == SupplierTimePeriod.allTime
              ? null
              : _calcPctChange(revenue, prevRevenue);
          _ordersDeltaPct = _selectedPeriod == SupplierTimePeriod.allTime
              ? null
              : _calcPctChange(
                  currentOrders.length.toDouble(), prevCount.toDouble());
          _ticketDeltaPct = _selectedPeriod == SupplierTimePeriod.allTime
              ? null
              : _calcPctChange(avgTicket, prevAvg);

          _topProducts = sortedProducts
              .map((e) => {'name': e.key, 'amount': e.value})
              .toList();

          _topClients = sortedClients
              .map((e) => {
                    'id': e.key,
                    'name':
                        '${clientNames[e.key] ?? 'Restaurante'} (${clientLocations[e.key] ?? ''})',
                    'zone': clientLocations[e.key] ?? '',
                    'orders_count': e.value['count'],
                    'amount': e.value['total'],
                  })
              .toList();

          _categorySales = sortedCategories
              .map((e) => {'name': e.key, 'amount': e.value})
              .toList();

          _timelineBars = timelineMap.entries
              .toList()
              .reversed
              .map((e) => {'label': e.key, 'amount': e.value})
              .toList();

          _retentionAlerts = retention;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica distribuidor: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _inferCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('plato') ||
        lower.contains('bandeja') ||
        lower.contains('tenedor') ||
        lower.contains('vaso') ||
        lower.contains('bolsa')) {
      return 'Empaques y Desechables';
    }
    if (lower.contains('pollo') ||
        lower.contains('carne') ||
        lower.contains('res') ||
        lower.contains('cerdo')) {
      return 'Carnes y Proteínas';
    }
    if (lower.contains('tomate') ||
        lower.contains('cebolla') ||
        lower.contains('papa') ||
        lower.contains('lechuga')) {
      return 'Frutas y Verduras';
    }
    return 'Insumos Generales';
  }

  String _monthShort(int m) {
    const months = [
      '',
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic'
    ];
    return months[m.clamp(1, 12)];
  }

  void _exportCsvReport() {
    if (_rawOrders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No hay despachos entregados en este período para exportar.'),
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln(
        'Codigo Despacho,Fecha,Cliente Restaurante,Estado,Subtotal Venta USD,Total Facturado USD');

    for (var o in _rawOrders) {
      final code = o['code'] ?? '';
      final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
      final dateStr = dt != null
          ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
          : '';
      final client =
          (o['client_name'] ?? 'Restaurante').toString().replaceAll(',', ' ');
      final status = (o['status'] ?? '').toString();
      final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      final subtotal = (o['subtotal'] as num?)?.toDouble() ?? (total / 1.03);

      buffer.writeln(
        '$code,$dateStr,$client,$status,${subtotal.toStringAsFixed(2)},${total.toStringAsFixed(2)}',
      );
    }

    final bytes = utf8.encode('\uFEFF${buffer.toString()}');
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download',
          'Reporte_Ventas_Abasto_${DateTime.now().millisecondsSinceEpoch}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte de ventas CSV descargado.'),
        backgroundColor: AppColors.tealMint,
      ),
    );
  }

  Widget _buildDeltaBadge(double? deltaPct) {
    if (deltaPct == null) return const SizedBox.shrink();
    final isUp = deltaPct >= 0;
    final Color badgeColor =
        isUp ? AppColors.tealMint : const Color(0xFF64748B);
    final Color textColor =
        isUp ? const Color(0xFF0F766E) : const Color(0xFF475569);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${isUp ? '▲ +' : '▼ '}${deltaPct.toStringAsFixed(0)}% vs. anterior',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    String? subtitle,
    double? deltaPct,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDark.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.subtitleGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: AppColors.navyDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (deltaPct != null)
            _buildDeltaBadge(deltaPct)
          else if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.subtitleGrey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimelineChart() {
    final maxVal = _timelineBars.isNotEmpty
        ? _timelineBars
            .map((e) => (e['amount'] as num).toDouble())
            .reduce((a, b) => a > b ? a : b)
        : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                'Evolución de Facturación',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              Icon(Icons.bar_chart_rounded,
                  color: AppColors.navyDark, size: 20),
            ],
          ),
          const SizedBox(height: 16),
          if (_timelineBars.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Aún no hay despachos entregados en este período.',
                  style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _timelineBars.map((bar) {
                  final label = bar['label'].toString();
                  final amount = (bar['amount'] as num).toDouble();
                  final ratio =
                      maxVal > 0 ? (amount / maxVal).clamp(0.08, 1.0) : 0.08;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '\$${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 100 * ratio,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.tealMint,
                                  AppColors.navyDark,
                                ],
                              ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.subtitleGrey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRetentionAlertsSection() {
    if (_retentionAlerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryBlue.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDark.withOpacity(0.03),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Seguimiento de Clientes Recurrentes',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._retentionAlerts.take(3).map((alert) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.schedule,
                      size: 15, color: AppColors.primaryBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF334155)),
                        children: [
                          TextSpan(
                            text: alert['name'].toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' suele reabastecerse cada ${alert['avgDays']} días (último despacho hace ${alert['daysSinceLast']} días).',
                          ),
                        ],
                      ),
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

  Widget _buildBarsSection({
    required String title,
    required List<dynamic> items,
    required Color barColor,
    required IconData itemIcon,
    bool isClient = false,
  }) {
    final maxAmount =
        items.isNotEmpty ? (items.first['amount'] as num).toDouble() : 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
              final name = it['name']?.toString() ?? '';
              final amount = (it['amount'] as num).toDouble();
              final ordersCount = it['orders_count'];
              final progress =
                  maxAmount > 0 ? (amount / maxAmount).clamp(0.0, 1.0) : 0.0;

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
                            color: barColor == AppColors.tealMint
                                ? const Color(0xFF0F766E)
                                : barColor,
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
                        backgroundColor: const Color(0xFFF1F5F9),
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
          TextButton.icon(
            onPressed: _exportCsvReport,
            icon: const Icon(Icons.download_rounded,
                size: 18, color: AppColors.navyDark),
            label: const Text(
              'Exportar CSV',
              style: TextStyle(
                color: AppColors.navyDark,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
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
                                selectedBackgroundColor: AppColors.navyDark,
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

                          // 2. Alertas de Retención de Clientes Recurrentes
                          _buildRetentionAlertsSection(),

                          // 3. Tarjetas de Métricas (KPIs)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 750;
                              return GridView.count(
                                crossAxisCount: isDesktop ? 4 : 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                childAspectRatio: isDesktop ? 1.35 : 1.25,
                                children: [
                                  _buildKpiCard(
                                    title: 'Facturación Total',
                                    value:
                                        '\$${_totalRevenue.toStringAsFixed(2)}',
                                    icon: Icons.payments_outlined,
                                    iconColor: AppColors.tealMint,
                                    deltaPct: _revenueDeltaPct,
                                  ),
                                  _buildKpiCard(
                                    title: 'Despachos Realizados',
                                    value: '$_ordersCount',
                                    icon: Icons.local_shipping_outlined,
                                    iconColor: AppColors.primaryBlue,
                                    deltaPct: _ordersDeltaPct,
                                  ),
                                  _buildKpiCard(
                                    title: 'Ticket Promedio Venta',
                                    value:
                                        '\$${_averageTicket.toStringAsFixed(2)}',
                                    icon: Icons.analytics_outlined,
                                    iconColor: AppColors.navyDark,
                                    subtitle: 'Por cada despacho',
                                    deltaPct: _ticketDeltaPct,
                                  ),
                                  _buildKpiCard(
                                    title: 'Cliente Principal',
                                    value: _topClientName,
                                    icon: Icons.storefront_outlined,
                                    iconColor: const Color(0xFF32668E),
                                    subtitle: _topClientShare > 0
                                        ? '${_topClientShare.toStringAsFixed(0)}% de tus ingresos'
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // 4. Evolución de Facturación + Ventas por Categoría
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;
                              final timelineWidget = _buildTimelineChart();
                              final categoryWidget = _buildBarsSection(
                                title: 'Ventas por Categoría',
                                items: _categorySales,
                                barColor: const Color(0xFF32668E),
                                itemIcon: Icons.category_outlined,
                              );

                              if (isDesktop) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: timelineWidget),
                                    const SizedBox(width: 20),
                                    Expanded(flex: 2, child: categoryWidget),
                                  ],
                                );
                              }

                              return Column(
                                children: [
                                  timelineWidget,
                                  const SizedBox(height: 20),
                                  categoryWidget,
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),

                          // 5. Rankings de Productos Vendidos y Restaurantes Clientes
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;

                              final productsWidget = _buildBarsSection(
                                title: 'Insumos Más Vendidos',
                                items: _topProducts,
                                barColor: AppColors.navyDark,
                                itemIcon: Icons.inventory_2_outlined,
                              );

                              final zoneAliases = <String, List<String>>{
                                'Santa Tecla': [
                                  'santa tecla',
                                  'quezaltepec',
                                  'merliot',
                                  'delicias',
                                  'alpes suizos',
                                  'pinares',
                                  'utila',
                                  'santa teresa',
                                ],
                                'Antiguo Cuscatlán': [
                                  'antiguo cuscatlan',
                                  'santa elena',
                                  'sultana',
                                  'madreselva',
                                  'laguna',
                                  'cima',
                                ],
                                'San Salvador': [
                                  'san salvador',
                                  'escalon',
                                  'san benito',
                                  'miramonte',
                                  'flor blanca',
                                  'altamira',
                                  'medica',
                                ],
                                'Soyapango': [
                                  'soyapango',
                                  'ilopango',
                                  'venecia',
                                  'sierra morena',
                                ],
                              };

                              final filteredClients = _selectedClientZone ==
                                      'Todas'
                                  ? _topClients
                                  : _topClients.where((c) {
                                      final zText = (c['zone'] ?? '')
                                          .toString()
                                          .toLowerCase()
                                          .replaceAll('á', 'a')
                                          .replaceAll('é', 'e')
                                          .replaceAll('í', 'i')
                                          .replaceAll('ó', 'o')
                                          .replaceAll('ú', 'u');
                                      final keys =
                                          zoneAliases[_selectedClientZone] ??
                                              [
                                                _selectedClientZone
                                                    .toLowerCase()
                                              ];
                                      return keys.any((k) => zText.contains(k));
                                    }).toList();

                              final clientsWidget = Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        'Todas',
                                        'Santa Tecla',
                                        'Antiguo Cuscatlán',
                                        'San Salvador',
                                        'Soyapango',
                                      ].map((z) {
                                        final sel = _selectedClientZone == z;
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(right: 6),
                                          child: ChoiceChip(
                                            label: Text(z,
                                                style: const TextStyle(
                                                    fontSize: 11.5)),
                                            selected: sel,
                                            selectedColor: AppColors.navyDark,
                                            labelStyle: TextStyle(
                                              color: sel
                                                  ? Colors.white
                                                  : AppColors.navyDark,
                                            ),
                                            onSelected: (_) => setState(
                                                () => _selectedClientZone = z),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                  _buildBarsSection(
                                    title:
                                        'Top Restaurantes (Frecuencia y Monto)',
                                    items: filteredClients,
                                    barColor: AppColors.tealMint,
                                    itemIcon: Icons.restaurant_outlined,
                                    isClient: true,
                                  ),
                                ],
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