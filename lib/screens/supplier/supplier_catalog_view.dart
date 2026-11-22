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
  final String _supplierCategory = 'Lácteos y Quesos';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'Todos';

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
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSupplierInfoAndProducts() async {
    setState(() => _isLoading = true);
    try {
      final currentUid = supabase.auth.currentUser?.id;

      final res = await supabase
          .from('products')
          .select('*')
          .order('created_at', ascending: false);

      final allProducts = List<Map<String, dynamic>>.from(res);

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

  Future<void> _toggleAvailability(
      Map<String, dynamic> product, bool newValue) async {
    final prev = product['is_available'] ?? true;
    setState(() => product['is_available'] = newValue);

    try {
      await supabase
          .from('products')
          .update({'is_available': newValue}).eq('id', product['id']);
    } catch (e) {
      if (mounted) {
        setState(() => product['is_available'] = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar disponibilidad: $e')),
        );
      }
    }
  }

  Future<String?> _uploadImage(Uint8List bytes, String filename) async {
    try {
      final cleanFileName =
          filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '${_currentUserId.isNotEmpty ? _currentUserId : 'catalog'}/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName';

      await supabase.storage.from('product-images').uploadBinary(path, bytes);
      return supabase.storage.from('product-images').getPublicUrl(path);
    } catch (e) {
      debugPrint('Error subiendo imagen a product-images: $e');
      return null;
    }
  }

  void _showFullImageDialog({
    Uint8List? imageBytes,
    String? imageUrl,
  }) {
    if (imageBytes == null && (imageUrl == null || imageUrl.isEmpty)) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageBytes != null
                    ? Image.memory(
                        imageBytes,
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withOpacity(0.65),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Cerrar vista completa',
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

  void _openProductDialog({Map<String, dynamic>? productToEdit}) {
    final bool isEditing = productToEdit != null;

    final nameCtrl = TextEditingController(
      text: productToEdit?['name']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: productToEdit?['description']?.toString() ?? '',
    );
    final priceCtrl = TextEditingController(
      text: productToEdit != null
          ? (productToEdit['price'] as num?)?.toStringAsFixed(2) ?? ''
          : '',
    );
    final unitCtrl = TextEditingController(
      text: productToEdit?['unit']?.toString() ?? '1 unidad',
    );
    final stockCtrl = TextEditingController(
      text: productToEdit?['stock_quantity'] != null
          ? productToEdit!['stock_quantity'].toString()
          : '',
    );

    final rawTiers = (productToEdit?['bulk_tiers'] as List<dynamic>?) ?? [];
    final List<Map<String, TextEditingController>> tierControllers = rawTiers
        .map((t) => {
              'min_qty': TextEditingController(
                  text: (t['min_qty'] ?? '').toString()),
              'price': TextEditingController(
                  text: (t['price'] as num?)?.toStringAsFixed(2) ?? ''),
            })
        .toList();


    final Set<String> categoriesSet = {_supplierCategory, ..._defaultCategories};
    final List<String> availableCategories = categoriesSet.toList();

    String selectedCategory =
        productToEdit?['category']?.toString().trim() ?? _supplierCategory;

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
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: AppColors.navyDark),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (_) {
                        final bool hasAnyImage = pickedImageBytes != null ||
                            (existingImageUrl != null &&
                                existingImageUrl!.isNotEmpty);

                        Future<void> pickNewPhoto() async {
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
                        }

                        return Column(
                          children: [
                            Center(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: hasAnyImage
                                    ? () => _showFullImageDialog(
                                          imageBytes: pickedImageBytes,
                                          imageUrl: existingImageUrl,
                                        )
                                    : pickNewPhoto,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 170,
                                      height: 170,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.primaryBlue
                                              .withOpacity(0.35),
                                          width: 1.5,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: pickedImageBytes != null
                                          ? Image.memory(pickedImageBytes!,
                                              fit: BoxFit.contain)
                                          : (existingImageUrl != null &&
                                                  existingImageUrl!.isNotEmpty)
                                              ? Image.network(
                                                  existingImageUrl!,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(
                                                          Icons.broken_image),
                                                )
                                              : Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: const [
                                                    Icon(
                                                        Icons
                                                            .add_a_photo_outlined,
                                                        size: 38,
                                                        color: AppColors
                                                            .primaryBlue),
                                                    SizedBox(height: 8),
                                                    Text(
                                                      'Subir Foto',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: AppColors
                                                            .primaryBlue,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                    ),
                                    if (hasAnyImage)
                                      Positioned(
                                        bottom: 6,
                                        right: 6,
                                        child: Container(
                                          padding: const EdgeInsets.all(5),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.65),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.fullscreen_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (hasAnyImage)
                              Center(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: pickNewPhoto,
                                  icon: const Icon(
                                      Icons.photo_camera_outlined,
                                      size: 15),
                                  label: const Text(
                                    'Cambiar foto',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                            else
                              const Center(
                                child: Text(
                                  'Toca para seleccionar foto desde tu computadora o galería',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.subtitleGrey),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del insumo',
                        prefixIcon: Icon(Icons.shopping_bag_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción del producto (Opcional)',
                        hintText:
                            'Vacío = se asignará una descripción automática',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                              hintText: 'ej: Caja 50 lb, 1 litro',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Icon(Icons.info_outline,
                              size: 15, color: AppColors.primaryBlue),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ingresa tu precio base con IVA (13%) incluido. Al restaurante se le mostrará +3% adicional por tarifa de servicio Abasto (tú facturarás en tu DTE únicamente tu precio base).',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.35,
                                color: AppColors.navyDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Stock disponible (Opcional)',
                        hintText: 'Vacío = ilimitado (se pausa al llegar a 0)',
                        prefixIcon: Icon(Icons.inventory_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Precios por Volumen / Mayoreo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setModalState(() {
                              tierControllers.add({
                                'min_qty': TextEditingController(),
                                'price': TextEditingController(),
                              });
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline, size: 16),
                          label: const Text('Agregar escala',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    if (tierControllers.isEmpty)
                      const Text(
                        'Sin escalas: se aplicará el precio base para cualquier cantidad.',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.subtitleGrey),
                      )
                    else
                      ...tierControllers.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final tc = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: tc['min_qty'],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Desde (cant.)',
                                    hintText: 'Ej. 5',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: tc['price'],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Precio c/u (\$)',
                                    hintText: 'Ej. 9.50',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent, size: 20),
                                onPressed: () {
                                  setModalState(() {
                                    tierControllers.removeAt(idx);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }),
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

                          final parsedStock =
                              int.tryParse(stockCtrl.text.trim());
                          final parsedTiers = <Map<String, dynamic>>[];
                          for (var tc in tierControllers) {
                            final minQ =
                                int.tryParse(tc['min_qty']!.text.trim()) ?? 0;
                            final tierP =
                                double.tryParse(tc['price']!.text.trim()) ??
                                    0.0;
                            if (minQ > 1 && tierP > 0) {
                              parsedTiers
                                  .add({'min_qty': minQ, 'price': tierP});
                            }
                          }
                          parsedTiers.sort((a, b) => (a['min_qty'] as int)
                              .compareTo(b['min_qty'] as int));

                          final rawDesc = descCtrl.text.trim();
                          final finalDescription = rawDesc.isNotEmpty
                              ? rawDesc
                              : '$name en presentación de $unit. Insumo seleccionado para abastecimiento de restaurantes.';

                          final Map<String, dynamic> payload = {
                            'name': name,
                            'description': finalDescription,
                            'price': price,
                            'unit': unit,
                            'category': selectedCategory,
                            'stock_quantity': parsedStock,
                            'bulk_tiers': parsedTiers,
                            'is_available': parsedStock == null || parsedStock > 0,
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
                                backgroundColor: AppColors.tealMint,
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

  Widget _buildProductCard(Map<String, dynamic> item) {
    final String? imgUrl = item['image_url'] ?? item['image'];
    final String name = item['name']?.toString() ?? 'Insumo';
    final String unit = item['unit']?.toString() ?? '';
    final String category = item['category']?.toString() ?? _supplierCategory;
    final double price = (item['price'] as num?)?.toDouble() ?? 0.0;
    final bool isAvailable = item['is_available'] ?? true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable ? const Color(0xFFE2E8F0) : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDark.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Imagen superior + Badge de estado
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(15)),
                  child: (imgUrl != null && imgUrl.isNotEmpty)
                      ? ColorFiltered(
                          colorFilter: isAvailable
                              ? const ColorFilter.mode(
                                  Colors.transparent, BlendMode.multiply)
                              : const ColorFilter.mode(
                                  Colors.grey, BlendMode.saturation),
                          child: Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildEmptyImage(),
                          ),
                        )
                      : _buildEmptyImage(),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: isAvailable
                          ? AppColors.navyDark.withOpacity(0.85)
                          : Colors.grey.shade700,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isAvailable ? 'Activo en tienda' : 'Pausado',
                      style: TextStyle(
                        color: isAvailable ? AppColors.tealMint : Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.white.withOpacity(0.92),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Editar insumo',
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.navyDark),
                      onPressed: () => _openProductDialog(productToEdit: item),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Detalles inferiores
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                    color: AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.navyDark,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Presentación: $unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.subtitleGrey,
                    ),
                  ),
                if ((item['description'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item['description'].toString().trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.subtitleGrey,
                    ),
                  ),
                ],
                  if (item['stock_quantity'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Stock disponible: ${item['stock_quantity']} unid.',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: (item['stock_quantity'] as int) <= 5
                          ? Colors.orange.shade800
                          : const Color(0xFF0F766E),
                    ),
                  ),
                ],
                if (((item['bulk_tiers'] as List<dynamic>?) ?? []).isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'Mayoreo desde ${(item['bulk_tiers'] as List).first['min_qty']} unid.',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
                ],
                const Divider(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Precio catálogo',
                          style: TextStyle(
                              fontSize: 10.5, color: AppColors.subtitleGrey),
                        ),
                        Text(
                          '\$${price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Switch(
                          value: isAvailable,
                          activeColor: AppColors.tealMint,
                          onChanged: (val) => _toggleAvailability(item, val),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.navyDark,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () =>
                              _openProductDialog(productToEdit: item),
                          child: const Text(
                            'Editar',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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

  Widget _buildEmptyImage() {
    return Container(
      color: const Color(0xFFF1F5F9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 44, color: AppColors.primaryBlue.withOpacity(0.55)),
          const SizedBox(height: 6),
          const Text(
            'Sin fotografía',
            style: TextStyle(fontSize: 11.5, color: AppColors.subtitleGrey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = {
      'Todos',
      ..._products
          .map((p) => (p['category'] ?? '').toString().trim())
          .where((c) => c.isNotEmpty)
    }.toList();

    final filteredProducts = _products.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final cat = (p['category'] ?? '').toString();
      final matchesSearch =
          _searchQuery.isEmpty || name.contains(_searchQuery);
      final matchesCat =
          _selectedCategory == 'Todos' || cat == _selectedCategory;
      return matchesSearch && matchesCat;
    }).toList();

    final activeCount =
        _products.where((p) => (p['is_available'] ?? true) == true).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF001A2C),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.tealMint.withOpacity(0.16),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2_rounded,
                  color: AppColors.tealMint, size: 19),
            ),
            const SizedBox(width: 10),
            const Text(
              'Mi Catálogo de Insumos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.tealMint,
                foregroundColor: const Color(0xFF001A2C),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => _openProductDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Nuevo Insumo',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar catálogo',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadSupplierInfoAndProducts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  children: [
                    // Barra superior de resumen, búsqueda y filtros
                    Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 700;
                              final statsRow = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildStatBadge(
                                    'Total Insumos',
                                    '${_products.length}',
                                    AppColors.navyDark,
                                  ),
                                  const SizedBox(width: 10),
                                  _buildStatBadge(
                                    'Activos',
                                    '$activeCount',
                                    const Color(0xFF0F766E),
                                  ),
                                ],
                              );

                              final searchField = TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText:
                                      'Buscar producto en tu catálogo...',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon:
                                              const Icon(Icons.clear, size: 18),
                                          onPressed: () => _searchCtrl.clear(),
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: const Color(0xFFF1F5F9),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                ),
                              );

                              if (isWide) {
                                return Row(
                                  children: [
                                    statsRow,
                                    const SizedBox(width: 20),
                                    Expanded(child: searchField),
                                  ],
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  statsRow,
                                  const SizedBox(height: 12),
                                  searchField,
                                ],
                              );
                            },
                          ),
                          if (categories.length > 2) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: categories.map((cat) {
                                    final selected = _selectedCategory == cat;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(cat),
                                        selected: selected,
                                        selectedColor: AppColors.navyDark,
                                        labelStyle: TextStyle(
                                          fontSize: 12,
                                          fontWeight: selected
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: selected
                                              ? Colors.white
                                              : AppColors.navyDark,
                                        ),
                                        onSelected: (_) {
                                          setState(
                                              () => _selectedCategory = cat);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Grilla responsive de insumos
                    Expanded(
                      child: filteredProducts.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.inventory_2_outlined,
                                      size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text(
                                    _products.isEmpty
                                        ? 'Aún no tienes productos en tu catálogo'
                                        : 'No hay insumos que coincidan con tu búsqueda',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        color: AppColors.subtitleGrey),
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.navyDark),
                                    onPressed: () => _openProductDialog(),
                                    icon: const Icon(Icons.add,
                                        color: AppColors.tealMint),
                                    label: const Text(
                                        'Publicar nuevo producto',
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                int crossAxisCount = 1;
                                double aspectRatio = 1.15;

                                if (constraints.maxWidth >= 1000) {
                                  crossAxisCount = 4;
                                  aspectRatio = 0.78;
                                } else if (constraints.maxWidth >= 720) {
                                  crossAxisCount = 3;
                                  aspectRatio = 0.80;
                                } else if (constraints.maxWidth >= 480) {
                                  crossAxisCount = 2;
                                  aspectRatio = 0.82;
                                }

                                return GridView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 28),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    crossAxisSpacing: 16,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: aspectRatio,
                                  ),
                                  itemCount: filteredProducts.length,
                                  itemBuilder: (ctx, i) =>
                                      _buildProductCard(filteredProducts[i]),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatBadge(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.navyDark,
            ),
          ),
        ],
      ),
    );
  }
}