import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CartBottomSheet extends StatelessWidget {
  final String supplierName;
  final Map<String, dynamic> supplierData;
  final List<Map<String, dynamic>> cartItems;
  final Function(Map<String, dynamic> item, int newQty) onQuantityChanged;
  final VoidCallback onConfirmOrder;
  final double platformFeeRate;

  const CartBottomSheet({
    super.key,
    required this.supplierName,
    required this.supplierData,
    required this.cartItems,
    required this.onQuantityChanged,
    required this.onConfirmOrder,
    this.platformFeeRate = 0.02,
  });

  @override
  Widget build(BuildContext context) {
    double subtotal = 0.0;
    for (var item in cartItems) {
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      subtotal += qty * price;
    }

    final double fee = subtotal * platformFeeRate;
    final double total = subtotal + fee;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.45,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined,
                        color: AppColors.primaryBlue, size: 24),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tu Carrito de Pedido',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                        Text(
                          'Proveedor: $supplierName',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.subtitleGrey),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            // Lista de productos en el carrito
            Expanded(
              child: cartItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.remove_shopping_cart_outlined,
                              size: 48, color: Colors.grey),
                          SizedBox(height: 10),
                          Text(
                            'Tu carrito está vacío.',
                            style: TextStyle(color: AppColors.subtitleGrey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: cartItems.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = cartItems[index];
                        final name = item['name'] ?? item['product_name'] ?? 'Insumo';
                        final unit = item['unit'] ?? item['presentation'] ?? '';
                        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                        final itemTotal = qty * price;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              // Miniatura o icono
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.inventory_2_outlined,
                                    color: AppColors.primaryBlue, size: 22),
                              ),
                              const SizedBox(width: 12),
                              // Detalle
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.navyDark,
                                      ),
                                    ),
                                    Text(
                                      '\$${price.toStringAsFixed(2)} ${unit.isNotEmpty ? "• $unit" : ""}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.subtitleGrey),
                                    ),
                                  ],
                                ),
                              ),
                              // Control de cantidad
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () =>
                                        onQuantityChanged(item, qty - 1),
                                  ),
                                  Text(
                                    '$qty',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.navyDark,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline,
                                        color: AppColors.primaryBlue, size: 20),
                                    onPressed: () =>
                                        onQuantityChanged(item, qty + 1),
                                  ),
                                ],
                              ),
                              SizedBox(
                                width: 55,
                                child: Text(
                                  '\$${itemTotal.toStringAsFixed(2)}',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.navyDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const Divider(height: 20),

            // Resumen de liquidación
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal Insumos:',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.subtitleGrey)),
                      Text('\$${subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tarifa de Servicio Abasto (2%):',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.subtitleGrey)),
                      Text('\$${fee.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
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
                        '\$${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Botón de confirmación
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: cartItems.isEmpty ? null : onConfirmOrder,
                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                label: Text(
                  'Confirmar Pedido (\$${total.toStringAsFixed(2)})',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}