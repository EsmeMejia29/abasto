import 'dart:math';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../utils/error_handler.dart';
import '../widgets/business_info_sheet.dart';

class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Future<List<Product>> _productsFuture;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  final Map<String, int> _selectedQuantities = {};
  bool _isSubmitting = false;

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'Todos';
  List<String> _supplierCategories = ['Todos'];

  @override
  void initState() {
    super.initState();
    _productsFuture = _fetchProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Product>> _fetchProducts() async {
    final response = await supabase
        .from('products')
        .select('*')
        .eq('supplier_id', widget.supplier.id)
        .eq('is_available', true)
        .order('name', ascending: true);

    final list = (response as List<dynamic>)
        .map((p) => Product.fromMap(p as Map<String, dynamic>))
        .toList();

    _allProducts = list;
    _filteredProducts = list;

    final cats = {'Todos', ...list.map((p) => p.category).where((c) => c.isNotEmpty)};
    _supplierCategories = cats.toList();

    return list;
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        final matchesQuery = p.name.toLowerCase().contains(query) ||
            p.category.toLowerCase().contains(query);
        final matchesCat = _selectedCategory == 'Todos' ||
            p.category.toLowerCase() == _selectedCategory.toLowerCase();
        return matchesQuery && matchesCat;
      }).toList();
    });
  }

  double _calculateTotal() {
    double total = 0.0;
    for (var product in _allProducts) {
      final qty = _selectedQuantities[product.id] ?? 0;
      total += qty * product.price;
    }
    return total;
  }

  void _openBusinessInfo() {
    BusinessInfoSheet.show(
      context,
      businessId: widget.supplier.id,
      defaultName: widget.supplier.name,
      role: 'supplier',
    );
  }

  Future<void> _submitOrder(double total) async {
    setState(() => _isSubmitting = true);
    try {
      final restaurantId =
          supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final orderCode =
          'ORD-${DateTime.now().year}-${Random().nextInt(900) + 100}';

      final initialHistory = [
        {
          'status': 'pendiente',
          'changed_at': DateTime.now().toIso8601String(),
          'note': 'Pedido emitido por el restaurante',
        }
      ];

      Map<String, dynamic> orderInsert;
      try {
        orderInsert = await supabase.from('orders').insert({
          'code': orderCode,
          'restaurant_id': restaurantId,
          'supplier_id': widget.supplier.id,
          'total_amount': total,
          'status': 'pendiente',
          'status_history': initialHistory,
          'is_financed': false,
          'installments_count': 1,
        }).select('id').single();
      } catch (_) {
        orderInsert = await supabase.from('orders').insert({
          'code': orderCode,
          'restaurant_id': restaurantId,
          'supplier_id': widget.supplier.id,
          'total_amount': total,
          'status': 'pendiente',
          'is_financed': false,
          'installments_count': 1,
        }).select('id').single();
      }

      final orderId = orderInsert['id'];

      final itemsToInsert = <Map<String, dynamic>>[];
      for (var product in _allProducts) {
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
            content: Text('¡Pedido $orderCode emitido como Pendiente!'),
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

  Widget _buildSupplierHeader() {
    final s = widget.supplier;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: _openBusinessInfo,
        splashColor: AppColors.primaryBlue.withOpacity(0.08),
        highlightColor: AppColors.primaryBlue.withOpacity(0.04),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppColors.primaryBlue.withOpacity(0.12),
                    backgroundImage: (s.avatarUrl != null && s.avatarUrl!.isNotEmpty)
                        ? NetworkImage(s.avatarUrl!)
                        : null,
                    child: (s.avatarUrl == null || s.avatarUrl!.isEmpty)
                        ? Text(
                            s.name.isNotEmpty ? s.name[0].toUpperCase() : 'D',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                s.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            if (s.isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.check_circle,
                                  color: AppColors.tealMint, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          s.category,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.subtitleGrey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${s.rating.toStringAsFixed(1)} (${s.reviewsCount} reseñas verificadas)',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right, size: 16, color: AppColors.subtitleGrey),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 15, color: AppColors.primaryBlue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.location,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.schedule_outlined,
                      size: 15, color: AppColors.subtitleGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.businessHours,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.subtitleGrey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
    final currentTotal = _calculateTotal();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            tooltip: 'Ver información y reseñas',
            icon: const Icon(Icons.info_outline),
            onPressed: _openBusinessInfo,
          ),
        ],
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

          return Column(
            children: [
              _buildSupplierHeader(),

              // Buscador de productos
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _applyFilters(),
                  decoration: InputDecoration(
                    hintText: 'Buscar insumo en ${widget.supplier.name}...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              // Chips de categorías
              if (_supplierCategories.length > 2)
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _supplierCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, idx) {
                      final cat = _supplierCategories[idx];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: AppColors.primaryBlue,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.navyDark,
                          fontSize: 12,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setState(() => _selectedCategory = cat);
                            _applyFilters();
                          }
                        },
                      );
                    },
                  ),
                ),

              const SizedBox(height: 6),

              Expanded(
                child: _filteredProducts.isEmpty
                    ? Center(
                        child: Text(
                          'No se encontraron insumos con esos filtros.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        itemCount: _filteredProducts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
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
                                _buildProductThumbnail(product.imageUrl),
                                const SizedBox(width: 12),
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
                              : () => _submitOrder(currentTotal),
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