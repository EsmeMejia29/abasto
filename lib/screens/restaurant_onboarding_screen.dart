import 'package:flutter/material.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../utils/error_handler.dart';

class RestaurantOnboardingScreen extends StatefulWidget {
  final String restaurantId;

  const RestaurantOnboardingScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantOnboardingScreen> createState() =>
      _RestaurantOnboardingScreenState();
}

class _RestaurantOnboardingScreenState
    extends State<RestaurantOnboardingScreen> {
  int _currentStep = 0;
  bool _isSaving = false;

  // Paso 1: Giro del restaurante
  final _restaurantTypeCtrl =
      TextEditingController(text: 'Pupusería / Restaurante Típico');
  final List<String> _commonTypes = [
    'Pupusería / Típico',
    'Cafetería & Pastelería',
    'Pizzería & Pastas',
    'Restaurante de Carnes / Parrilla',
    'Taquería / Comida Mexicana',
    'Comida Rápida / Hamburguesas',
    'Mariscos',
    'Comedor / Almuerzos Ejecutivos',
  ];

  // Paso 2: Insumos que necesita
  final List<String> _availableSupplies = [
    'Verduras y Hortalizas',
    'Lácteos y Quesillo',
    'Carnes y Aves',
    'Mariscos frescos',
    'Harinas y Granos Básicos',
    'Abarrotes y Especias',
    'Desechables y Empaques',
  ];
  final Set<String> _selectedSupplies = {
    'Verduras y Hortalizas',
    'Lácteos y Quesillo'
  };
  String _orderFrequency = '2 a 3 veces por semana';
  final _budgetCtrl = TextEditingController(text: '1200');

  // Paso 3: Inventario inicial
  bool _startFromZero = true;
  final List<Map<String, TextEditingController>> _initialInventoryItems = [];

  @override
  void initState() {
    super.initState();
    _addItemRow();
  }

  void _addItemRow() {
    setState(() {
      _initialInventoryItems.add({
        'name': TextEditingController(),
        'category': TextEditingController(text: 'Verduras'),
        'stock': TextEditingController(),
        'unit': TextEditingController(text: 'lb'),
      });
    });
  }

  void _removeItemRow(int index) {
    if (_initialInventoryItems.length > 1) {
      setState(() {
        _initialInventoryItems.removeAt(index);
      });
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isSaving = true);
    final userId = widget.restaurantId;

    try {
      // 1. Guardar perfil operacional del restaurante
      await supabase.from('restaurant_details').upsert({
        'profile_id': userId,
        'restaurant_type': _restaurantTypeCtrl.text.trim(),
        'needed_supplies': _selectedSupplies.toList(),
        'order_frequency': _orderFrequency,
        'monthly_budget': double.tryParse(_budgetCtrl.text) ?? 0.00,
        'onboarding_completed': true,
      });

      // 2. Si decidió registrar inventario inicial, insertarlo en la tabla
      if (!_startFromZero) {
        final itemsToInsert = <Map<String, dynamic>>[];
        for (var row in _initialInventoryItems) {
          final name = row['name']!.text.trim();
          final stock = double.tryParse(row['stock']!.text.trim()) ?? 0.0;
          final unit = row['unit']!.text.trim();
          final category = row['category']!.text.trim();

          if (name.isNotEmpty) {
            itemsToInsert.add({
              'restaurant_id': userId,
              'product_name': name,
              'category': category.isEmpty ? 'General' : category,
              'current_stock': stock,
              'unit': unit.isEmpty ? 'unidades' : unit,
              'total_spent': 0.0,
            });
          }
        }

        if (itemsToInsert.isNotEmpty) {
          await supabase.from('restaurant_inventory').insert(itemsToInsert);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Configuración inicial guardada con éxito!'),
            backgroundColor: AppColors.tealMint,
          ),
        );

        // Avanzar a la aplicación principal
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del Restaurante'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stepper(
          type: StepperType.horizontal,
          currentStep: _currentStep,
          onStepContinue: () {
            if (_currentStep < 2) {
              setState(() => _currentStep += 1);
            } else {
              _completeOnboarding();
            }
          },
          onStepCancel: () {
            if (_currentStep > 0) {
              setState(() => _currentStep -= 1);
            }
          },
          controlsBuilder: (context, details) {
            final isLastStep = _currentStep == 2;
            return Padding(
              padding: const EdgeInsets.only(top: 24.0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _isSaving ? null : details.onStepContinue,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isLastStep ? 'Finalizar y Entrar' : 'Siguiente',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Atrás'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            // PASO 1: Especialidad del negocio
            Step(
              title: const Text('Giro'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿A qué se dedica tu restaurante?',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Esto nos ayuda a priorizar los distribuidores y precios más convenientes para tu cocina.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _commonTypes.map((type) {
                      final isSelected = _restaurantTypeCtrl.text == type;
                      return ChoiceChip(
                        label: Text(type),
                        selected: isSelected,
                        selectedColor: AppColors.tealMint.withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : AppColors.subtitleGrey,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _restaurantTypeCtrl.text = type);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _restaurantTypeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Otro giro / Especialidad personalizada',
                      prefixIcon: Icon(Icons.edit),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // PASO 2: Insumos y Frecuencia de compras
            Step(
              title: const Text('Insumos'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿Qué insumos compras frecuentemente?',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableSupplies.map((supply) {
                      final isChecked = _selectedSupplies.contains(supply);
                      return FilterChip(
                        label: Text(supply),
                        selected: isChecked,
                        selectedColor: AppColors.tealMint.withOpacity(0.25),
                        checkmarkColor: AppColors.primaryBlue,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedSupplies.add(supply);
                            } else {
                              _selectedSupplies.remove(supply);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Frecuencia de pedidos a proveedores:',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _orderFrequency,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'Diario (Frescura)', child: Text('Diario')),
                      DropdownMenuItem(
                          value: '2 a 3 veces por semana',
                          child: Text('2 a 3 veces por semana')),
                      DropdownMenuItem(
                          value: 'Semanal', child: Text('Semanal')),
                      DropdownMenuItem(
                          value: 'Quincenal', child: Text('Quincenal')),
                    ],
                    onChanged: (val) =>
                        setState(() => _orderFrequency = val ?? _orderFrequency),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _budgetCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Presupuesto mensual estimado en compras (\$ USD)',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // PASO 3: Inventario Actual (Cero vs Registrar)
            Step(
              title: const Text('Inventario'),
              isActive: _currentStep >= 2,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿Cómo deseas comenzar tu inventario?',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.navyDark),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _startFromZero,
                    title: const Text('Empezar desde cero',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Tu inventario se irá llenando de forma automática a medida que confirmes pedidos con distribuidores.'),
                    onChanged: (val) => setState(() => _startFromZero = val!),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _startFromZero,
                    title: const Text('Registrar existencias actuales',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Ingresa los insumos que ya tienes en bodega o refrigerador para controlarlos desde hoy.'),
                    onChanged: (val) => setState(() => _startFromZero = val!),
                  ),
                  if (!_startFromZero) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Insumos iniciales:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navyDark),
                        ),
                        TextButton.icon(
                          onPressed: _addItemRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Agregar otro'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._initialInventoryItems.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: row['name'],
                                decoration: const InputDecoration(
                                  hintText: 'Insumo (ej. Tomate)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: row['stock'],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  hintText: 'Cantidad',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: row['unit'],
                                decoration: const InputDecoration(
                                  hintText: 'Unidad (lb, cj)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            if (_initialInventoryItems.length > 1)
                              IconButton(
                                icon: const Icon(Icons.close,
                                    size: 18, color: Colors.grey),
                                onPressed: () => _removeItemRow(idx),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}