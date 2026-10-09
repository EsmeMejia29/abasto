import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'supplier_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Supplier>> _suppliersFuture;
  List<Supplier> _allSuppliers = [];
  List<Supplier> _filteredSuppliers = [];
  String _selectedCategory = 'Todos';
  final TextEditingController _searchCtrl = TextEditingController();

  String _restaurantName = 'Mi Restaurante';
  String _restaurantLocation = 'El Salvador';

  final List<String> _categories = [
    'Todos',
    'Verduras',
    'Lácteos',
    'Carnes',
    'Abarrotes',
    'Mariscos',
    'Desechables',
  ];

  @override
  void initState() {
    super.initState();
    _loadRestaurantProfile();
    _suppliersFuture = _fetchSuppliers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRestaurantProfile() async {
    final userId =
        supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
    try {
      final res = await supabase
          .from('profiles')
          .select('business_name, address')
          .eq('id', userId)
          .maybeSingle();

      if (res != null && mounted) {
        setState(() {
          if (res['business_name'] != null &&
              res['business_name'].toString().trim().isNotEmpty) {
            _restaurantName = res['business_name'];
          }
          if (res['address'] != null &&
              res['address'].toString().trim().isNotEmpty) {
            _restaurantLocation = res['address'];
          } else {
            _restaurantLocation = 'Cuenta Restaurante B2B';
          }
        });
      }
    } catch (_) {}
  }

  Future<List<Supplier>> _fetchSuppliers() async {
    // Especificamos explícitamente la relación foreign key para evitar la ambigüedad PGRST201
    final response = await supabase.from('supplier_details').select('''
      *,
      profiles!supplier_details_profile_id_fkey (
        business_name,
        address,
        phone
      )
    ''');

    final dataList = response as List<dynamic>;

    final list = dataList.map((item) {
      final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
      final profile = map['profiles'] as Map<String, dynamic>?;

      if (profile != null && profile['business_name'] != null) {
        map['business_name'] = profile['business_name'];
      }

      return Supplier.fromMap(map);
    }).toList();

    _allSuppliers = list;
    _filteredSuppliers = list;
    return list;
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filteredSuppliers = _allSuppliers.where((supplier) {
        final matchesQuery = supplier.name.toLowerCase().contains(query) ||
            supplier.category.toLowerCase().contains(query) ||
            supplier.location.toLowerCase().contains(query);

        final matchesCategory = _selectedCategory == 'Todos' ||
            supplier.category
                .toLowerCase()
                .contains(_selectedCategory.toLowerCase());

        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.storefront, color: AppColors.primaryBlue),
            SizedBox(width: 8),
            Text('Abasto'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadRestaurantProfile();
              setState(() {
                _suppliersFuture = _fetchSuppliers();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner superior dinámico con el perfil real del usuario
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.tealMint.withOpacity(0.12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _restaurantName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _restaurantLocation,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.subtitleGrey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tealMint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Canal B2B',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Buscador
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _applyFilter(),
              decoration: InputDecoration(
                hintText: 'Buscar distribuidor, verduras, lácteos...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Chips de categorías
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppColors.primaryBlue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : AppColors.navyDark,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() => _selectedCategory = cat);
                      _applyFilter();
                    }
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 6),

          // Lista de Distribuidores
          Expanded(
            child: FutureBuilder<List<Supplier>>(
              future: _suppliersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Error al cargar distribuidores: ${snapshot.error}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }

                if (_filteredSuppliers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        const Text(
                          'No se encontraron distribuidores.',
                          style: TextStyle(color: AppColors.subtitleGrey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: _filteredSuppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = _filteredSuppliers[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 1.5,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SupplierDetailScreen(supplier: supplier),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      supplier.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.navyDark,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.amber.shade200),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.star,
                                            size: 15, color: Colors.amber),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${supplier.rating.toStringAsFixed(1)} (${supplier.reviewsCount})',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                supplier.category,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.subtitleGrey,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.local_shipping_outlined,
                                      size: 15, color: AppColors.primaryBlue),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Ruta: ${supplier.deliveryDays}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }
}