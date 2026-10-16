import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/session_manager.dart';
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
  bool _isLoadingInitialData = true;

  final ImagePicker _imagePicker = ImagePicker();

  // Paso 1: Perfil y Datos Comerciales (Tabla 'profiles')
  final _businessNameCtrl = TextEditingController(text: 'Mi Distribuidora');
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _nrcNitCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _businessHoursCtrl =
      TextEditingController(text: 'Lunes a Sábado: 7:00 AM - 5:00 PM');

  // Paso 2: Rubros y Logística de Distribución (Tabla 'supplier_details')
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

  final _coverageCtrl = TextEditingController(
    text: 'Santa Tecla, Antiguo Cuscatlán, San Salvador',
  );
  final _deliveryDaysCtrl = TextEditingController(
    text: 'Lunes a Sábado (Entregas matutinas)',
  );
  final _minOrderCtrl = TextEditingController(text: '25.00');

  // Paso 3: Catálogo inicial (Tabla 'products')
  bool _startCatalogFromZero = false;
  final List<Map<String, dynamic>> _initialProducts = [];

  @override
  void initState() {
    super.initState();
    _addProductRow();
    _loadExistingProfileData();
  }

  Future<void> _loadExistingProfileData() async {
    try {
      final currentAuthId = supabase.auth.currentUser?.id;
      final userId = widget.supplierId.isNotEmpty
          ? widget.supplierId
          : (currentAuthId ?? SessionManager.currentUserId);

      if (userId.isNotEmpty) {
        final profile = await supabase
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 4));

        if (profile != null && mounted) {
          setState(() {
            if ((profile['business_name'] ?? '').toString().isNotEmpty) {
              _businessNameCtrl.text = profile['business_name'];
            }
            if ((profile['phone'] ?? '').toString().isNotEmpty) {
              _phoneCtrl.text = profile['phone'];
            }
            if ((profile['address'] ?? '').toString().isNotEmpty) {
              _addressCtrl.text = profile['address'];
            }
            if ((profile['website'] ?? '').toString().isNotEmpty) {
              _websiteCtrl.text = profile['website'];
            }
            if ((profile['nrc_nit'] ?? '').toString().isNotEmpty) {
              _nrcNitCtrl.text = profile['nrc_nit'];
            }
            if ((profile['business_hours'] ?? '').toString().isNotEmpty) {
              _businessHoursCtrl.text = profile['business_hours'];
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Aviso cargando datos de distribuidor: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitialData = false);
      }
    }
  }

  @override
  void dispose() {
    _businessNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _nrcNitCtrl.dispose();
    _websiteCtrl.dispose();
    _businessHoursCtrl.dispose();
    _categoryDetailsCtrl.dispose();
    _coverageCtrl.dispose();
    _deliveryDaysCtrl.dispose();
    _minOrderCtrl.dispose();
    for (var row in _initialProducts) {
      (row['name'] as TextEditingController).dispose();
      (row['unit'] as TextEditingController).dispose();
      (row['price'] as TextEditingController).dispose();
      (row['image_url'] as TextEditingController).dispose();
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
        'image_url': TextEditingController(),
        'isUploading': false,
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
        (row['image_url'] as TextEditingController).dispose();
      });
    }
  }

  Future<void> _pickAndUploadImage(Map<String, dynamic> row) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1024,
      );

      if (file == null) return;

      setState(() => row['isUploading'] = true);

      final bytes = await file.readAsBytes();
      final fileExt = file.name.split('.').last.toLowerCase();
      final currentAuthId = supabase.auth.currentUser?.id ?? widget.supplierId;
      final fileName =
          '$currentAuthId/${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supabase.storage.from('product-images').uploadBinary(
            fileName,
            bytes,
          );

      final publicUrl =
          supabase.storage.from('product-images').getPublicUrl(fileName);

      setState(() {
        (row['image_url'] as TextEditingController).text = publicUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto del insumo subida con éxito.'),
            backgroundColor: AppColors.tealMint,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => row['isUploading'] = false);
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isSaving = true);
    final currentAuthId = supabase.auth.currentUser?.id;
    final userId = widget.supplierId.isNotEmpty
        ? widget.supplierId
        : (currentAuthId ?? SessionManager.currentUserId);

    if (userId.isEmpty) {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
          (route) => false,
        );
      }
      return;
    }

    try {
      final consolidatedCategory = _categoryDetailsCtrl.text.trim().isNotEmpty
          ? _categoryDetailsCtrl.text.trim()
          : _selectedCategories.join(', ');

      // 1. Guardar y actualizar ficha en 'profiles' asegurando rol supplier
      await supabase.from('profiles').upsert({
        'id': userId,
        'business_name': _businessNameCtrl.text.trim().isNotEmpty
            ? _businessNameCtrl.text.trim()
            : 'Mi Distribuidora',
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isNotEmpty
            ? _addressCtrl.text.trim()
            : 'Dirección central de distribución',
        'nrc_nit': _nrcNitCtrl.text.trim().isNotEmpty
            ? _nrcNitCtrl.text.trim()
            : 'En trámite de registro',
        'website': _websiteCtrl.text.trim(),
        'business_hours': _businessHoursCtrl.text.trim(),
        'role': 'supplier',
      });

      // 2. Guardar la configuración en 'supplier_details'
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

      // 3. Si eligió registrar productos iniciales, insertarlos
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
          final imgUrl =
              (row['image_url'] as TextEditingController).text.trim();

          if (name.isNotEmpty) {
            productsToInsert.add({
              'supplier_id': userId,
              'category': cat,
              'name': name,
              'unit': unit.isEmpty ? 'unidad' : unit,
              'price': price,
              'image_url': imgUrl.isNotEmpty ? imgUrl : null,
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

  Widget _buildStepIndicator() {
    final steps = ['Perfil Comercial', 'Rubro & Cobertura', 'Catálogo'];
    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = _currentStep == index;
        final isDone = _currentStep > index;

        return Expanded(
          child: InkWell(
            onTap: isDone ? () => setState(() => _currentStep = index) : null,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isDone
                      ? AppColors.tealMint
                      : (isActive ? AppColors.primaryBlue : Colors.grey.shade300),
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? Colors.white : Colors.grey.shade700,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    steps[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive || isDone
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isActive ? AppColors.navyDark : AppColors.subtitleGrey,
                    ),
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: isDone ? AppColors.tealMint : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Información Legal y Comercial',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Esta información se mostrará en tu ficha pública para generar confianza con los restaurantes compradores.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 18),

        TextField(
          controller: _businessNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre Comercial / Empresa',
            hintText: 'Ej. Distribuidora Santa Tecla',
            prefixIcon: Icon(Icons.business_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono / WhatsApp de Despacho',
            hintText: 'Ej. 7000-0000',
            prefixIcon: Icon(Icons.phone_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _nrcNitCtrl,
          decoration: const InputDecoration(
            labelText: 'Número de Registro Comercial (NRC / NIT)',
            hintText: 'Ej. 123456-7 o En trámite',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Dirección Física / Bodega Principal',
            hintText: 'Ej. Calle El Pedregal, Bodega #4, Antiguo Cuscatlán',
            prefixIcon: Icon(Icons.location_on_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _businessHoursCtrl,
          decoration: const InputDecoration(
            labelText: 'Horario de Atención y Despacho',
            hintText: 'Ej. Lunes a Sábado: 7:00 AM - 5:00 PM',
            prefixIcon: Icon(Icons.access_time),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _websiteCtrl,
          decoration: const InputDecoration(
            labelText: 'Página Web o Red Social',
            hintText: 'Ej. @midistribuidora o www.distribuidora.sv',
            prefixIcon: Icon(Icons.language_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Qué rubros de insumos abasteces?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Selecciona las categorías principales. Los restaurantes filtrarán su búsqueda basándose en ellas.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
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
                color: isSelected ? AppColors.primaryBlue : AppColors.navyDark,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
            hintText: 'Ej. Verduras frescas, Granos selectos',
            prefixIcon: Icon(Icons.category_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 14),

        const Text(
          'Zonas y frecuencia de reparto',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Define tus rutas y el monto mínimo requerido para entregar pedidos.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _coverageCtrl,
          decoration: const InputDecoration(
            labelText: 'Zonas / Municipios con cobertura de entrega',
            hintText: 'Ej. Santa Tecla, Antiguo Cuscatlán, San Salvador',
            prefixIcon: Icon(Icons.map_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _deliveryDaysCtrl,
          decoration: const InputDecoration(
            labelText: 'Días y horarios habituales de entrega',
            hintText: 'Ej. Lunes a Sábado (Entregas matutinas)',
            prefixIcon: Icon(Icons.local_shipping_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),

        TextField(
          controller: _minOrderCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Pedido mínimo para despacho (\$ USD)',
            prefixIcon: Icon(Icons.attach_money),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    final availableCategoryOptions = _selectedCategories.isNotEmpty
        ? _selectedCategories.toList()
        : _commonCategories;

    return Column(
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
        const SizedBox(height: 4),
        const Text(
          'Puedes publicar tus insumos clave ahora o subirlos más adelante desde la sección Mi Catálogo.',
          style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
        ),
        const SizedBox(height: 16),

        RadioListTile<bool>(
          contentPadding: EdgeInsets.zero,
          value: false,
          groupValue: _startCatalogFromZero,
          title: const Text(
            'Registrar mis primeros productos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            'Comienza a recibir órdenes de restaurantes de inmediato.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (val) => setState(() => _startCatalogFromZero = val!),
        ),
        RadioListTile<bool>(
          contentPadding: EdgeInsets.zero,
          value: true,
          groupValue: _startCatalogFromZero,
          title: const Text(
            'Subir catálogo después',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: const Text(
            'Completarás el listado de inventario desde el panel principal.',
            style: TextStyle(fontSize: 12),
          ),
          onChanged: (val) => setState(() => _startCatalogFromZero = val!),
        ),

        if (!_startCatalogFromZero) ...[
          const Divider(height: 24),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              children: const [
                Icon(Icons.cloud_upload_outlined,
                    size: 18, color: Color(0xFF16A34A)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Las fotos son opcionales. Puedes subirlas directamente desde tu dispositivo o dejarlas para después.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF166534)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Insumos iniciales por categoría:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
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
          const SizedBox(height: 10),

          ..._initialProducts.asMap().entries.map((entry) {
            final idx = entry.key;
            final row = entry.value;

            String currentCat = row['category'] as String;
            if (!availableCategoryOptions.contains(currentCat)) {
              currentCat = availableCategoryOptions.first;
              row['category'] = currentCat;
            }

            final imgCtrl = row['image_url'] as TextEditingController;
            final bool hasImage = imgCtrl.text.trim().isNotEmpty;
            final bool isUploading = row['isUploading'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 14.0),
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
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
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: availableCategoryOptions
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(cat,
                                        style: const TextStyle(fontSize: 13)),
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
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: row['name'] as TextEditingController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del Insumo',
                              hintText: 'Ej. Queso Morolique',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row['unit'] as TextEditingController,
                            decoration: const InputDecoration(
                              labelText: 'Presentación',
                              hintText: 'Caja 50 lb',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row['price'] as TextEditingController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Precio',
                              hintText: '\$ USD',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        if (hasImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              imgCtrl.text.trim(),
                              width: 38,
                              height: 38,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 38,
                                height: 38,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image,
                                    size: 18, color: Colors.grey),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],

                        isUploading
                            ? Row(
                                children: const [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Subiendo imagen...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ],
                              )
                            : OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  side: BorderSide(
                                    color: hasImage
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                  backgroundColor: hasImage
                                      ? const Color(0xFFECFDF5)
                                      : Colors.white,
                                ),
                                icon: Icon(
                                  hasImage
                                      ? Icons.check_circle_outline
                                      : Icons.photo_camera_outlined,
                                  size: 16,
                                  color: hasImage
                                      ? const Color(0xFF059669)
                                      : AppColors.primaryBlue,
                                ),
                                label: Text(
                                  hasImage
                                      ? 'Cambiar foto'
                                      : 'Subir foto (Opcional)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: hasImage
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: hasImage
                                        ? const Color(0xFF059669)
                                        : AppColors.navyDark,
                                  ),
                                ),
                                onPressed: () => _pickAndUploadImage(row),
                              ),

                        if (hasImage) ...[
                          IconButton(
                            tooltip: 'Eliminar foto',
                            icon: const Icon(Icons.close,
                                size: 16, color: Colors.redAccent),
                            onPressed: () {
                              setState(() {
                                imgCtrl.clear();
                              });
                            },
                          ),
                        ],

                        const Spacer(),
                        const Text(
                          'Puedes ponerla después',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppColors.subtitleGrey,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInitialData) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'Configura tu Distribuidora',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStepIndicator(),
                      const SizedBox(height: 24),
                      const Divider(height: 1),
                      const SizedBox(height: 24),

                      if (_currentStep == 0) _buildStep1(),
                      if (_currentStep == 1) _buildStep2(),
                      if (_currentStep == 2) _buildStep3(),

                      const SizedBox(height: 28),
                      Row(
                        children: [
                          if (_currentStep > 0) ...[
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: () =>
                                  setState(() => _currentStep -= 1),
                              child: const Text('Atrás'),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () {
                                      if (_currentStep < 2) {
                                        setState(() => _currentStep += 1);
                                      } else {
                                        _completeOnboarding();
                                      }
                                    },
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
                                      _currentStep == 2
                                          ? 'Publicar Distribuidora'
                                          : 'Continuar',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}