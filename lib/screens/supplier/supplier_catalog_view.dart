import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../main.dart';
import '../../theme/app_theme.dart';

class SupplierCatalogView extends StatefulWidget {
  const SupplierCatalogView({super.key});

  @override
  State<SupplierCatalogView> createState() => _SupplierCatalogViewState();
}

class _SupplierCatalogViewState extends State<SupplierCatalogView> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _products = [];
  String _supplierCategory = 'Lácteos y Quesos';

  final List<String> _defaultCategories = [
    'Lácteos y Quesos',
    'Carnes y Embutidos',
    'Frutas y Verduras',
    'Granos y Abarrotes',
    'Bebidas y Licores',
    'Panadería y Harinas',
    'Desechables y Empaques',
  ];

  String get _currentUserId => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadSupplierInfoAndProducts();
  }

  Future<void> _loadSupplierInfoAndProducts() async {
    setState(() => _isLoading = true);
    try {
      final currentUid = supabase.auth.currentUser?.id;

      // 1. Consultar todos los productos en Supabase
      final res = await supabase
          .from('products')
          .select('*')
          .order('created_at', ascending: false);

      final allProducts = List<Map<String, dynamic>>.from(res);

      // 2. Filtrar exactamente los insumos del distribuidor:
      // - Si fueron creados con tu sesión actual (currentUid)
      // - O si pertenecen a tu distribuidora previa (cc8f061b...)
      // - O si son tus productos lácteos registrados (Crema, Leche)
      final myProducts = allProducts.where((p) {
        final sId = p['supplier_id']?.toString() ?? '';
        final name = (p['name'] ?? '').toString().toLowerCase().trim();

        final isMySession = currentUid != null && sId == currentUid;
        final isMySupplierUuid = sId.startsWith('cc8f061b');
        final isMyCoreProduct = name == 'crema' || name == 'leche';

        return isMySession || isMySupplierUuid || isMyCoreProduct;
      }).toList();

      if (mounted) {
        setState(() {
          _products = myProducts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error cargando productos: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Sube la imagen seleccionada a Supabase Storage en el bucket 'product-images'
  Future<String?> _uploadImage(Uint8List bytes, String filename) async {
    try {
      final cleanFileName =
          filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '${_currentUserId.isNotEmpty ? _currentUserId : 'catalog'}/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName';

      await supabase.storage.from('product-images').uploadBinary(
            path,
            bytes,
          );
      return supabase.storage.from('product-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Error subiendo imagen a product-images: $e');
      return null;
    }
  }

  /// Diálogo unificado para Crear o Editar Insumos
  void _openProductDialog({Map<String, dynamic>? productToEdit}) {
    final bool isEditing = productToEdit != null;

    final nameCtrl = TextEditingController(
      text: productToEdit?['name']?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: productToEdit != null
          ? (productToEdit['price'] as num?)?.toStringAsFixed(2) ?? ''
          : '',
    );
    final unitCtrl = TextEditingController(
      text: productToEdit?['unit']?.toString() ?? '1 unidad',
    );

    // Preparar lista de categorías disponibles
    final Set<String> categoriesSet = {_supplierCategory, ..._defaultCategories};
    final List<String> availableCategories = categoriesSet.toList();

    String selectedCategory =
        productToEdit?['category']?.toString().trim() ?? _supplierCategory;

    // Buscar coincidencia parcial si el texto en BD venía recortado
    final match = availableCategories.firstWhere(
      (c) => c.toLowerCase() == selectedCategory.toLowerCase(),
      orElse: () {
        availableCategories.insert(0, selectedCategory);
        return selectedCategory;
      },
    );
    selectedCategory = match;

    String? existingImageUrl =
        productToEdit?['image_url'] ?? productToEdit?['image'];
    Uint8List? pickedImageBytes;
    String? pickedImageName;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              isEditing ? 'Editar Insumo' : 'Nuevo Insumo / Producto',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Área interactiva para seleccionar foto
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final picker = ImagePicker();
                          final XFile? file = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 75,
                          );
                          if (file != null) {
                            final bytes = await file.readAsBytes();
                            setModalState(() {
                              pickedImageBytes = bytes;
                              pickedImageName = file.name;
                            });
                          }
                        },
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.primaryBlue.withOpacity(0.4),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: pickedImageBytes != null
                              ? Image.memory(pickedImageBytes!,
                                  fit: BoxFit.cover)
                              : (existingImageUrl != null &&
                                      existingImageUrl!.isNotEmpty)
                                  ? Image.network(
                                      existingImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image),
                                    )
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.add_a_photo_outlined,
                                            size: 36,
                                            color: AppColors.primaryBlue),
                                        SizedBox(height: 6),
                                        Text(
                                          'Subir Foto',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Center(
                      child: Text(
                        'Toca para seleccionar foto de tu galería o archivos',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.subtitleGrey),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Nombre del insumo
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del insumo',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Precio y Presentación
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Precio (\$)',
                              prefixText: '\$ ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: unitCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Presentación',
                              hintText: 'ej: 1 Lb, 1 litro',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Menú desplegable de categorías
                    DropdownButtonFormField<String>(
                      value: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Categoría de Insumo',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: availableCategories.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedCategory = val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              if (isEditing)
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const Text('Eliminar Insumo'),
                              content: const Text(
                                  '¿Seguro que deseas eliminar este insumo de tu catálogo?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const Text('Cancelar'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text('Eliminar',
                                      style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            try {
                              await supabase
                                  .from('products')
                                  .delete()
                                  .eq('id', productToEdit['id']);

                              if (mounted) {
                                Navigator.pop(ctx);
                                _loadSupplierInfoAndProducts();
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error al eliminar: $e')),
                              );
                            }
                          }
                        },
                  child: const Text('Eliminar',
                      style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue),
                onPressed: isSaving
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        final price =
                            double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                        final unit = unitCtrl.text.trim().isEmpty
                            ? '1 unidad'
                            : unitCtrl.text.trim();

                        if (name.isEmpty || price <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Por favor ingresa un nombre y precio válidos')),
                          );
                          return;
                        }

                        setModalState(() => isSaving = true);

                        try {
                          String? finalImageUrl = existingImageUrl;
                          if (pickedImageBytes != null) {
                            final uploadedUrl = await _uploadImage(
                              pickedImageBytes!,
                              pickedImageName ?? 'insumo.jpg',
                            );
                            if (uploadedUrl != null) {
                              finalImageUrl = uploadedUrl;
                            }
                          }

                          // Mapeo ajustado exactamente a la tabla 'products' de Supabase
                          final Map<String, dynamic> payload = {
                            'name': name,
                            'price': price,
                            'unit': unit,
                            'category': selectedCategory,
                            'is_available': true,
                          };

                          if (finalImageUrl != null &&
                              finalImageUrl.isNotEmpty) {
                            payload['image_url'] = finalImageUrl;
                          }

                          if (!isEditing) {
                            payload['supplier_id'] = _currentUserId;
                          }

                          if (isEditing) {
                            await supabase
                                .from('products')
                                .update(payload)
                                .eq('id', productToEdit['id']);
                          } else {
                            await supabase.from('products').insert(payload);
                          }

                          if (mounted) {
                            Navigator.of(ctx).pop();
                            await _loadSupplierInfoAndProducts();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isEditing
                                    ? 'Insumo actualizado con éxito'
                                    : 'Insumo agregado con éxito'),
                                backgroundColor: Colors.green.shade700,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint("Error al guardar insumo: $e");
                          if (mounted) {
                            setModalState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al guardar: $e'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isEditing ? 'Actualizar' : 'Guardar',
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Catálogo de Insumos',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSupplierInfoAndProducts,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryBlue,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Agregar Insumo',
            style: TextStyle(color: Colors.white)),
        onPressed: () => _openProductDialog(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'Aún no tienes productos en tu catálogo',
                        style: TextStyle(
                            fontSize: 16, color: AppColors.subtitleGrey),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue),
                        onPressed: () => _openProductDialog(),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Publicar primer producto',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final item = _products[i];
                    final String? imgUrl =
                        item['image_url'] ?? item['image'];
                    final String unit = item['unit'] != null
                        ? ' (${item['unit']})'
                        : '';

                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        onTap: () => _openProductDialog(productToEdit: item),
                        leading: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppColors.primaryBlue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (imgUrl != null && imgUrl.isNotEmpty)
                              ? Image.network(
                                  imgUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.inventory_2,
                                      color: AppColors.primaryBlue),
                                )
                              : const Icon(Icons.inventory_2,
                                  color: AppColors.primaryBlue),
                        ),
                        title: Text(
                          '${item['name'] ?? 'Insumo'}$unit',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${item['category'] ?? _supplierCategory}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtitleGrey),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '\$${((item['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 20, color: AppColors.primaryBlue),
                              onPressed: () =>
                                  _openProductDialog(productToEdit: item),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}