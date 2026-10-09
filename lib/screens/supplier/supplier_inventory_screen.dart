import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../config/session_manager.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';

class SupplierInventoryScreen extends StatefulWidget {
  const SupplierInventoryScreen({super.key});

  @override
  State<SupplierInventoryScreen> createState() =>
      _SupplierInventoryScreenState();
}

class _SupplierInventoryScreenState extends State<SupplierInventoryScreen> {
  late Future<List<Map<String, dynamic>>> _productsFuture;
  List<Map<String, dynamic>> _catalogList = [];
  final ImagePicker _picker = ImagePicker();

  String get _currentUserId =>
      supabase.auth.currentUser?.id ?? SessionManager.supplierId;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  void _loadCatalog() {
    setState(() {
      _productsFuture = _fetchCatalog();
    });
  }

  Future<List<Map<String, dynamic>>> _fetchCatalog() async {
    final userId = _currentUserId;

    String? suppDetailId;
    try {
      final detail = await supabase
          .from('supplier_details')
          .select('id')
          .eq('profile_id', userId)
          .maybeSingle();
      if (detail != null && detail['id'] != null) {
        suppDetailId = detail['id'].toString();
      }
    } catch (_) {}

    final query = supabase.from('products').select('*');
    final response = suppDetailId != null
        ? await query
            .or('supplier_id.eq.$userId,supplier_id.eq.$suppDetailId')
            .order('name', ascending: true)
        : await query.eq('supplier_id', userId).order('name', ascending: true);

    final list = List<Map<String, dynamic>>.from(response);
    _catalogList = list;
    return list;
  }

