import 'package:flutter/material.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';

class SupplierOnboardingScreen extends StatefulWidget {
  final String supplierId;

  const SupplierOnboardingScreen({super.key, required this.supplierId});

  @override
  State<SupplierOnboardingScreen> createState() =>
      _SupplierOnboardingScreenState();
}

class _SupplierOnboardingScreenState extends State<SupplierOnboardingScreen> {
  int _currentStep = 0;
  bool _isSaving = false;

  // Paso 1: Selección Múltiple de Rubros
  final List<String> _commonCategories = [
    'Verduras y Hortalizas',
    'Lácteos y Quesos',
    'Carnes y Aves',
    'Mariscos Frescos',
    'Abarrotes y Harinas',
    'Desechables y Empaques',
  ];

  final Set<String> _selectedCategories = {'Verduras y Hortalizas'};
  final TextEditingController _categoryDetailsCtrl = TextEditingController(
    text: 'Verduras y Hortalizas',
  );

  // Paso 2: Cobertura y Logística
  final _coverageCtrl = TextEditingController(
    text: 'Santa Tecla, Antiguo Cuscatlán, San Salvador',
  );
  final _deliveryDaysCtrl = TextEditingController(
    text: 'Lunes a Sábado (Entregas matutinas)',
  );
  final _minOrderCtrl = TextEditingController(text: '25.00');

  // Paso 3: Catálogo inicial segmentado por categoría
  bool _startCatalogFromZero = false;
  final List<Map<String, dynamic>> _initialProducts = [];

  @override
  void initState() {
    super.initState();
    _addProductRow();
  }

