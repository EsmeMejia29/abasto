import 'package:flutter/material.dart';
import '../main.dart';
import '../config/session_manager.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late Future<List<Map<String, dynamic>>> _inventoryFuture;

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  @override
  void initState() {
    super.initState();
    _inventoryFuture = _fetchInventory();
  }

  Future<List<Map<String, dynamic>>> _fetchInventory() async {
    // Consulta filtrada estrictamente por el restaurante logueado
    final response = await supabase
        .from('restaurant_inventory')
        .select('*')
        .eq('restaurant_id', _currentUserId)
        .order('total_spent', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _showAddInventoryItemDialog() async {
    final nameCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: 'Verduras');
    final stockCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'libras');
    final spentCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar Insumo en Bodega'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre del insumo (ej. Tomate de ensalada)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: catCtrl,
                decoration: const InputDecoration(labelText: 'Categoría (Lácteos, Carnes, Verduras)'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Stock actual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(labelText: 'Unidad (lb, cajas, fardos)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: spentCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Gasto total (\$ USD)',
                  hintText: 'Opcional (0.00)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () async {
              final stock = double.tryParse(stockCtrl.text.trim()) ?? 0.0;
              final spent = double.tryParse(spentCtrl.text.trim()) ?? 0.0;

              if (nameCtrl.text.trim().isNotEmpty) {
                try {
                  await supabase.from('restaurant_inventory').insert({
                    'restaurant_id': _currentUserId,
                    'product_name': nameCtrl.text.trim(),
                    'category': catCtrl.text.trim().isEmpty ? 'General' : catCtrl.text.trim(),
                    'current_stock': stock,
                    'unit': unitCtrl.text.trim().isEmpty ? 'unidades' : unitCtrl.text.trim(),
                    'total_spent': spent,
                  });

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() => _inventoryFuture = _fetchInventory());
                  }
                } catch (e) {
                  if (mounted) {
                    final msg = ErrorHandler.parse(e);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Guardar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Inventario y Gastos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Agregar insumo',
            onPressed: _showAddInventoryItemDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _inventoryFuture = _fetchInventory()),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _inventoryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final items = snapshot.data ?? [];
          final totalExpenditure = items.fold<double>(
            0.0,
            (acc, curr) => acc + ((curr['total_spent'] as num?)?.toDouble() ?? 0.0),
          );

          final maxExpense = items.isEmpty
              ? 1.0
              : items
                  .map((e) => (e['total_spent'] as num?)?.toDouble() ?? 0.0)
                  .reduce((a, b) => a > b ? a : b);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen superior del gasto total
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.logoGradient,
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
                        '\$${totalExpenditure.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        items.isEmpty
                            ? 'Aún no tienes insumos registrados en bodega'
                            : '${items.length} productos registrados en bodega',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Sección de Gráficas de Gastos
                const Text(
                  '¿En qué se gastó más? (Análisis de Insumos)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 12),

                if (items.isEmpty || totalExpenditure == 0.0)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        children: [
                          Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text(
                            'Sin registros de gastos',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyDark),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'A medida que agregues insumos con sus montos de compra o confirmes pedidos, verás aquí la gráfica de distribución de tus costos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: items.take(5).map((item) {
                          final name = item['product_name'] ?? '';
                          final spent = (item['total_spent'] as num?)?.toDouble() ?? 0.0;
                          final percentage = totalExpenditure > 0 ? (spent / totalExpenditure) * 100 : 0.0;
                          final barRatio = maxExpense > 0 ? (spent / maxExpense) : 0.0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    Text(
                                      '\$${spent.toStringAsFixed(2)} (${percentage.toStringAsFixed(1)}%)',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.primaryBlue,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: barRatio.clamp(0.0, 1.0),
                                    minHeight: 10,
                                    backgroundColor: Colors.grey.shade200,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      barRatio > 0.6 ? AppColors.tealMint : AppColors.primaryBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Lista de Existencias en Bodega
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
                    TextButton.icon(
                      onPressed: _showAddInventoryItemDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Nuevo Insumo'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (items.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24.0),
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 52, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          const Text(
                            'Tu bodega está vacía',
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.subtitleGrey),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Toca en "+ Nuevo Insumo" para empezar a registrar existencias.',
                            style: TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...items.map((item) {
                    final name = item['product_name'] ?? '';
                    final category = item['category'] ?? 'General';
                    final stock = item['current_stock'] ?? 0;
                    final unit = item['unit'] ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.tealMint.withOpacity(0.15),
                          child: const Icon(Icons.kitchen, color: AppColors.primaryBlue),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Categoría: $category'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            '$stock $unit',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navyDark),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}