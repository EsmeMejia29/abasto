import 'package:flutter/material.dart';
import '../../main.dart';
import '../../config/session_manager.dart';
import '../../theme/app_theme.dart';

class SupplierInventoryScreen extends StatefulWidget {
  const SupplierInventoryScreen({super.key});

  @override
  State<SupplierInventoryScreen> createState() => _SupplierInventoryScreenState();
}

class _SupplierInventoryScreenState extends State<SupplierInventoryScreen> {
  late Future<List<Map<String, dynamic>>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _productsFuture = _fetchCatalog();
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog() async {
    final response = await supabase
        .from('products')
        .select('*')
        .eq('supplier_id', SessionManager.supplierId)
        .order('name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _showAddProductDialog() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'Caja');
    final priceCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Insumo al Catálogo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre del producto')),
            TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Presentación (ej. Caja 50 lb, Libra)')),
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio (\$ USD)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final price = double.tryParse(priceCtrl.text) ?? 0.0;
              if (nameCtrl.text.isNotEmpty && price > 0) {
                await supabase.from('products').insert({
                  'supplier_id': SessionManager.supplierId,
                  'name': nameCtrl.text.trim(),
                  'unit': unitCtrl.text.trim(),
                  'price': price,
                  'is_available': true,
                });
                if (mounted) {
                  Navigator.pop(context);
                  setState(() => _productsFuture = _fetchCatalog());
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Catálogo de Insumos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddProductDialog,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return const Center(child: Text('No tienes insumos en tu catálogo. Presiona + para agregar.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final isAvailable = product['is_available'] ?? true;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  title: Text(product['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${product['unit']} • \$${(product['price'] as num?)?.toStringAsFixed(2) ?? "0.00"}'),
                  trailing: Switch(
                    value: isAvailable,
                    activeColor: AppColors.tealMint,
                    onChanged: (val) async {
                      await supabase.from('products').update({'is_available': val}).eq('id', product['id']);
                      setState(() => _productsFuture = _fetchCatalog());
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}