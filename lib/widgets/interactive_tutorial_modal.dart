import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class _TutorialStep {
  final IconData icon;
  final Color badgeColor;
  final String title;
  final String description;
  final String proTip;

  const _TutorialStep({
    required this.icon,
    required this.badgeColor,
    required this.title,
    required this.description,
    required this.proTip,
  });
}

class InteractiveTutorialModal extends StatefulWidget {
  final bool isSupplier;

  const InteractiveTutorialModal({
    super.key,
    required this.isSupplier,
  });

  static Future<void> show(BuildContext context, {required bool isSupplier}) {
    return showDialog<void>(
      context: context,
      builder: (_) => InteractiveTutorialModal(isSupplier: isSupplier),
    );
  }

  @override
  State<InteractiveTutorialModal> createState() =>
      _InteractiveTutorialModalState();
}

class _InteractiveTutorialModalState extends State<InteractiveTutorialModal> {
  int _stepIndex = 0;

  List<_TutorialStep> get _steps => widget.isSupplier
      ? const [
          _TutorialStep(
            icon: Icons.inventory_2_outlined,
            badgeColor: AppColors.primaryBlue,
            title: '1. Publica tu Catálogo y Escalas',
            description:
                'Ve a la pestaña "Mi Catálogo" para agregar tus insumos con precio base (IVA 13% incluido), stock opcional y descuentos por volumen (mayoreo).',
            proTip:
                'Abasto suma un 3% adicional al comprador aparte; tú recibes y facturas únicamente tu precio base publicado.',
          ),
          _TutorialStep(
            icon: Icons.local_shipping_outlined,
            badgeColor: Color(0xFF0F766E),
            title: '2. Gestiona Despachos y Ruta GPS',
            description:
                'En "Despachos" verás cada pedido pagado. Toca "Ver Ficha y Mapa" en el nombre del restaurante para abrir Google Maps y ver instrucciones de descarga.',
            proTip:
                'Actualiza el estado a "En Ruta" al salir a repartir y a "Entregado" al completar la entrega en cocina.',
          ),
          _TutorialStep(
            icon: Icons.receipt_long_outlined,
            badgeColor: Color(0xFFB45309),
            title: '3. Emite y Sube el DTE (CCF / Factura)',
            description:
                'Toca la etiqueta fiscal del pedido para copiar el NRC, NIT, Razón Social y Giro del restaurante, y adjunta el PDF generado en Hacienda.',
            proTip:
                'Puedes previsualizar el PDF antes de guardarlo para confirmar que sea el documento correcto.',
          ),
          _TutorialStep(
            icon: Icons.account_balance_wallet_outlined,
            badgeColor: Color(0xFF16A34A),
            title: '4. Cobra tus Liquidaciones los Viernes',
            description:
                'Todos los pedidos marcados como "Entregado" (sin incidencias abiertas) se transfieren a tu cuenta bancaria cada viernes con retención del 5% (0% con bono referido).',
            proTip:
                'Configura tu cuenta bancaria desde la tarjeta superior de "Saldo por Liquidar" y descarga tus reportes en CSV.',
          ),
        ]
      : const [
          _TutorialStep(
            icon: Icons.storefront_outlined,
            badgeColor: AppColors.primaryBlue,
            title: '1. Explora Distribuidores Verificados',
            description:
                'Filtra por categoría (Verduras, Lácteos, Carnes, Abarrotes, etc.) y entra al catálogo de cada distribuidor para ver precios con IVA incluido y descuentos por volumen.',
            proTip:
                'Toca la calificación con estrellas de cualquier distribuidor para ver sus reseñas y tiempos de entrega.',
          ),
          _TutorialStep(
            icon: Icons.shopping_cart_checkout_outlined,
            badgeColor: Color(0xFF0F766E),
            title: '2. Arma tu Carrito y Elige tu DTE',
            description:
                'Al alcanzar el pedido mínimo del proveedor, abre el carrito y elige si necesitas Crédito Fiscal (CCF / DTE-03) para deducir IVA o Factura Electrónica (DTE-01).',
            proTip:
                'Usa "Guardar como lista semanal" en el carrito para recargar tus compras recurrentes en un clic.',
          ),
          _TutorialStep(
            icon: Icons.lock_outline,
            badgeColor: Color(0xFF4F46E5),
            title: '3. Paga Seguro con Wompi',
            description:
                'Desde la pestaña "Pedidos", paga tu orden con tarjeta de débito o crédito a través de Wompi. El pedido pasa a Confirmado automáticamente.',
            proTip:
                'Antes de pagar puedes modificar cantidades o cancelar el pedido sin costo.',
          ),
          _TutorialStep(
            icon: Icons.description_outlined,
            badgeColor: Color(0xFFB45309),
            title: '4. Descarga tus CCF y Exporta Contabilidad',
            description:
                'Cuando el distribuidor adjunte tu CCF o Factura, descárgalo directo en la tarjeta del pedido. También puedes exportar todo tu historial a Excel/CSV.',
            proTip:
                'Si un insumo llega incompleto o dañado al entregarse, usa "Reportar Faltante" para proteger tu compra.',
          ),
        ];

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIndex];
    final isFirst = _stepIndex == 0;
    final isLast = _stepIndex == _steps.length - 1;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.isSupplier
                          ? 'Guía Rápida • Distribuidor'
                          : 'Guía Rápida • Restaurante',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Ícono destacado del paso
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: step.badgeColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(step.icon, size: 34, color: step.badgeColor),
                ),
              ),
              const SizedBox(height: 16),

              // Título y descripción
              Text(
                step.title,
                style: const TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                step.description,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 14),

              // Consejo práctico
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 18, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.proTip,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Indicadores de paso (puntos)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final active = i == _stepIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.primaryBlue
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 18),

              // Botones de navegación
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: isFirst
                        ? null
                        : () => setState(() => _stepIndex--),
                    child: const Text('Anterior'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLast
                          ? const Color(0xFF16A34A)
                          : AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: Icon(
                      isLast ? Icons.check : Icons.arrow_forward,
                      size: 17,
                    ),
                    label: Text(
                      isLast ? '¡Entendido!' : 'Siguiente',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      if (isLast) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _stepIndex++);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}