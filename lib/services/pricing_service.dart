import '../main.dart'; // Para acceder al cliente de Supabase

class PricingService {
  static const double restaurantServiceFeeRate = 0.02; // 2% al restaurante
  static const double supplierCommissionRate = 0.05;   // 5% retenido al distribuidor

  // Cálculo de totales
  static Map<String, double> calculateBreakdown(double subtotal) {
    final fee = subtotal * restaurantServiceFeeRate;
    final totalToPay = subtotal + fee;
    final supplierCommission = subtotal * supplierCommissionRate;
    final supplierPayout = subtotal - supplierCommission;

    return {
      'subtotal': subtotal,
      'platformFee': fee,
      'totalToPay': totalToPay,
      'supplierCommission': supplierCommission,
      'supplierPayout': supplierPayout,
    };
  }

  // Registra el abono al balance del distribuidor en Supabase
  static Future<void> creditSupplierBalance({
    required String supplierId,
    required String orderId,
    required String orderCode,
    required double subtotalInsumos,
  }) async {
    final double commission = subtotalInsumos * supplierCommissionRate;
    final double netPayout = subtotalInsumos - commission;

    await supabase.from('supplier_payouts').insert({
      'supplier_id': supplierId,
      'order_id': orderId,
      'order_code': orderCode,
      'gross_amount': subtotalInsumos,
      'commission_fee': commission,
      'net_payout': netPayout,
      'status': 'disponible',
    });
  }
}