  @override
  void dispose() {
    _categoryDetailsCtrl.dispose();
    _coverageCtrl.dispose();
    _deliveryDaysCtrl.dispose();
    _minOrderCtrl.dispose();
    for (var row in _initialProducts) {
      (row['name'] as TextEditingController).dispose();
      (row['unit'] as TextEditingController).dispose();
      (row['price'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  void _syncCategoryTextField() {
    if (_selectedCategories.isEmpty) {
      _categoryDetailsCtrl.text = '';
    } else {
      _categoryDetailsCtrl.text = _selectedCategories.join(', ');
    }
  }

  void _addProductRow() {
    final defaultCat = _selectedCategories.isNotEmpty
        ? _selectedCategories.first
        : 'General';

    setState(() {
      _initialProducts.add({
        'category': defaultCat,
        'name': TextEditingController(),
        'unit': TextEditingController(text: 'Caja 50 lb'),
        'price': TextEditingController(),
      });
    });
  }

  void _removeProductRow(int index) {
    if (_initialProducts.length > 1) {
      setState(() {
        final row = _initialProducts.removeAt(index);
        (row['name'] as TextEditingController).dispose();
        (row['unit'] as TextEditingController).dispose();
        (row['price'] as TextEditingController).dispose();
      });
    }
  }

  Future<void> _completeOnboarding() async {
    if (_selectedCategories.isEmpty &&
        _categoryDetailsCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona o ingresa al menos un rubro.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final userId = supabase.auth.currentUser?.id ?? widget.supplierId;

    try {
      final consolidatedCategory = _categoryDetailsCtrl.text.trim().isNotEmpty
          ? _categoryDetailsCtrl.text.trim()
          : _selectedCategories.join(', ');

      // 1. Guardar la configuración del distribuidor
      await supabase.from('supplier_details').upsert({
        'profile_id': userId,
        'category': consolidatedCategory,
        'delivery_coverage': _coverageCtrl.text.trim(),
        'delivery_days': _deliveryDaysCtrl.text.trim(),
        'min_order_amount': double.tryParse(
              _minOrderCtrl.text.replaceAll(r'$', '').trim(),
            ) ??
            0.00,
        'onboarding_completed': true,
      });

      // 2. Si eligió registrar productos, insertarlos asociados a su categoría
      if (!_startCatalogFromZero) {
        final productsToInsert = <Map<String, dynamic>>[];
        for (var row in _initialProducts) {
          final name = (row['name'] as TextEditingController).text.trim();
          final unit = (row['unit'] as TextEditingController).text.trim();
          final rawPrice = (row['price'] as TextEditingController)
              .text
              .replaceAll(r'$', '')
              .replaceAll(',', '.')
              .trim();
          final price = double.tryParse(rawPrice) ?? 0.0;
          final cat = row['category'] as String? ?? 'General';

          if (name.isNotEmpty) {
            productsToInsert.add({
              'supplier_id': userId,
              'category': cat,
              'name': name,
              'unit': unit.isEmpty ? 'unidad' : unit,
              'price': price,
              'is_available': true,
            });
          }
        }

        if (productsToInsert.isNotEmpty) {
          await supabase.from('products').insert(productsToInsert);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Distribuidora y catálogo guardados con éxito!'),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
          ),
        );

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
          SnackBar(
            content: Text('Error al guardar: $msg'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableCategoryOptions = _selectedCategories.isNotEmpty
        ? _selectedCategories.toList()
        : _commonCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Distribuidor'),
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
                              isLastStep
                                  ? 'Publicar Distribuidora'
                                  : 'Siguiente',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
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
            // PASO 1: Selección de Rubros
            Step(
              title: const Text('Rubro'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿Qué tipo de insumos distribuyes?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Puedes seleccionar varios rubros simultáneamente. Los restaurantes encontrarán tus productos en cada una de estas categorías.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.subtitleGrey),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _commonCategories.map((cat) {
                      final isSelected = _selectedCategories.contains(cat);
                      return FilterChip(
                        label: Text(cat),
                        selected: isSelected,
                        selectedColor: AppColors.tealMint.withOpacity(0.25),
                        checkmarkColor: AppColors.primaryBlue,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : AppColors.navyDark,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        onSelected: (bool selected) {
                          setState(() {
                            if (selected) {
                              _selectedCategories.add(cat);
                            } else {
                              _selectedCategories.remove(cat);
                            }
                            _syncCategoryTextField();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _categoryDetailsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Resumen o especialidades adicionales',
                      hintText: 'Ej. Verduras, Lácteos de Oriente, Carnes',
                      prefixIcon: Icon(Icons.category_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // PASO 2: Logística y Cobertura
            Step(
              title: const Text('Logística'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Zonas y frecuencia de reparto',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _coverageCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Zonas / Municipios con cobertura',
                      hintText:
                          'Ej. Santa Tecla, Antiguo Cuscatlán, San Salvador',
                      prefixIcon: Icon(Icons.map_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _deliveryDaysCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Días y horarios de despacho',
                      hintText: 'Ej. Lunes a Viernes (7:00 AM - 12:00 PM)',
                      prefixIcon: Icon(Icons.local_shipping_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _minOrderCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pedido mínimo para envío (\$ USD)',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),

            // PASO 3: Catálogo segmentado por categoría
            Step(
              title: const Text('Catálogo'),
              isActive: _currentStep >= 2,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '¿Deseas agregar tus primeros insumos ahora?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: _startCatalogFromZero,
                    title: const Text(
                      'Registrar mis primeros productos',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Agrega productos iniciales clasificándolos según los rubros que seleccionaste.',
                    ),
                    onChanged: (val) =>
                        setState(() => _startCatalogFromZero = val!),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: _startCatalogFromZero,
                    title: const Text(
                      'Subir catálogo después',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text(
                      'Podrás agregar productos en cualquier momento desde la pestaña "Mi Catálogo".',
                    ),
                    onChanged: (val) =>
                        setState(() => _startCatalogFromZero = val!),
                  ),
                  if (!_startCatalogFromZero) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Insumos iniciales por categoría:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addProductRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Agregar otro'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._initialProducts.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final row = entry.value;

                      String currentCat = row['category'] as String;
                      if (!availableCategoryOptions.contains(currentCat)) {
                        currentCat = availableCategoryOptions.first;
                        row['category'] = currentCat;
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12.0),
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      value: currentCat,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        labelText: 'Categoría del producto',
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      items: availableCategoryOptions
                                          .map(
                                            (cat) => DropdownMenuItem(
                                              value: cat,
                                              child: Text(
                                                cat,
                                                style: const TextStyle(
                                                    fontSize: 13),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => row['category'] = val);
                                        }
                                      },
                                    ),
                                  ),
                                  if (_initialProducts.length > 1)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 20,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => _removeProductRow(idx),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller:
                                          row['name'] as TextEditingController,
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
                                      controller:
                                          row['unit'] as TextEditingController,
                                      decoration: const InputDecoration(
                                        hintText: 'Unidad (Caja, lb)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    flex: 2,
                                    child: TextField(
                                      controller:
                                          row['price'] as TextEditingController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        hintText: 'Precio (\$)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
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