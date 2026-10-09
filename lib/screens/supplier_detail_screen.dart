import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../utils/error_handler.dart';

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
        .eq('is_available', true)
        .order('name', ascending: true);

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
      final restaurantId =
          supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final orderCode =
          'ORD-${DateTime.now().year}-${Random().nextInt(900) + 100}';

      // 1. Guardar orden general
      final orderInsert = await supabase.from('orders').insert({
        'code': orderCode,
        'restaurant_id': restaurantId,
        'supplier_id': widget.supplier.id,
        'total_amount': total,
        'status': 'pendiente',
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
            content: Text('¡Pedido $orderCode despachado con éxito!'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _buildProductThumbnail(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          imageUrl,
          width: 58,
          height: 58,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackThumbnail(),
        ),
      );
    }
    return _buildFallbackThumbnail();
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.inventory_2_outlined,
        color: AppColors.primaryBlue,
        size: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
      ),
      body: FutureBuilder<List<Product>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  'Error al cargar catálogo: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          final products = snapshot.data ?? [];
          final currentTotal = _calculateTotal(products);

          return Column(
            children: [
              // Encabezado del Proveedor
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.supplier.category,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: AppColors.navyDark,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 18),
                            Text(
                              ' ${widget.supplier.rating.toStringAsFixed(1)} (${widget.supplier.reviewsCount} reseñas)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.subtitleGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Cobertura: ${widget.supplier.location}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.subtitleGrey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 16, color: AppColors.subtitleGrey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Despacho: ${widget.supplier.deliveryDays}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.subtitleGrey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Lista de Insumos con Foto
              Expanded(
                child: products.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            const Text(
                              'Este proveedor aún no tiene insumos disponibles.',
                              style: TextStyle(color: AppColors.subtitleGrey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          final qty = _selectedQuantities[product.id] ?? 0;

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                // Fotografía del Insumo
                                _buildProductThumbnail(product.imageUrl),
                                const SizedBox(width: 12),

                                // Detalles (Nombre, Precio, Categoría)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.navyDark,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${product.category} • ${product.unit}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.subtitleGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '\$${product.price.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: AppColors.primaryBlue,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Selector de Cantidad
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        iconSize: 18,
                                        splashRadius: 20,
                                        icon: const Icon(
                                            Icons.remove_circle_outline),
                                        onPressed: qty > 0
                                            ? () {
                                                setState(() {
                                                  _selectedQuantities[
                                                      product.id] = qty - 1;
                                                });
                                              }
                                            : null,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: Text(
                                          '$qty',
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        iconSize: 18,
                                        splashRadius: 20,
                                        icon: const Icon(
                                            Icons.add_circle_outline),
                                        onPressed: () {
                                          setState(() {
                                            _selectedQuantities[product.id] =
                                                qty + 1;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),

              // Barra Inferior de Confirmación de Pedido
              if (currentTotal > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
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
                            const Text(
                              'Total del pedido:',
                              style: TextStyle(
                                  color: AppColors.subtitleGrey, fontSize: 12),
                            ),
                            Text(
                              '\$${currentTotal.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 22, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _isSubmitting
                              ? null
                              : () => _submitOrder(products, currentTotal),
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.shopping_bag_outlined,
                                  size: 18),
                          label: Text(
                            _isSubmitting
                                ? 'Procesando...'
                                : 'Confirmar Pedido',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
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