import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<Map<String, dynamic>> _inventoryFuture;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _inventoryFuture = _fetchInventoryData();
  }

  void _refresh() {
    setState(() {
      _inventoryFuture = _fetchInventoryData();
    });
  }

  Future<Map<String, dynamic>> _fetchInventoryData() async {
    final userId = _currentUserId;

    // 1. Obtener órdenes entregadas para asegurar cálculo acumulado en tiempo real
    final deliveredOrders = await supabase
        .from('orders')
        .select('''
          id, code, total_amount, updated_at,
          order_items (product_name, quantity, unit_price)
        ''')
        .eq('restaurant_id', userId)
        .eq('status', 'entregado');

    double totalSpent = 0.0;
    final Map<String, Map<String, dynamic>> inventoryItems = {};

    for (var ord in (deliveredOrders as List<dynamic>)) {
      final items = (ord['order_items'] as List<dynamic>?) ?? [];
      for (var it in items) {
        final name = it['product_name']?.toString() ?? 'Insumo';
        final qty = (it['quantity'] as num?)?.toDouble() ?? 1.0;
        final unitPrice = (it['unit_price'] as num?)?.toDouble() ?? 0.0;
        final cost = qty * unitPrice;

        totalSpent += cost;

        if (inventoryItems.containsKey(name)) {
          inventoryItems[name]!['quantity'] += qty;
          inventoryItems[name]!['total_spent'] += cost;
        } else {
          inventoryItems[name] = {
            'name': name,
            'quantity': qty,
            'unit_price': unitPrice,
            'total_spent': cost,
            'last_order': ord['code'] ?? '',
          };
        }
      }
    }

    return {
      'totalSpent': totalSpent,
      'items': inventoryItems.values.toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Inventario y Gastos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _inventoryFuture,
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

          final data = snapshot.data ?? {};
          final double totalSpent = data['totalSpent'] ?? 0.0;
          final List<dynamic> items = data['items'] ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tarjeta de Gasto Total Acumulado
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.navyDark, AppColors.tealMint],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gasto Total Acumulado en Insumos',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '\$${totalSpent.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items.isNotEmpty
                            ? '${items.length} insumos entregados en bodega'
                            : 'Aún no tienes insumos entregados en bodega',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Desglose de Gastos
                const Text(
                  '¿En qué se gastó más? (Análisis de Insumos)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 10),

                if (items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: const [
                        Icon(Icons.bar_chart, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'Sin registros de gastos',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'A medida que los pedidos cambien a "Entregado", verás el análisis de costos aquí.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppColors.subtitleGrey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  ...items.map((it) {
                    final double itemCost = it['total_spent'] ?? 0.0;
                    final pct = totalSpent > 0 ? (itemCost / totalSpent) : 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(it['name'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text('\$${itemCost.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryBlue)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.tealMint),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Representa el ${(pct * 100).toStringAsFixed(1)}% del gasto en insumos',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.subtitleGrey),
                          ),
                        ],
                      ),
                    );
                  }),

                const SizedBox(height: 24),

                // Existencias en Bodega
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Existencias en Bodega',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                    ),
                    Text(
                      '${items.length} productos',
                      style: const TextStyle(
                          color: AppColors.subtitleGrey, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (items.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: const [
                          Icon(Icons.inventory_2_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            'Tu bodega está vacía',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Los pedidos entregados ingresarán existencias automáticamente.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.subtitleGrey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.tealMint.withOpacity(0.15),
                            child: const Icon(Icons.check_circle_outline,
                                color: AppColors.tealMint),
                          ),
                          title: Text(item['name'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'Último ingreso: Pedido ${item['last_order']}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item['quantity']} unid.',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              Text(
                                '\$${(item['total_spent'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.subtitleGrey),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}