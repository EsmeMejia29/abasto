import 'dart:convert';
import 'dart:html' as html;
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

  double? _spentDeltaPct;
  double? _ordersDeltaPct;
  double? _ticketDeltaPct;

  List<dynamic> _rawOrders = [];
  List<dynamic> _topProducts = [];
  List<dynamic> _topSuppliers = [];
  List<dynamic> _categorySpend = [];
  List<dynamic> _timelineBars = [];
  List<dynamic> _reorderAlerts = [];
  List<dynamic> _priceVariations = [];

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

  List<DateTime?> _getPeriodRanges() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case TimePeriod.thisWeek:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final prevMonday = monday.subtract(const Duration(days: 7));
        return [monday, prevMonday];
      case TimePeriod.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final prevStart = DateTime(now.year, now.month - 1, 1);
        return [start, prevStart];
      case TimePeriod.last3Months:
        final start = DateTime(now.year, now.month - 2, 1);
        final prevStart = DateTime(now.year, now.month - 5, 1);
        return [start, prevStart];
      case TimePeriod.allTime:
        return [null, null];
    }
  }

  double? _calcPctChange(double current, double previous) {
    if (previous <= 0) return null;
    return ((current - previous) / previous) * 100;
  }

  Future<void> _fetchCrmData() async {
    setState(() => _isLoading = true);

    try {
      final ranges = _getPeriodRanges();
      final startDate = ranges[0];
      final prevStartDate = ranges[1];

      var query = supabase
          .from('orders')
          .select('''
            id,
            code,
            total_amount,
            subtotal,
            platform_fee,
            supplier_id,
            status,
            created_at,
            order_items (
              product_id,
              product_name,
              quantity,
              unit_price
            )
          ''')
          .eq('restaurant_id', _currentUserId)
          .neq('status', 'cancelado');

      if (_selectedPeriod != TimePeriod.allTime && prevStartDate != null) {
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

      double prevSpent = 0.0;
      for (var o in prevOrders) {
        prevSpent += (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      }
      final prevCount = prevOrders.length;
      final prevAvg = prevCount > 0 ? prevSpent / prevCount : 0.0;

      double spent = 0.0;
      final Map<String, double> productMap = {};
      final Map<String, String> productIdToName = {};
      final Map<String, double> supplierExpenseMap = {};
      final Map<String, double> timelineMap = {};

      for (var o in currentOrders) {
        final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
        spent += total;

        final sId = o['supplier_id']?.toString() ?? 'Desconocido';
        supplierExpenseMap[sId] = (supplierExpenseMap[sId] ?? 0.0) + total;

        final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
        if (dt != null) {
          final key = (_selectedPeriod == TimePeriod.thisWeek ||
                  _selectedPeriod == TimePeriod.thisMonth)
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

      final supplierIds =
          supplierExpenseMap.keys.where((id) => id != 'Desconocido').toList();
      final Map<String, String> supplierNames = {};

      if (supplierIds.isNotEmpty) {
        try {
          final profs = await supabase
              .from('profiles')
              .select('id, business_name')
              .filter('id', 'in', supplierIds);

          for (var p in (profs as List<dynamic>)) {
            supplierNames[p['id'].toString()] =
                p['business_name']?.toString() ?? 'Distribuidor';
          }
        } catch (_) {}
      }

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

      final Map<String, List<DateTime>> productDates = {};
      for (var o in allFetchedOrders) {
        final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
        if (dt == null) continue;
        final items = (o['order_items'] as List<dynamic>?) ?? [];
        for (var it in items) {
          final pName = (it['product_name'] ?? '').toString();
          if (pName.isEmpty) continue;
          productDates.putIfAbsent(pName, () => []).add(dt);
        }
      }

      final List<dynamic> alerts = [];
      final now = DateTime.now();
      productDates.forEach((pName, dates) {
        if (dates.length >= 2) {
          dates.sort((a, b) => a.compareTo(b));
          int totalDaysDiff = 0;
          for (int i = 1; i < dates.length; i++) {
            totalDaysDiff += dates[i].difference(dates[i - 1]).inDays.clamp(1, 90);
          }
          final avgDays = (totalDaysDiff / (dates.length - 1)).round();
          final daysSinceLast = now.difference(dates.last).inDays;

          if (avgDays > 0 && daysSinceLast >= (avgDays - 2)) {
            alerts.add({
              'name': pName,
              'avgDays': avgDays,
              'daysSinceLast': daysSinceLast,
              'ordersCount': dates.length,
            });
          }
        }
      });

      final sortedProducts = productMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final sortedSuppliers = supplierExpenseMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final sortedCategories = categoryMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      String topSupplier = 'N/A';
      double topShare = 0.0;
      if (sortedSuppliers.isNotEmpty && spent > 0) {
        final topEntry = sortedSuppliers.first;
        topSupplier = supplierNames[topEntry.key] ?? 'Distribuidor';
        topShare = (topEntry.value / spent) * 100;
      }

      final avgTicket =
          currentOrders.isNotEmpty ? (spent / currentOrders.length) : 0.0;

      for (var o in currentOrders) {
        final sId = o['supplier_id']?.toString() ?? '';
        o['supplier_name'] = supplierNames[sId] ?? 'Distribuidor';
      }

      // Calcular variación de precio unitario promedio vs período anterior
      final Map<String, List<double>> currPricesByProd = {};
      final Map<String, List<double>> prevPricesByProd = {};

      for (final o in currentOrders) {
        for (final it in ((o['order_items'] as List<dynamic>?) ?? [])) {
          final pName = (it['product_name'] ?? '').toString().trim();
          final uPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          if (pName.isNotEmpty && uPrice > 0) {
            currPricesByProd.putIfAbsent(pName, () => []).add(uPrice);
          }
        }
      }

      for (final o in prevOrders) {
        for (final it in ((o['order_items'] as List<dynamic>?) ?? [])) {
          final pName = (it['product_name'] ?? '').toString().trim();
          final uPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
          if (pName.isNotEmpty && uPrice > 0) {
            prevPricesByProd.putIfAbsent(pName, () => []).add(uPrice);
          }
        }
      }

      final List<dynamic> variations = [];
      currPricesByProd.forEach((pName, currList) {
        final prevList = prevPricesByProd[pName];
        if (prevList != null && prevList.isNotEmpty) {
          final currAvg = currList.reduce((a, b) => a + b) / currList.length;
          final prevAvg = prevList.reduce((a, b) => a + b) / prevList.length;
          if (prevAvg > 0) {
            final diffPct = ((currAvg - prevAvg) / prevAvg) * 100;
            if (diffPct.abs() >= 1.0) {
              variations.add({
                'name': pName,
                'currPrice': currAvg,
                'prevPrice': prevAvg,
                'diffPct': diffPct,
              });
            }
          }
        }
      });
      variations.sort((a, b) => (b['diffPct'] as double)
          .abs()
          .compareTo((a['diffPct'] as double).abs()));

      if (mounted) {
        setState(() {
          _rawOrders = currentOrders;
          _totalSpent = spent;
          _ordersCount = currentOrders.length;
          _averageTicket = avgTicket;
          _topSupplierName = topSupplier;
          _topSupplierShare = topShare;

          _spentDeltaPct = _selectedPeriod == TimePeriod.allTime
              ? null
              : _calcPctChange(spent, prevSpent);
          _ordersDeltaPct = _selectedPeriod == TimePeriod.allTime
              ? null
              : _calcPctChange(currentOrders.length.toDouble(), prevCount.toDouble());
          _ticketDeltaPct = _selectedPeriod == TimePeriod.allTime
              ? null
              : _calcPctChange(avgTicket, prevAvg);

          _topProducts = sortedProducts
              .map((e) => {'name': e.key, 'amount': e.value})
              .toList();

          _topSuppliers = sortedSuppliers
              .map((e) => {
                    'id': e.key,
                    'name': supplierNames[e.key] ?? 'Distribuidor',
                    'amount': e.value,
                  })
              .toList();

          _categorySpend = sortedCategories
              .map((e) => {'name': e.key, 'amount': e.value})
              .toList();

          _timelineBars = timelineMap.entries
              .toList()
              .reversed
              .map((e) => {'label': e.key, 'amount': e.value})
              .toList();

          _reorderAlerts = alerts;
          _priceVariations = variations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica: $e");
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
          content: Text('No hay compras registradas en este período para exportar.'),
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Codigo Orden,Fecha,Distribuidor,Estado,Subtotal USD,Tarifa Abasto USD,Total USD');

    for (var o in _rawOrders) {
      final code = o['code'] ?? '';
      final dt = DateTime.tryParse(o['created_at']?.toString() ?? '')?.toLocal();
      final dateStr = dt != null
          ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
          : '';
      final supplier = (o['supplier_name'] ?? 'Distribuidor').toString().replaceAll(',', ' ');
      final status = (o['status'] ?? '').toString();
      final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
      final subtotal = (o['subtotal'] as num?)?.toDouble() ?? (total / 1.03);
      final fee = (o['platform_fee'] as num?)?.toDouble() ?? (total - subtotal);

      buffer.writeln(
        '$code,$dateStr,$supplier,$status,${subtotal.toStringAsFixed(2)},${fee.toStringAsFixed(2)},${total.toStringAsFixed(2)}',
      );
    }

    final bytes = utf8.encode('\uFEFF${buffer.toString()}');
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Reporte_Gastos_Abasto_${DateTime.now().millisecondsSinceEpoch}.csv')
      ..click();
    html.Url.revokeObjectUrl(url);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reporte contable CSV descargado.'),
        backgroundColor: AppColors.tealMint,
      ),
    );
  }

  Widget _buildDeltaBadge(double? deltaPct, {bool invertColors = false}) {
    if (deltaPct == null) return const SizedBox.shrink();
    final isUp = deltaPct >= 0;
    final Color badgeColor = invertColors
        ? (isUp ? AppColors.tealMint : const Color(0xFF64748B))
        : (isUp ? const Color(0xFF32668E) : AppColors.tealMint);

    final Color textColor = badgeColor == AppColors.tealMint
        ? const Color(0xFF0F766E)
        : AppColors.navyDark;

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
    bool invertDeltaColors = false,
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
            _buildDeltaBadge(deltaPct, invertColors: invertDeltaColors)
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
                'Evolución de Compras en el Tiempo',
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
                  'Aún no hay compras para graficar en este período.',
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
                                  AppColors.primaryBlue,
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

  Widget _buildReorderAlertsSection() {
    if (_reorderAlerts.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.tealMint.withOpacity(0.45)),
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
                  color: AppColors.tealMint.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: Color(0xFF0F766E),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Sugerencia de Reabastecimiento',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._reorderAlerts.take(3).map((alert) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.autorenew,
                      size: 15, color: AppColors.tealMint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF334155)),
                        children: [
                          const TextSpan(text: 'Sueles pedir '),
                          TextSpan(
                            text: alert['name'].toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' cada ${alert['avgDays']} días (último pedido hace ${alert['daysSinceLast']} días).',
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

  Widget _buildPriceVariationsSection() {
    if (_priceVariations.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                  Icons.trending_up_rounded,
                  color: AppColors.primaryBlue,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Variación de Costos por Insumo (vs. período anterior)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._priceVariations.take(4).map((v) {
            final double pct = v['diffPct'];
            final bool isUp = pct > 0;
            final double prevP = v['prevPrice'];
            final double currP = v['currPrice'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isUp
                          ? const Color(0xFFFEF2F2)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${isUp ? '▲ +' : '▼ '}${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isUp
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF047857),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      v['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.navyDark,
                      ),
                    ),
                  ),
                  Text(
                    '\$${prevP.toStringAsFixed(2)} → \$${currP.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.subtitleGrey,
                      fontWeight: FontWeight.w500,
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
                          '\$${amount.toStringAsFixed(2)}',
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
              child: const Icon(Icons.query_stats_rounded,
                  color: AppColors.tealMint, size: 19),
            ),
            const SizedBox(width: 10),
            const Text(
              'Analítica',
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: _exportCsvReport,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text(
                'Exportar CSV',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar datos',
            icon: const Icon(Icons.refresh_rounded),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          _buildReorderAlertsSection(),
                          _buildPriceVariationsSection(),
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
                                    title: 'Gasto Total',
                                    value: '\$${_totalSpent.toStringAsFixed(2)}',
                                    icon: Icons.account_balance_wallet_outlined,
                                    iconColor: AppColors.tealMint,
                                    deltaPct: _spentDeltaPct,
                                  ),
                                  _buildKpiCard(
                                    title: 'Pedidos Hechos',
                                    value: '$_ordersCount',
                                    icon: Icons.receipt_long_outlined,
                                    iconColor: AppColors.primaryBlue,
                                    deltaPct: _ordersDeltaPct,
                                    invertDeltaColors: true,
                                  ),
                                  _buildKpiCard(
                                    title: 'Ticket Promedio',
                                    value:
                                        '\$${_averageTicket.toStringAsFixed(2)}',
                                    icon: Icons.query_stats_outlined,
                                    iconColor: AppColors.navyDark,
                                    subtitle: 'Por cada compra',
                                    deltaPct: _ticketDeltaPct,
                                  ),
                                  _buildKpiCard(
                                    title: 'Mayor Proveedor',
                                    value: _topSupplierName,
                                    icon: Icons.local_shipping_outlined,
                                    iconColor: const Color(0xFF32668E),
                                    subtitle: _topSupplierShare > 0
                                        ? '${_topSupplierShare.toStringAsFixed(0)}% del presupuesto'
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;
                              final timelineWidget = _buildTimelineChart();
                              final categoryWidget = _buildBarsSection(
                                title: 'Gasto por Categoría de Insumo',
                                items: _categorySpend,
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isDesktop = constraints.maxWidth >= 850;

                              final productsWidget = _buildBarsSection(
                                title: 'Insumos Más Pedidos (Monto)',
                                items: _topProducts,
                                barColor: AppColors.navyDark,
                                itemIcon: Icons.shopping_basket_outlined,
                              );

                              final suppliersWidget = _buildBarsSection(
                                title: 'Distribuidores Principales',
                                items: _topSuppliers,
                                barColor: AppColors.tealMint,
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