  // --- SUBIR IMAGEN A SUPABASE STORAGE ---
  Future<String?> _uploadImage(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      final fileExt = file.name.split('.').last.toLowerCase();
      final validExt = (fileExt == 'png' || fileExt == 'webp') ? fileExt : 'jpg';
      final fileName =
          '$_currentUserId/${DateTime.now().millisecondsSinceEpoch}.$validExt';

      await supabase.storage.from('product-images').uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/$validExt',
              upsert: true,
            ),
          );

      final publicUrl =
          supabase.storage.from('product-images').getPublicUrl(fileName);
      return publicUrl;
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir imagen: $msg'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return null;
    }
  }

  // --- TOGGLE SWITCH DISPONIBILIDAD ---
  Future<void> _toggleAvailability(
      Map<String, dynamic> product, bool newValue) async {
    final productId = product['id'];

    setState(() {
      product['is_available'] = newValue;
    });

    try {
      await supabase
          .from('products')
          .update({'is_available': newValue})
          .eq('id', productId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue
              ? '${product['name']} marcado como Disponible'
              : '${product['name']} marcado como No Disponible'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        product['is_available'] = !newValue;
      });
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar disponibilidad: $msg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- MODAL DE AGREGAR PRODUCTO CON IMAGEN ---
  Future<void> _showAddProductDialog() async {
    final nameCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: 'Lácteos y Quesos');
    final unitCtrl = TextEditingController(text: '1 litro');
    final priceCtrl = TextEditingController();

    Uint8List? pickedImageBytes;
    XFile? pickedFile;
    bool isUploading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Nuevo Insumo al Catálogo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selector de Imagen
                GestureDetector(
                  onTap: () async {
                    final img = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setDialogState(() {
                        pickedFile = img;
                        pickedImageBytes = bytes;
                      });
                    }
                  },
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryBlue.withOpacity(0.3),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: pickedImageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              pickedImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.add_a_photo_outlined,
                                  size: 36, color: AppColors.primaryBlue),
                              SizedBox(height: 6),
                              Text(
                                'Toca para subir foto del insumo',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primaryBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del insumo (ej. Queso Morolique)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Presentación (ej. Libra, Caja, Litro)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio por unidad (\$ USD)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: isUploading
                  ? null
                  : () async {
                      final rawPrice = priceCtrl.text
                          .replaceAll(r'$', '')
                          .replaceAll(',', '.')
                          .trim();
                      final price = double.tryParse(rawPrice) ?? 0.0;
                      final name = nameCtrl.text.trim();

                      if (name.isNotEmpty && price > 0) {
                        setDialogState(() => isUploading = true);

                        String? uploadedImageUrl;
                        if (pickedFile != null) {
                          uploadedImageUrl = await _uploadImage(pickedFile!);
                        }

                        try {
                          await supabase.from('products').insert({
                            'supplier_id': _currentUserId,
                            'name': name,
                            'category': catCtrl.text.trim().isEmpty
                                ? 'General'
                                : catCtrl.text.trim(),
                            'unit': unitCtrl.text.trim().isEmpty
                                ? 'unidad'
                                : unitCtrl.text.trim(),
                            'price': price,
                            'image_url': uploadedImageUrl,
                            'is_available': true,
                          });

                          if (mounted) {
                            Navigator.pop(context);
                            _loadCatalog();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Producto agregado con éxito!'),
                                backgroundColor: AppColors.tealMint,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUploading = false);
                          if (mounted) {
                            final msg = ErrorHandler.parse(e);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Guardar',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- MODAL DE EDITAR PRODUCTO CON FOTO ---
  Future<void> _showEditProductDialog(Map<String, dynamic> product) async {
    final nameCtrl = TextEditingController(text: product['name'] ?? '');
    final catCtrl =
        TextEditingController(text: product['category'] ?? 'General');
    final unitCtrl = TextEditingController(text: product['unit'] ?? 'unidad');
    final priceCtrl = TextEditingController(
      text: (product['price'] as num?)?.toStringAsFixed(2) ?? '',
    );

    String? currentImageUrl = product['image_url'];
    Uint8List? newImageBytes;
    XFile? newPickedFile;
    bool isUpdating = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Editar ${product['name']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Selector de Imagen (con foto existente o nueva)
                GestureDetector(
                  onTap: () async {
                    final img = await _picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (img != null) {
                      final bytes = await img.readAsBytes();
                      setDialogState(() {
                        newPickedFile = img;
                        newImageBytes = bytes;
                      });
                    }
                  },
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primaryBlue.withOpacity(0.3),
                      ),
                    ),
                    child: newImageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              newImageBytes!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : (currentImageUrl != null &&
                                currentImageUrl!.isNotEmpty)
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      currentImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.broken_image,
                                              size: 40, color: Colors.grey),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.65),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Cambiar foto',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      size: 38, color: AppColors.primaryBlue),
                                  SizedBox(height: 6),
                                  Text(
                                    'Subir foto desde este dispositivo',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                  ),
                ),
                const SizedBox(height: 14),

                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del insumo',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: catCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Presentación / Unidad',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio por unidad (\$ USD)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUpdating ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
              ),
              onPressed: isUpdating
                  ? null
                  : () async {
                      final rawPrice = priceCtrl.text
                          .replaceAll(r'$', '')
                          .replaceAll(',', '.')
                          .trim();
                      final price = double.tryParse(rawPrice) ?? 0.0;
                      final name = nameCtrl.text.trim();

                      if (name.isNotEmpty && price > 0) {
                        setDialogState(() => isUpdating = true);

                        String? finalImageUrl = currentImageUrl;
                        if (newPickedFile != null) {
                          final uploaded = await _uploadImage(newPickedFile!);
                          if (uploaded != null) {
                            finalImageUrl = uploaded;
                          }
                        }

                        try {
                          await supabase.from('products').update({
                            'name': name,
                            'category': catCtrl.text.trim(),
                            'unit': unitCtrl.text.trim(),
                            'price': price,
                            'image_url': finalImageUrl,
                          }).eq('id', product['id']);

                          if (mounted) {
                            Navigator.pop(context);
                            _loadCatalog();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('¡Insumo actualizado con éxito!'),
                                backgroundColor: AppColors.tealMint,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isUpdating = false);
                          if (mounted) {
                            final msg = ErrorHandler.parse(e);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(msg),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
              child: isUpdating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Actualizar',
                      style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // --- ELIMINAR PRODUCTO ---
  Future<void> _deleteProduct(String productId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar insumo?'),
        content: const Text(
          'Esta acción eliminará el producto de tu catálogo para los restaurantes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('products').delete().eq('id', productId);
      _loadCatalog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado del catálogo')),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Catálogo de Insumos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Agregar producto',
            onPressed: _showAddProductDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCatalog,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              _catalogList.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && _catalogList.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text('Error: ${snapshot.error}',
                    style: const TextStyle(color: Colors.red)),
              ),
            );
          }

          final products = _catalogList;
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'No tienes insumos en tu catálogo.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Presiona + para agregar tu primer producto.',
                    style: TextStyle(
                      color: AppColors.subtitleGrey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                    ),
                    onPressed: _showAddProductDialog,
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Agregar Insumo',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              final isAvailable = product['is_available'] ?? true;
              final category = product['category'] ?? 'General';
              final imageUrl = product['image_url'] as String?;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                elevation: 1.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showEditProductDialog(product),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        // Imagen real o Avatar genérico
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: (imageUrl != null && imageUrl.isNotEmpty)
                              ? Image.network(
                                  imageUrl,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _buildFallbackAvatar(),
                                )
                              : _buildFallbackAvatar(),
                        ),
                        const SizedBox(width: 12),

                        // Datos del producto
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product['name'] ?? '',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.navyDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$category • ${product['unit']} • \$${(product['price'] as num?)?.toStringAsFixed(2) ?? "0.00"}',
                                style: const TextStyle(
                                  color: AppColors.subtitleGrey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Switch de Disponibilidad
                        Switch(
                          value: isAvailable,
                          activeColor: AppColors.tealMint,
                          onChanged: (val) =>
                              _toggleAvailability(product, val),
                        ),

                        // Botón de Editar
                        IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              size: 20, color: AppColors.primaryBlue),
                          tooltip: 'Editar insumo',
                          onPressed: () => _showEditProductDialog(product),
                        ),

                        // Botón de Eliminar
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              size: 20, color: Colors.redAccent),
                          tooltip: 'Eliminar insumo',
                          onPressed: () =>
                              _deleteProduct(product['id'].toString()),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFallbackAvatar() {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.inventory,
          color: AppColors.primaryBlue, size: 26),
    );
  }
}