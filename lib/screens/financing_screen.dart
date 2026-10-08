import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';

class FinancingScreen extends StatefulWidget {
  const FinancingScreen({super.key});

  @override
  State<FinancingScreen> createState() => _FinancingScreenState();
}

class _FinancingScreenState extends State<FinancingScreen> {
  Map<String, dynamic>? _creditLine;
  List<Map<String, dynamic>> _installments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFinancingData();
  }

  Future<void> _loadFinancingData() async {
    try {
      setState(() => _isLoading = true);

      // 1. Obtener línea de crédito desde Supabase
      final creditData = await supabase
          .from('credit_lines')
          .select('*')
          .limit(1)
          .maybeSingle();

      // 2. Obtener cuotas con el código del pedido asociado
      final installmentsData = await supabase
          .from('installments')
          .select('*, orders(code)')
          .order('due_date', ascending: true);

      if (mounted) {
        setState(() {
          _creditLine = creditData;
          _installments = List<Map<String, dynamic>>.from(installmentsData);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creditLimit = (_creditLine?['credit_limit'] as num?)?.toDouble() ?? 1200.00;
    final currentBalance = (_creditLine?['current_balance'] as num?)?.toDouble() ?? 0.00;
    final available = creditLimit - currentBalance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Línea de Crédito Abasto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFinancingData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFinancingData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tarjeta de cupo con el gradiente oficial del logo
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: AppColors.logoGradient,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryBlue.withOpacity(0.28),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Cupo Rotativo para Restaurantes',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.tealMint.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppColors.tealMint.withOpacity(0.5)),
                                ),
                                child: const Text(
                                  'Activo',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '\$${creditLimit.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Disponible', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text(
                                    '\$${available.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('En cuotas diferidas', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                  Text(
                                    '\$${currentBalance.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '¿Cómo funciona nuestro financiamiento?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildStepTile(
                      step: '1',
                      title: 'Haces tu pedido al proveedor',
                      description: 'Seleccionas tus insumos perecederos y eliges pago diferido en cuotas.',
                    ),
                    _buildStepTile(
                      step: '2',
                      title: 'Abasto le paga al proveedor de contado',
                      description: 'El repartidor entrega sin fricción y con cobro 100% garantizado contra entrega.',
                    ),
                    _buildStepTile(
                      step: '3',
                      title: 'Pagas en cuotas a Abasto',
                      description: 'Liquidas quincenalmente dentro de los plazos establecidos según tu flujo de caja.',
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Próximos vencimientos de cuotas',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_installments.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Text(
                          'No tienes cuotas pendientes de pago en este momento.',
                          style: TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
                        ),
                      )
                    else
                      ..._installments.map((inst) {
                        final order = inst['orders'] as Map<String, dynamic>?;
                        final code = order?['code'] ?? 'Orden';
                        final numCuota = inst['installment_number'];
                        final amount = (inst['amount'] as num?)?.toDouble() ?? 0.0;
                        final dueDate = inst['due_date']?.toString() ?? '';
                        final isPaid = inst['status'] == 'pagado';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isPaid ? Colors.green.shade50 : AppColors.tealMint.withOpacity(0.15),
                              child: Icon(
                                isPaid ? Icons.check_circle_outline : Icons.calendar_today,
                                color: isPaid ? Colors.green : AppColors.primaryBlue,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              'Cuota $numCuota • $code',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Text(
                              'Vence: $dueDate',
                              style: const TextStyle(color: AppColors.subtitleGrey, fontSize: 12),
                            ),
                            trailing: Text(
                              '\$${amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                        );
                      }),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStepTile({required String step, required String title, required String description}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.tealMint.withOpacity(0.2),
            child: Text(
              step,
              style: const TextStyle(
                color: AppColors.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.navyDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(color: AppColors.subtitleGrey, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}