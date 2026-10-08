import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../theme/app_theme.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Future<List<Product>> _productsFuture;
  final Map<String, int> _selectedQuantities = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _fetchProducts();
  }

  Future<List<Product>> _fetchProducts() async {
    final response = await supabase
        .from('products')
        .select('*')
        .eq('supplier_id', widget.supplier.id)
        .eq('is_available', true);

    return (response as List<dynamic>)
        .map((p) => Product.fromMap(p as Map<String, dynamic>))
        .toList();
  }

  double _calculateTotal(List<Product> products) {
    double total = 0.0;
    for (var product in products) {
      final qty = _selectedQuantities[product.id] ?? 0;
      total += qty * product.price;
    }
    return total;
  }

  Future<void> _submitOrder(List<Product> products, double total) async {
    setState(() => _isSubmitting = true);
    try {
      final restaurant = await supabase
          .from('profiles')
          .select('id')
          .eq('role', 'restaurant')
          .limit(1)
          .single();

      final restaurantId = restaurant['id'];
      final orderCode = 'ORD-${DateTime.now().year}-${Random().nextInt(900) + 100}';

      // 1. Guardar orden
      final orderInsert = await supabase.from('orders').insert({
        'code': orderCode,
        'restaurant_id': restaurantId,
        'supplier_id': widget.supplier.id,
        'total_amount': total,
        'status': 'enRuta',
        'is_financed': false,
        'installments_count': 1,
      }).select('id').single();

      final orderId = orderInsert['id'];

      // 2. Guardar renglones de producto
      final itemsToInsert = <Map<String, dynamic>>[];
      for (var product in products) {
        final qty = _selectedQuantities[product.id] ?? 0;
        if (qty > 0) {
          itemsToInsert.add({
            'order_id': orderId,
            'product_id': product.id,
            'product_name': product.name,
            'quantity': qty,
            'unit_price': product.price,
          });
        }
      }
      await supabase.from('order_items').insert(itemsToInsert);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Pedido $orderCode despachado al proveedor con éxito!'),
            backgroundColor: AppColors.tealMint,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier.name)),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final products = snapshot.data ?? [];
          final currentTotal = _calculateTotal(products);

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey.shade100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(widget.supplier.category, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            Text(' ${widget.supplier.rating.toStringAsFixed(1)} (${widget.supplier.reviewsCount} reseñas)'),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Cobertura: ${widget.supplier.location}'),
                    Text('Días de despacho: ${widget.supplier.deliveryDays}'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: products.isEmpty
                    ? const Center(child: Text('Este proveedor aún no tiene productos registrados.'))
                    : ListView.builder(
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final qty = _selectedQuantities[product.id] ?? 0;

                          return ListTile(
                            title: Text(product.name),
                            subtitle: Text('\$${product.price.toStringAsFixed(2)} / ${product.unit}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: qty > 0
                                      ? () {
                                          setState(() {
                                            _selectedQuantities[product.id] = qty - 1;
                                          });
                                        }
                                      : null,
                                ),
                                Text('$qty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    setState(() {
                                      _selectedQuantities[product.id] = qty + 1;
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (currentTotal > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Total del pedido:', style: TextStyle(color: Colors.grey)),
                            Text(
                              '\$${currentTotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyDark),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          onPressed: _isSubmitting ? null : () => _submitOrder(products, currentTotal),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send),
                          label: Text(_isSubmitting ? 'Guardando...' : 'Confirmar Pedido'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}