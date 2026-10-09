import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});

  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> {
  RealtimeChannel? _crmSubscription;
  bool _isLoading = true;
  double _totalSpent = 0.0;
  int _totalOrders = 0;
  List<MapEntry<String, double>> _topSuppliers = [];
  List<MapEntry<String, double>> _topSupplies = [];

 @override
  void initState() {
    super.initState();
    _loadCrmData();
    _setupRealtime();
  }

  void _setupRealtime() {
    // Escucha cambios tanto en orders como en order_items
    _crmSubscription = supabase
        .channel('public:restaurant_crm_channel')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            debugPrint('Cambio en orders detectado por CRM: ${payload.eventType}');
            if (mounted) {
              _loadCrmData();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (payload) {
            debugPrint('Cambio en order_items detectado por CRM: ${payload.eventType}');
            if (mounted) {
              _loadCrmData();
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _crmSubscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadCrmData() async {
    setState(() => _isLoading = true);
    try {
      final currentUid = supabase.auth.currentUser?.id;

      // 1. Consultar todos los perfiles de la BD para tener el mapa id -> business_name
      final Map<String, String> supplierNames = {};
      try {
        final profilesRes = await supabase
            .from('profiles')
            .select('*');

        for (var p in profilesRes) {
          // Evalúa las columnas habituales de nombre comercial o personal
          final dynamic rawName = p['business_name'] ??
              p['company_name'] ??
              p['store_name'] ??
              p['trade_name'] ??
              p['name'] ??
              p['full_name'];

          if (rawName != null && rawName.toString().trim().isNotEmpty) {
            supplierNames[p['id'].toString()] = rawName.toString().trim();
          }
        }
      } catch (e) {
        debugPrint("Error leyendo profiles: $e");
      }

      // 2. Traer las órdenes correspondientes al restaurante actual
      var query = supabase.from('orders').select('*');
      List<Map<String, dynamic>> orders = [];

      try {
        final res = (currentUid != null)
            ? await query.eq('restaurant_id', currentUid).order('created_at', ascending: false)
            : await query.order('created_at', ascending: false);
        orders = List<Map<String, dynamic>>.from(res);
      } catch (_) {
        final resFallback = await supabase.from('orders').select('*').order('created_at', ascending: false);
        orders = List<Map<String, dynamic>>.from(resFallback);
      }

      // Si se probaron órdenes con otro restaurant_id de prueba, tomar las órdenes asociadas al grupo principal
      if (orders.isEmpty) {
        final resAll = await supabase.from('orders').select('*').order('created_at', ascending: false);
        final allOrders = List<Map<String, dynamic>>.from(resAll);
        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (var o in allOrders) {
          final rId = o['restaurant_id']?.toString() ?? '';
          grouped.putIfAbsent(rId, () => []).add(o);
        }
        if (grouped.isNotEmpty) {
          orders = grouped.values.reduce((a, b) => a.length > b.length ? a : b);
        }
      }

      final myOrderIds = orders.map((o) => o['id'].toString()).toSet();

      // 3. Traer los ítems de estas órdenes directamente desde order_items enlazado con products
      List<Map<String, dynamic>> orderItems = [];
      try {
        final itemsRes = await supabase
            .from('order_items')
            .select('*, products(name)')
            .filter('order_id', 'in', myOrderIds.toList());
        orderItems = List<Map<String, dynamic>>.from(itemsRes);
      } catch (e) {
        debugPrint("Error obteniendo order_items: $e");
      }

      double spent = 0.0;
      final Map<String, double> supplierMap = {};
      final Map<String, double> itemAmountMap = {};

      // 4. Calcular gasto total y agrupar por distribuidor usando la BD
      for (var o in orders) {
        final double amount = (o['total_amount'] as num?)?.toDouble() ?? 
                             (o['total'] as num?)?.toDouble() ?? 0.0;
        spent += amount;

        final sId = o['supplier_id']?.toString() ?? '';

        String supName = '';
        if (supplierNames.containsKey(sId)) {
          supName = supplierNames[sId]!;
        } else if (o['supplier_name'] != null && o['supplier_name'].toString().trim().isNotEmpty) {
          supName = o['supplier_name'].toString().trim();
        } else if (o['supplier_business_name'] != null && o['supplier_business_name'].toString().trim().isNotEmpty) {
          supName = o['supplier_business_name'].toString().trim();
        } else {
          // Si por alguna razón la cuenta no tiene nombre configurado en profiles
          supName = 'Distribuidor ${sId.length > 8 ? sId.substring(0, 8) : sId}';
        }

        supplierMap[supName] = (supplierMap[supName] ?? 0.0) + amount;
      }

      // 5. Agrupar insumos vendidos con los datos de order_items y products
      for (var it in orderItems) {
        String prodName = 'Insumo';
        if (it['products'] != null && it['products']['name'] != null) {
          prodName = it['products']['name'].toString();
        } else if (it['product_name'] != null) {
          prodName = it['product_name'].toString();
        }

        final double subtotal = (it['subtotal'] as num?)?.toDouble() ??
            ((it['unit_price'] as num? ?? 0.0) * (it['quantity'] as num? ?? 1)).toDouble();

        itemAmountMap[prodName] = (itemAmountMap[prodName] ?? 0.0) + subtotal;
      }

      final sortedSuppliers = supplierMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final sortedItems = itemAmountMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (mounted) {
        setState(() {
          _totalOrders = orders.length;
          _totalSpent = spent;
          _topSuppliers = sortedSuppliers;
          _topSupplies = sortedItems;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error calculando analítica: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRM & Analítica',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCrmData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Métricas Principales
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Gasto Total',
                          value: '\$${_totalSpent.toStringAsFixed(2)}',
                          icon: Icons.account_balance_wallet_outlined,
                          color: AppColors.tealMint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Pedidos Hechos',
                          value: '$_totalOrders',
                          icon: Icons.receipt_long_outlined,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Insumos Más Pedidos
                  const Text(
                    'Insumos Más Pedidos (Monto Invertido)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_topSupplies.isEmpty)
                    const Text('No hay compras registradas aún.',
                        style: TextStyle(color: AppColors.subtitleGrey))
                  else
                    ..._topSupplies.map((entry) {
                      final maxVal = _topSupplies.first.value > 0
                          ? _topSupplies.first.value
                          : 1.0;
                      final percent = (entry.value / maxVal).clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                Text('\$${entry.value.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryBlue)),
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

                  // Distribuidores Principales
                  const Text(
                    'Distribuidores Principales',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_topSuppliers.isEmpty)
                    const Text('No hay distribuidores recurrentes aún.',
                        style: TextStyle(color: AppColors.subtitleGrey))
                  else
                    ..._topSuppliers.map((entry) {
                      final maxVal = _topSuppliers.first.value > 0
                          ? _topSuppliers.first.value
                          : 1.0;
                      final percent = (entry.value / maxVal).clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.local_shipping_outlined,
                                        size: 16, color: AppColors.tealMint),
                                    const SizedBox(width: 6),
                                    Text(entry.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                Text('\$${entry.value.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.tealMint)),
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
          Text(title,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.subtitleGrey)),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}