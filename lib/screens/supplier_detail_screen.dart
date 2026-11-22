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
  final Map<String, int>? initialQuantities;

  const SupplierDetailScreen({
    super.key,
    required this.supplier,
    this.initialQuantities,
  });

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> {
  late Future<List<Product>> _productsFuture;
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  final Map<String, int> _selectedQuantities = {};
  bool _isSubmitting = false;

  // Tarifa del 3% integrada al precio de cara al restaurante
  static const double _platformFeeRate = 0.03;

  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedCategory = 'Todos';
  List<String> _supplierCategories = ['Todos'];
  int _freeCredits = 0;
  double _minOrderAmount = 0.0;
  final Map<String, int?> _productStocks = {};
  final Map<String, List<dynamic>> _productTiers = {};
  final Map<String, String> _productDescriptions = {};
  final Map<String, String> _productSkus = {};
  String _selectedTaxDoc = 'factura'; // 'ccf' (Crédito Fiscal) o 'factura' (Consumidor Final)
  bool _hasCompleteTaxProfile = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantities != null) {
      _selectedQuantities.addAll(widget.initialQuantities!);
    }
    _productsFuture = _fetchProducts();
    _loadFreeCredits();
  }

  Future<void> _loadFreeCredits() async {
    final suppDet = await supabase
          .from('supplier_details')
          .select('min_order_amount')
          .eq('profile_id', widget.supplier.id)
          .maybeSingle();
      if (mounted && suppDet != null) {
        setState(() {
          _minOrderAmount =
              (suppDet['min_order_amount'] as num?)?.toDouble() ?? 0.0;
        });
      }
    try {
      final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final res = await supabase
          .from('profiles')
          .select('free_commission_orders, nrc, nit, nrc_nit')
          .eq('id', uid)
          .maybeSingle();
      if (mounted && res != null) {
        final nrc = (res['nrc'] ?? '').toString().trim();
        final nit = (res['nit'] ?? '').toString().trim();
        final legacy = (res['nrc_nit'] ?? '').toString().trim();
        final hasTax = (nrc.isNotEmpty && nit.isNotEmpty) || legacy.isNotEmpty;

        setState(() {
          _freeCredits = (res['free_commission_orders'] as num?)?.toInt() ?? 0;
          _hasCompleteTaxProfile = hasTax;
          _selectedTaxDoc = 'factura';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Product>> _fetchProducts() async {
    // 1. Verificar primero si el restaurante tiene pedidos sin comisión disponibles
    try {
      final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final prof = await supabase
          .from('profiles')
          .select('free_commission_orders')
          .eq('id', uid)
          .maybeSingle();
      _freeCredits = (prof?['free_commission_orders'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    final bool apply3Pct = _freeCredits <= 0;

    final response = await supabase
        .from('products')
        .select('*')
        .eq('supplier_id', widget.supplier.id)
        .eq('is_available', true)
        .order('name', ascending: true);

    final list = (response as List<dynamic>).map((p) {
      final baseMap = Map<String, dynamic>.from(p as Map<String, dynamic>);
      final double basePrice = (baseMap['price'] as num?)?.toDouble() ?? 0.0;

      // Si tiene bono de referido, muestra el precio base sin el 3%
      final double customerPrice = apply3Pct
          ? double.parse((basePrice * (1 + _platformFeeRate)).toStringAsFixed(2))
          : basePrice;
      baseMap['price'] = customerPrice;

      final prodId = baseMap['id'].toString();
      _productStocks[prodId] = (baseMap['stock_quantity'] as num?)?.toInt();
      _productDescriptions[prodId] =
          (baseMap['description'] ?? baseMap['details'] ?? '').toString().trim();
      _productSkus[prodId] = (baseMap['sku'] ?? '').toString().trim();

      final rawTiers = (baseMap['bulk_tiers'] as List<dynamic>?) ?? [];
      _productTiers[prodId] = rawTiers.map((t) {
        final baseTierPrice = (t['price'] as num?)?.toDouble() ?? basePrice;
        final customerTierPrice = apply3Pct
            ? double.parse(
                (baseTierPrice * (1 + _platformFeeRate)).toStringAsFixed(2))
            : baseTierPrice;
        return {
          'min_qty': (t['min_qty'] as num?)?.toInt() ?? 1,
          'price': customerTierPrice,
        };
      }).toList();

      return Product.fromMap(baseMap);
    }).toList();

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
      if (qty > 0) {
        total += qty * _effectiveUnitPrice(product, qty);
      }
    }
    return double.parse(total.toStringAsFixed(2));
  }

  int _totalItemsCount() {
    int count = 0;
    for (var qty in _selectedQuantities.values) {
      count += qty;
    }
    return count;
  }

  void _openBusinessInfo() {
    BusinessInfoSheet.show(
      context,
      businessId: widget.supplier.id,
      defaultName: widget.supplier.name,
      role: 'supplier',
    );
  }

  Future<void> _submitOrder(double totalAmount) async {
    setState(() => _isSubmitting = true);
    try {
      final restaurantId =
          supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final orderCode =
          'ORD-${DateTime.now().year}-${Random().nextInt(900) + 100}';

      final initialHistory = [
        {
          'status': 'pendiente',
          'changed_at': DateTime.now().toUtc().toIso8601String(),
          'note': 'Pedido emitido por el restaurante',
        }
      ];

      final bool usedFreeOrder = await supabase.rpc(
            'consume_restaurant_free_order',
            params: {'p_restaurant_id': restaurantId},
          ) ==
          true;

      final double subtotalInsumos = usedFreeOrder
          ? totalAmount
          : double.parse((totalAmount / (1 + _platformFeeRate)).toStringAsFixed(2));
      final double feeAbasto = usedFreeOrder
          ? 0.0
          : double.parse((totalAmount - subtotalInsumos).toStringAsFixed(2));
      final double finalTotal = totalAmount;

      Map<String, dynamic> orderInsert;
      try {
        orderInsert = await supabase.from('orders').insert({
          'code': orderCode,
          'restaurant_id': restaurantId,
          'supplier_id': widget.supplier.id,
          'total_amount': finalTotal,
          'subtotal': subtotalInsumos,
          'platform_fee': feeAbasto,
          'is_commission_free': usedFreeOrder,
          'tax_document_type': _selectedTaxDoc,
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
          'total_amount': totalAmount,
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
            'unit_price': _effectiveUnitPrice(product, qty),
          });
        }
      }
      await supabase.from('order_items').insert(itemsToInsert);
      try {
        await supabase.rpc('decrement_product_stock', params: {
          'p_order_id': orderId,
        });
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Pedido $orderCode emitido exitosamente!'),
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

Widget _buildCartBody({
    VoidCallback? onStateChanged,
    VoidCallback? onCloseModal,
    bool isSidebar = false,
  }) {
    final selectedProducts = _allProducts
        .where((p) => (_selectedQuantities[p.id] ?? 0) > 0)
        .toList();

    double currentTotal = 0.0;
    for (var p in selectedProducts) {
      final q = _selectedQuantities[p.id] ?? 0;
      currentTotal += q * _effectiveUnitPrice(p, q);
    }

    return Column(
      mainAxisSize: isSidebar ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.navyDark.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shopping_cart_outlined,
                      color: AppColors.navyDark, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Carrito de Pedido',
                      style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark),
                    ),
                    Text(
                      widget.supplier.name,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.subtitleGrey),
                    ),
                  ],
                ),
              ],
            ),
            if (onCloseModal != null)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onCloseModal,
              )
            else if (selectedProducts.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() => _selectedQuantities.clear());
                  onStateChanged?.call();
                },
                child: const Text(
                  'Vaciar',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
        const Divider(height: 18),

        if (selectedProducts.isEmpty)
          Expanded(
            flex: isSidebar ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_shopping_cart_rounded,
                        size: 44, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 10),
                    Text(
                      'Tu carrito está vacío',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.navyDark,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Selecciona insumos del catálogo para armar tu pedido.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.subtitleGrey),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          isSidebar
              ? Expanded(
                  child: ListView.separated(
                    itemCount: selectedProducts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) => _buildCartItemRow(
                        selectedProducts[index], onStateChanged),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: selectedProducts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, index) => _buildCartItemRow(
                        selectedProducts[index], onStateChanged),
                  ),
                ),

        const Divider(height: 18),

        const Text(
          'Documento Tributario (DTE El Salvador):',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _selectedTaxDoc = 'factura');
                  onStateChanged?.call();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedTaxDoc == 'factura'
                        ? AppColors.navyDark
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedTaxDoc == 'factura'
                          ? AppColors.navyDark
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Factura Electrónica',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _selectedTaxDoc == 'factura'
                              ? Colors.white
                              : AppColors.navyDark,
                        ),
                      ),
                      Text(
                        'DTE-01 • Consumidor Final',
                        style: TextStyle(
                          fontSize: 10,
                          color: _selectedTaxDoc == 'factura'
                              ? AppColors.tealMint
                              : AppColors.subtitleGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _selectedTaxDoc = 'ccf');
                  onStateChanged?.call();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedTaxDoc == 'ccf'
                        ? AppColors.navyDark
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedTaxDoc == 'ccf'
                          ? AppColors.navyDark
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crédito Fiscal (CCF)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: _selectedTaxDoc == 'ccf'
                              ? Colors.white
                              : AppColors.navyDark,
                        ),
                      ),
                      Text(
                        'DTE-03 • Deduce 13% IVA',
                        style: TextStyle(
                          fontSize: 10,
                          color: _selectedTaxDoc == 'ccf'
                              ? AppColors.tealMint
                              : AppColors.subtitleGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_selectedTaxDoc == 'ccf' && !_hasCompleteTaxProfile) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                Icon(Icons.warning_amber_rounded,
                    size: 15, color: Color(0xFFB45309)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Completa tu NRC, NIT y Giro en "Mi Perfil" para recibir CCF.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),

        if (_freeCredits > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.tealMint.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.tealMint.withOpacity(0.5)),
            ),
            child: Row(
              children: const [
                Icon(Icons.card_giftcard_rounded,
                    size: 16, color: Color(0xFF0F766E)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '¡Bono Referido activo! 0% tarifa Abasto en este pedido.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
              ],
            ),
          ),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total a Pagar:',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark),
              ),
              Text(
                '\$${currentTotal.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (_minOrderAmount > 0 && currentTotal < _minOrderAmount) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: Color(0xFFB45309)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Pedido mínimo: \$${_minOrderAmount.toStringAsFixed(2)} (faltan \$${(_minOrderAmount - currentTotal).toStringAsFixed(2)}).',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (selectedProducts.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                onCloseModal?.call();
                _saveCurrentCartAsTemplate();
              },
              icon: const Icon(Icons.bookmark_add_outlined, size: 15),
              label: const Text(
                'Guardar como lista semanal',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ),
        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyDark,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: selectedProducts.isEmpty ||
                    _isSubmitting ||
                    (_minOrderAmount > 0 && currentTotal < _minOrderAmount)
                ? null
                : () {
                    onCloseModal?.call();
                    _submitOrder(currentTotal);
                  },
            icon: const Icon(Icons.check_circle_outline,
                size: 19, color: AppColors.tealMint),
            label: Text(
              'Confirmar Pedido (\$${currentTotal.toStringAsFixed(2)})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCartItemRow(Product product, VoidCallback? onStateChanged) {
    final qty = _selectedQuantities[product.id] ?? 0;
    final unitPrice = _effectiveUnitPrice(product, qty);
    final itemTotal = qty * unitPrice;
    final int? maxStock = _productStocks[product.id];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          _buildCartThumbnail(product.imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.navyDark,
                  ),
                ),
                Text(
                  '\$${unitPrice.toStringAsFixed(2)} • ${product.unit}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.subtitleGrey,
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 18,
                icon: const Icon(Icons.remove_circle_outline,
                    color: Color(0xFFDC2626)),
                onPressed: () {
                  setState(() {
                    _selectedQuantities[product.id] = qty - 1;
                  });
                  onStateChanged?.call();
                },
              ),
              Text(
                '$qty',
                style:
                    const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 18,
                icon: Icon(
                  Icons.add_circle_outline,
                  color: (maxStock != null && qty >= maxStock)
                      ? Colors.grey
                      : AppColors.primaryBlue,
                ),
                onPressed: (maxStock != null && qty >= maxStock)
                    ? null
                    : () {
                        setState(() {
                          _selectedQuantities[product.id] = qty + 1;
                        });
                        onStateChanged?.call();
                      },
              ),
            ],
          ),
          SizedBox(
            width: 54,
            child: Text(
              '\$${itemTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.navyDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openCartModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: _buildCartBody(
              onStateChanged: () => setModalState(() {}),
              onCloseModal: () => Navigator.pop(ctx),
              isSidebar: false,
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveCurrentCartAsTemplate() async {
    final nameCtrl = TextEditingController();
    final templateName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar Lista Recurrente',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nombre de la lista',
            hintText: 'Ej. Pedido Lunes Lácteos / Semanal',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (templateName == null || templateName.isEmpty) return;

    try {
      final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      final items = _selectedQuantities.entries
          .where((e) => e.value > 0)
          .map((e) => {'product_id': e.key, 'quantity': e.value})
          .toList();

      await supabase.from('restaurant_order_templates').insert({
        'restaurant_id': uid,
        'supplier_id': widget.supplier.id,
        'name': templateName,
        'items': items,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plantilla "$templateName" guardada'),
            backgroundColor: AppColors.tealMint,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error guardando plantilla: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openTemplatesSheet() async {
    final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
    final res = await supabase
        .from('restaurant_order_templates')
        .select('*')
        .eq('restaurant_id', uid)
        .eq('supplier_id', widget.supplier.id)
        .order('created_at', ascending: false);

    final templates = (res as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Listas Recurrentes para este Proveedor',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark),
            ),
            const SizedBox(height: 12),
            if (templates.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Aún no tienes listas guardadas aquí. Arma un carrito y tócalo para guardar tu plantilla semanal.',
                  style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
                ),
              )
            else
              ...templates.map((tpl) {
                final items = (tpl['items'] as List<dynamic>?) ?? [];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.playlist_add_check_rounded,
                      color: AppColors.primaryBlue),
                  title: Text(tpl['name'] ?? 'Lista',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${items.length} productos configurados'),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navyDark,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedQuantities.clear();
                        for (var it in items) {
                          final pid = it['product_id'].toString();
                          final q = (it['quantity'] as num).toInt();
                          final maxStock = _productStocks[pid];
                          if (_allProducts.any((p) => p.id == pid)) {
                            _selectedQuantities[pid] =
                                maxStock != null ? q.clamp(0, maxStock) : q;
                          }
                        }
                      });
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Lista "${tpl['name']}" cargada al carrito'),
                          backgroundColor: AppColors.tealMint,
                        ),
                      );
                    },
                    child: const Text('Cargar'),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  double _effectiveUnitPrice(Product product, int qty) {
    double price = product.price;
    final tiers = _productTiers[product.id] ?? [];
    for (var t in tiers) {
      if (qty >= (t['min_qty'] as int)) {
        price = (t['price'] as double);
      }
    }
    return price;
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
                    backgroundImage:
                        (s.avatarUrl != null && s.avatarUrl!.isNotEmpty)
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
                              const Icon(Icons.verified_rounded,
                                  color: AppColors.tealMint, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.category,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Color(0xFFF59E0B), size: 16),
                            const SizedBox(width: 4),
                            Text(
                              s.reviewsCount > 0
                                  ? '${s.rating.toStringAsFixed(1)} (${s.reviewsCount} reseñas verificadas)'
                                  : '5.0 • Proveedor Verificado',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.navyDark,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppColors.subtitleGrey),
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
                      'Sede: ${s.location.isNotEmpty ? '${s.location[0].toUpperCase()}${s.location.substring(1)}' : s.location}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF334155)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (s.deliveryCoverage.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.local_shipping_outlined,
                        size: 15, color: Color(0xFF0F766E)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reparte en: ${s.deliveryCoverage}',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F766E)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(Icons.schedule_outlined,
                      size: 15, color: AppColors.subtitleGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${s.businessHours}${_minOrderAmount > 0 ? ' • Pedido mín: \$${_minOrderAmount.toStringAsFixed(2)}' : ''}',
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

  Widget _buildCartThumbnail(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          imageUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildCartFallback(),
        ),
      );
    }
    return _buildCartFallback();
  }

  Widget _buildCartFallback() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryBlue, size: 24),
    );
  }

  void _showFullScreenProductImage(String imageUrl, String title) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 56,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 12,
              right: 54,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black.withOpacity(0.65),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openProductDetailModal(Product product) {
    final bool isDesktop = MediaQuery.of(context).size.width >= 850;
    final int? maxStock = _productStocks[product.id];
    final tiers = _productTiers[product.id] ?? [];
    final description = _productDescriptions[product.id] ?? '';
    final sku = _productSkus[product.id] ?? '';

    Widget buildDetailContent(StateSetter setModalState, VoidCallback close) {
      final int qty = _selectedQuantities[product.id] ?? 0;
      final double unitPrice =
          _effectiveUnitPrice(product, qty > 0 ? qty : 1);
      final bool hasTierDiscount = unitPrice < product.price;
      final double subtotalItem = qty * unitPrice;

      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Imagen superior clicable para ver en tamaño completo + botón de cerrar y badge de categoría
            Stack(
              children: [
                GestureDetector(
                  onTap: (product.imageUrl != null &&
                          product.imageUrl!.isNotEmpty)
                      ? () => _showFullScreenProductImage(
                            product.imageUrl!,
                            product.name,
                          )
                      : null,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                    child: SizedBox(
                      height: isDesktop ? 240 : 210,
                      width: double.infinity,
                      child: (product.imageUrl != null &&
                              product.imageUrl!.isNotEmpty)
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Icon(Icons.inventory_2_outlined,
                                    size: 56, color: AppColors.primaryBlue),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.inventory_2_outlined,
                                  size: 56, color: AppColors.primaryBlue),
                            ),
                    ),
                  ),
                ),
                if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.zoom_in_rounded,
                                color: Colors.white, size: 15),
                            SizedBox(width: 4),
                            Text(
                              'Ver completa',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.navyDark.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      product.category,
                      style: const TextStyle(
                        color: AppColors.tealMint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.white.withOpacity(0.92),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.close,
                          size: 20, color: AppColors.navyDark),
                      onPressed: close,
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título y presentación
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ),
                      if (sku.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'SKU: $sku',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.subtitleGrey,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Badges de Presentación y Disponibilidad
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.straighten_rounded,
                                size: 14, color: AppColors.primaryBlue),
                            const SizedBox(width: 5),
                            Text(
                              'Presentación: ${product.unit}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 14, color: Color(0xFF0F766E)),
                            const SizedBox(width: 5),
                            Text(
                              maxStock != null
                                  ? 'Stock disponible: $maxStock'
                                  : 'Disponible para despacho',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F766E),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Precio unitario y precio tachado si aplica descuento
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '\$${unitPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ ${product.unit}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.subtitleGrey,
                        ),
                      ),
                      if (hasTierDiscount || _freeCredits > 0) ...[
                        const SizedBox(width: 10),
                        Text(
                          '\$${(hasTierDiscount ? product.price : (product.price * (1 + _platformFeeRate))).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.lineThrough,
                            color: AppColors.subtitleGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Descripción / Especificaciones del insumo
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Especificaciones del Insumo',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          description.isNotEmpty
                              ? description
                              : 'Insumo comercial abastecido por ${widget.supplier.name} en presentación de ${product.unit}. Precio incluye IVA (13%) para respaldo tributario.',
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Escalas de precios por volumen (Mayoreo) si existen
                  if (tiers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.local_offer_outlined,
                                  size: 15, color: Color(0xFF0F766E)),
                              SizedBox(width: 6),
                              Text(
                                'Precios por Volumen (Mayoreo)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F766E),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...tiers.map((t) {
                            final minQ = t['min_qty'] as int;
                            final tPrice = t['price'] as double;
                            final applied = qty >= minQ;
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '${applied ? '✓ ' : '• '}Desde $minQ unidades: \$${tPrice.toStringAsFixed(2)} c/u',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: applied
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: const Color(0xFF166534),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Selector de cantidad + Botón de confirmar en carrito
                  Row(
                    children: [
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove,
                                  color: Color(0xFFDC2626), size: 18),
                              onPressed: qty > 0
                                  ? () {
                                      setState(() {
                                        _selectedQuantities[product.id] =
                                            qty - 1;
                                      });
                                      setModalState(() {});
                                    }
                                  : null,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                '$qty',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyDark,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.add,
                                size: 18,
                                color: (maxStock != null && qty >= maxStock)
                                    ? Colors.grey
                                    : AppColors.primaryBlue,
                              ),
                              onPressed: (maxStock != null && qty >= maxStock)
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedQuantities[product.id] =
                                            qty + 1;
                                      });
                                      setModalState(() {});
                                    },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navyDark,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              if (qty == 0) {
                                setState(() {
                                  _selectedQuantities[product.id] = 1;
                                });
                              }
                              close();
                            },
                            icon: const Icon(Icons.shopping_cart_checkout,
                                size: 18, color: AppColors.tealMint),
                            label: Text(
                              qty == 0
                                  ? 'Agregar (\$${unitPrice.toStringAsFixed(2)})'
                                  : 'Listo (\$${subtotalItem.toStringAsFixed(2)})',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
              child: buildDetailContent(
                setModalState,
                () => Navigator.pop(ctx),
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (context, setModalState) => ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: buildDetailContent(
              setModalState,
              () => Navigator.pop(ctx),
            ),
          ),
        ),
      );
    }
  }

  // Tarjeta de Insumo con altura fija protegida para evitar overflow
  Widget _buildGridProductCard(Product product) {
    final qty = _selectedQuantities[product.id] ?? 0;
    final bool hasSelection = qty > 0;
    final int? maxStock = _productStocks[product.id];
    final tiers = _productTiers[product.id] ?? [];
    final double unitPrice = _effectiveUnitPrice(product, qty > 0 ? qty : 1);
    final bool hasTierDiscount = unitPrice < product.price;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasSelection ? AppColors.primaryBlue : const Color(0xFFE2E8F0),
          width: hasSelection ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Imagen Superior clicable para ver detalles
          Expanded(
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
              onTap: () => _openProductDetailModal(product),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(13)),
                    child: (product.imageUrl != null &&
                            product.imageUrl!.isNotEmpty)
                        ? Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Icon(Icons.inventory_2_outlined,
                                  color: AppColors.primaryBlue, size: 36),
                            ),
                          )
                        : Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Icon(Icons.inventory_2_outlined,
                                color: AppColors.primaryBlue, size: 36),
                          ),
                  ),
                  if (hasSelection)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$qty en carrito',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 2. Información (clicable) y Controles de cantidad
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _openProductDetailModal(product),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.navyDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${product.category} • ${product.unit}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.subtitleGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '\$${unitPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          if (hasTierDiscount || _freeCredits > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              '\$${(hasTierDiscount ? product.price : (product.price * (1 + _platformFeeRate))).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.subtitleGrey,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (tiers.isNotEmpty)
                        Text(
                          hasTierDiscount
                              ? '¡Precio mayoreo aplicado!'
                              : '${tiers.first['min_qty']}+ unid. a \$${(tiers.first['price'] as double).toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: hasTierDiscount
                                ? const Color(0xFF0F766E)
                                : AppColors.primaryBlue,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Selector de cantidad
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        iconSize: 16,
                        icon: const Icon(Icons.remove, color: Colors.red),
                        onPressed: qty > 0
                            ? () {
                                setState(() {
                                  _selectedQuantities[product.id] = qty - 1;
                                });
                              }
                            : null,
                      ),
                      Text(
                        '$qty',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        iconSize: 16,
                        icon: Icon(
                          Icons.add,
                          color: (maxStock != null && qty >= maxStock)
                              ? Colors.grey
                              : AppColors.primaryBlue,
                        ),
                        onPressed: (maxStock != null && qty >= maxStock)
                            ? null
                            : () {
                                setState(() {
                                  _selectedQuantities[product.id] = qty + 1;
                                });
                              },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTotal = _calculateTotal();
    final totalItems = _totalItemsCount();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.supplier.name),
        actions: [
          IconButton(
            tooltip: 'Mis Listas / Plantillas Semanales',
            icon: const Icon(Icons.bookmark_border_rounded),
            onPressed: _openTemplatesSheet,
          ),
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

return LayoutBuilder(
            builder: (context, screenConstraints) {
              final bool isDesktop = screenConstraints.maxWidth >= 900;

              final catalogColumn = Column(
                children: [
                  _buildSupplierHeader(),

                  // Buscador de productos
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => _applyFilters(),
                      decoration: InputDecoration(
                        hintText:
                            'Buscar insumo en ${widget.supplier.name}...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300),
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
                            selectedColor: AppColors.navyDark,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.navyDark,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
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

                  // Grid de productos
                  Expanded(
                    child: _filteredProducts.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron insumos con esos filtros.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, gridConstraints) {
                              int crossAxisCount = 2;
                              double aspectRatio = 0.70;

                              if (gridConstraints.maxWidth > 950) {
                                crossAxisCount = 4;
                                aspectRatio = 0.72;
                              } else if (gridConstraints.maxWidth > 620) {
                                crossAxisCount = 3;
                                aspectRatio = 0.70;
                              }

                              return GridView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: aspectRatio,
                                ),
                                itemCount: _filteredProducts.length,
                                itemBuilder: (context, index) {
                                  return _buildGridProductCard(
                                      _filteredProducts[index]);
                                },
                              );
                            },
                          ),
                  ),

                  // Barra inferior solo en móvil/tablet
                  if (!isDesktop && currentTotal > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
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
                            InkWell(
                              onTap: _openCartModal,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                            Icons.shopping_cart_outlined,
                                            size: 15,
                                            color: AppColors.primaryBlue),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$totalItems insumo(s) • Ver Carrito',
                                          style: const TextStyle(
                                            color: AppColors.primaryBlue,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Total: \$${currentTotal.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.navyDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.navyDark,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _isSubmitting ? null : _openCartModal,
                              icon: const Icon(Icons.shopping_bag_outlined,
                                  size: 18, color: AppColors.tealMint),
                              label: const Text(
                                'Ver Carrito',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );

              if (!isDesktop) {
                return catalogColumn;
              }

              // Vista Escritorio: Catálogo a la izquierda + Carrito fijo a la derecha
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: catalogColumn),
                  Container(
                    width: 390,
                    padding: const EdgeInsets.all(18),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        left: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: _buildCartBody(isSidebar: true),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}