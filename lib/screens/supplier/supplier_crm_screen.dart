import 'package:flutter/material.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';

class SupplierCrmScreen extends StatefulWidget {
  const SupplierCrmScreen({super.key});

  @override
  State<SupplierCrmScreen> createState() => _SupplierCrmScreenState();
}

class _SupplierCrmScreenState extends State<SupplierCrmScreen> {
  bool _isLoading = true;
  double _totalRevenue = 0.0;
  int _totalOrders = 0;
  List<MapEntry<String, double>> _topProducts = [];
  List<MapEntry<String, List<num>>> _topClientsByOrders = [];

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final currentUid = supabase.auth.currentUser?.id;

      // 1. Obtener nombres de clientes/restaurantes desde profiles
      final Map<String, String> restaurantNames = {};
      try {
        final profilesRes = await supabase.from('profiles').select('*');
        for (var p in profilesRes) {
          final dynamic rawName = p['business_name'] ??
              p['company_name'] ??
              p['store_name'] ??
              p['trade_name'] ??
              p['name'] ??
              p['full_name'];

          if (rawName != null && rawName.toString().trim().isNotEmpty) {
            restaurantNames[p['id'].toString()] = rawName.toString().trim();
          }
        }
      } catch (e) {
        debugPrint("Error mapeando perfiles: $e");
      }

      // 2. Consultar las órdenes asignadas a este distribuidor
      var query = supabase.from('orders').select('*');
      List<Map<String, dynamic>> orders = [];

      try {
        final res = (currentUid != null)
            ? await query.eq('supplier_id', currentUid).order('created_at', ascending: false)
            : await query.order('created_at', ascending: false);
        orders = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        final resAll = await supabase.from('orders').select('*').order('created_at', ascending: false);
        orders = List<Map<String, dynamic>>.from(resAll);
      }

      // Si por sesiones de prueba el UID no coincide directamente, agrupar por el supplier_id principal
      if (orders.isEmpty) {
        final resAll = await supabase.from('orders').select('*').order('created_at', ascending: false);
        final allOrders = List<Map<String, dynamic>>.from(resAll);
        final Map<String, List<Map<String, dynamic>>> bySupplier = {};
        for (var o in allOrders) {
          final sId = o['supplier_id']?.toString() ?? '';
          bySupplier.putIfAbsent(sId, () => []).add(o);
        }
        if (bySupplier.isNotEmpty) {
          orders = bySupplier.values.reduce((a, b) => a.length > b.length ? a : b);
        }
      }

      final myOrderIds = orders.map((o) => o['id'].toString()).toSet();

      // 3. Obtener los insumos reales de estas órdenes desde order_items
      List<Map<String, dynamic>> orderItems = [];
      try {
        final itemsRes = await supabase
            .from('order_items')
            .select('*, products(name)')
            .filter('order_id', 'in', myOrderIds.toList());
        orderItems = List<Map<String, dynamic>>.from(itemsRes);
      } catch (e) {
        debugPrint("Error obteniendo order_items en CRM Distribuidor: $e");
      }

      double revenue = 0.0;
      final Map<String, double> productSales = {};
      final Map<String, List<num>> clientStats = {};

      // 4. Calcular facturación y clientes
      for (var o in orders) {
        final double total = (o['total_amount'] as num?)?.toDouble() ??
            (o['total'] as num?)?.toDouble() ??
            0.0;
        revenue += total;

        final restId = o['restaurant_id']?.toString() ?? '';
        String client = '';

        if (restaurantNames.containsKey(restId)) {
          client = restaurantNames[restId]!;
        } else if (o['restaurant_name'] != null && o['restaurant_name'].toString().trim().isNotEmpty) {
          client = o['restaurant_name'].toString().trim();
        } else if (o['business_name'] != null && o['business_name'].toString().trim().isNotEmpty) {
          client = o['business_name'].toString().trim();
        } else {
          client = restId.isNotEmpty
              ? 'Restaurante ${restId.length > 8 ? restId.substring(0, 8) : restId}'
              : 'Restaurante';
        }

        if (!clientStats.containsKey(client)) {
          clientStats[client] = [0, 0.0];
        }
        clientStats[client]![0] = (clientStats[client]![0] as int) + 1;
        clientStats[client]![1] = (clientStats[client]![1] as double) + total;
      }

      // 5. Acumular las ventas exactas por insumo desde la BD
      for (var it in orderItems) {
        String prodName = 'Insumo';
        if (it['products'] != null && it['products']['name'] != null) {
          prodName = it['products']['name'].toString();
        } else if (it['product_name'] != null) {
          prodName = it['product_name'].toString();
        } else if (it['name'] != null) {
          prodName = it['name'].toString();
        }

        final double subtotal = (it['subtotal'] as num?)?.toDouble() ??
            ((it['unit_price'] as num? ?? 0.0) * (it['quantity'] as num? ?? 1)).toDouble();

        productSales[prodName] = (productSales[prodName] ?? 0.0) + subtotal;
      }

      final sortedProducts = productSales.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final sortedClients = clientStats.entries.toList()
        ..sort((a, b) => (b.value[0]).compareTo(a.value[0]));

      if (mounted) {
        setState(() {
          _totalOrders = orders.length;
          _totalRevenue = revenue;
          _topProducts = sortedProducts;
          _topClientsByOrders = sortedClients;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica de Distribuidor: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM & Rendimiento', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAnalytics),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Facturación Total',
                          value: '\$${_totalRevenue.toStringAsFixed(2)}',
                          icon: Icons.payments_outlined,
                          color: AppColors.tealMint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Despachos Realizados',
                          value: '$_totalOrders',
                          icon: Icons.local_shipping_outlined,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  const Text(
                    'Insumos Más Vendidos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_topProducts.isEmpty)
                    const Text('Aún no hay insumos registrados en órdenes.', style: TextStyle(color: AppColors.subtitleGrey))
                  else
                    ..._topProducts.map((entry) {
                      final maxVal = _topProducts.first.value > 0 ? _topProducts.first.value : 1.0;
                      final percent = (entry.value / maxVal).clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('\$${entry.value.toStringAsFixed(2)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 10,
                                backgroundColor: Colors.grey.shade200,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 24),

                  const Text(
                    'Top Restaurantes por Frecuencia de Pedidos',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_topClientsByOrders.isEmpty)
                    const Text('Aún no hay clientes registrados.', style: TextStyle(color: AppColors.subtitleGrey))
                  else
                    ..._topClientsByOrders.map((entry) {
                      final int orderCount = entry.value[0].toInt();
                      final double totalSpent = entry.value[1].toDouble();
                      final int maxOrders = _topClientsByOrders.first.value[0].toInt();
                      final percent = maxOrders > 0 ? (orderCount / maxOrders).clamp(0.0, 1.0) : 1.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.storefront, size: 18, color: AppColors.tealMint),
                                    const SizedBox(width: 8),
                                    Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  ],
                                ),
                                Text(
                                  '$orderCount pedidos (\$${totalSpent.toStringAsFixed(2)})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.tealMint),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: percent,
                                minHeight: 10,
                                backgroundColor: Colors.grey.shade200,
                                color: AppColors.tealMint,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.12),
            radius: 18,
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 12, color: AppColors.subtitleGrey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}