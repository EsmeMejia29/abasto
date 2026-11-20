import 'dart:math' as math;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import '../services/notification_service.dart';
import 'supplier_detail_screen.dart';
import '../widgets/business_info_sheet.dart';
import '../widgets/interactive_tutorial_modal.dart';

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
  String _selectedZone = 'Todas las zonas';
  bool _sortByNearest = false;
  bool _isLocating = false;
  double? _userLat;
  double? _userLng;
  final TextEditingController _searchCtrl = TextEditingController();

  String _restaurantName = 'Mi Restaurante';
  String _restaurantLocation = '';

  final List<String> _zones = const [
    'Todas las zonas',
    'Santa Tecla',
    'Antiguo Cuscatlán',
    'San Salvador',
    'Soyapango',
    'Lourdes Colón',
    'La Libertad',
    'Santa Ana',
    'San Miguel',
  ];

  // Colonias, residenciales y centros de referencia por municipio en El Salvador
  static const Map<String, List<String>> _zoneKeywords = {
    'Santa Tecla': [
      'santa tecla',
      'quezaltepec',
      'merliot',
      'ciudad merliot',
      'las delicias',
      'alpes suizos',
      'pinares de suiza',
      'utila',
      'san jose del pino',
      'el cafetalon',
      'las palmeras',
      'bosques de santa teresa',
      'santa teresa',
      'jardines del volcan',
      'nuevo cuscatlan',
      'via del mar',
      'el boqueron',
    ],
    'Antiguo Cuscatlán': [
      'antiguo cuscatlan',
      'santa elena',
      'la sultana',
      'madreselva',
      'plan de la laguna',
      'lomas de san francisco',
      'jardines de guadalupe',
      'la cima',
      'arcadia',
      'multiplaza',
      'la gran via',
    ],
    'San Salvador': [
      'san salvador',
      'escalon',
      'san benito',
      'zona rosa',
      'maquilishuat',
      'miramonte',
      'flor blanca',
      'san jacinto',
      'altamira',
      'colonia medica',
      'la rabida',
      'satelite',
      'zacamil',
      'metrocentro',
      'salvador del mundo',
      'alameda roosevelt',
      'miralvalle',
      'monserrat',
      'luz',
      'costa rica',
    ],
    'Soyapango': [
      'soyapango',
      'prados de venecia',
      'bosques del rio',
      'sierra morena',
      'montes de san bartolo',
      'ilopango',
      'san bartolo',
      'ciudad credisa',
      'plaza mundo',
    ],
    'Santa Ana': [
      'santa ana',
      'el palmar',
      'ivU',
      'colonia el trebol',
      'las victorias',
      'chalchuapa',
    ],
    'San Miguel': [
      'san miguel',
      'ciudad pacifica',
      'panamericana',
      'colonia belen',
      'chaparrastique',
      'metrocentro san miguel',
    ],
  };

  // Coordenadas centrales [lat, lng, radioKm] por si el comercio puso pin en mapa
  static const Map<String, List<double>> _zoneCenters = {
    'Santa Tecla': [13.6769, -89.2797, 6.5],
    'Antiguo Cuscatlán': [13.6649, -89.2532, 4.5],
    'San Salvador': [13.6929, -89.2182, 7.5],
    'Soyapango': [13.7102, -89.1399, 6.0],
    'Santa Ana': [13.9942, -89.5597, 8.0],
    'San Miguel': [13.4834, -88.1833, 8.0],
  };

  String _normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
  }

  bool _supplierMatchesZone(Supplier supplier, String selectedZone) {
    if (selectedZone == 'Todas las zonas') return true;

    // Combinamos ubicación sede + zonas de cobertura de entrega del distribuidor
    final combinedLocation =
        _normalizeText('${supplier.location} ${supplier.deliveryCoverage}');
    final keywords = _zoneKeywords[selectedZone] ?? [_normalizeText(selectedZone)];

    // 1. Coincidencia por municipio, colonia o zona de cobertura de reparto
    for (final kw in keywords) {
      if (combinedLocation.contains(_normalizeText(kw))) {
        return true;
      }
    }

    // 2. Respaldo por coordenadas GPS del pin en el mapa
    final center = _zoneCenters[selectedZone];
    if (center != null &&
        supplier.latitude != null &&
        supplier.longitude != null) {
      const double r = 6371.0;
      final dLat = (supplier.latitude! - center[0]) * math.pi / 180.0;
      final dLon = (supplier.longitude! - center[1]) * math.pi / 180.0;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
          math.cos(center[0] * math.pi / 180.0) *
              math.cos(supplier.latitude! * math.pi / 180.0) *
              math.sin(dLon / 2) *
              math.sin(dLon / 2);
      final distKm = r * (2 * math.atan2(math.sqrt(a), math.sqrt(1 - a)));
      if (distKm <= center[2]) {
        return true;
      }
    }

    return false;
  }

  final _categories  = const [
    {'label': 'Todos', 'icon': Icons.grid_view_rounded},
    {'label': 'Verduras', 'icon': Icons.eco_outlined},
    {'label': 'Lácteos', 'icon': Icons.water_drop_outlined},
    {'label': 'Carnes', 'icon': Icons.set_meal_outlined},
    {'label': 'Abarrotes', 'icon': Icons.inventory_2_outlined},
    {'label': 'Mariscos', 'icon': Icons.phishing_outlined},
    {'label': 'Desechables', 'icon': Icons.takeout_dining_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadRestaurantProfile();
    _suppliersFuture = _fetchSuppliers();
    NotificationService.initializeAndRegisterToken();
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

      final restDet = await supabase
          .from('restaurant_details')
          .select('delivery_latitude, delivery_longitude')
          .eq('profile_id', userId)
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
          }
          if (restDet != null) {
            _userLat ??= double.tryParse(
                restDet['delivery_latitude']?.toString() ?? '');
            _userLng ??= double.tryParse(
                restDet['delivery_longitude']?.toString() ?? '');
          }
        });
      }
    } catch (_) {}
  }

  double? _distanceKmTo(Supplier s) {
    if (_userLat == null ||
        _userLng == null ||
        s.latitude == null ||
        s.longitude == null) {
      return null;
    }
    const double r = 6371.0;
    final dLat = (s.latitude! - _userLat!) * math.pi / 180.0;
    final dLon = (s.longitude! - _userLng!) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_userLat! * math.pi / 180.0) *
            math.cos(s.latitude! * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  Future<void> _toggleNearestSort() async {
    if (_sortByNearest) {
      setState(() => _sortByNearest = false);
      _applyFilter();
      return;
    }

    if (_userLat != null && _userLng != null) {
      setState(() => _sortByNearest = true);
      _applyFilter();
      return;
    }

    setState(() => _isLocating = true);
    try {
      final pos = await html.window.navigator.geolocation.getCurrentPosition();
      final lat = pos.coords?.latitude?.toDouble();
      final lng = pos.coords?.longitude?.toDouble();
      if (lat != null && lng != null && mounted) {
        setState(() {
          _userLat = lat;
          _userLng = lng;
          _sortByNearest = true;
          _isLocating = false;
        });
        _applyFilter();
        return;
      }
    } catch (_) {
      // Fallback: usar zona del restaurante como referencia si el navegador bloquea GPS
    }

    if (mounted) {
      setState(() {
        _isLocating = false;
        _sortByNearest = true;
      });
      _applyFilter();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ordenando por cercanía y coincidencia con tu zona registrada.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<List<Supplier>> _fetchSuppliers() async {
    final detailsRes = await supabase.from('supplier_details').select('*');

    List<dynamic> profilesRes = [];
    try {
      profilesRes = await supabase
          .from('profiles')
          .select(
              'id, business_name, address, location, phone, avatar_url, rating, reviews_count, is_verified')
          .eq('role', 'supplier');
    } catch (_) {
      profilesRes = await supabase
          .from('profiles')
          .select('id, business_name, address, phone')
          .eq('role', 'supplier');
    }

    final profilesMap = {
      for (var p in profilesRes)
        p['id'].toString(): p as Map<String, dynamic>
    };

    final list = (detailsRes as List<dynamic>).map((item) {
      final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
      final profId = map['profile_id']?.toString() ?? '';

      if (profilesMap.containsKey(profId)) {
        final prof = profilesMap[profId]!;
        map['business_name'] = prof['business_name'];
        map['avatar_url'] = prof['avatar_url'];
        final addr = (prof['address'] ?? '').toString().trim();
        final loc = (prof['location'] ?? '').toString().trim();
        if (addr.isNotEmpty) map['address'] = addr;
        if (loc.isNotEmpty) {
          map['location'] = loc;
          if (addr.isNotEmpty &&
              !addr.toLowerCase().contains(loc.toLowerCase())) {
            map['address'] = '$addr, $loc';
          }
        }
        if (prof['rating'] != null) {
          map['rating'] = prof['rating'];
        }
        if (prof['reviews_count'] != null) {
          map['reviews_count'] = prof['reviews_count'];
        }
        if (prof['is_verified'] != null) {
          map['is_verified'] = prof['is_verified'];
        }
      }
      return Supplier.fromMap(map);
    }).toList();

    _allSuppliers = list;
    _filteredSuppliers = list;
    return list;
  }

  void _applyFilter() {
    final query = _searchCtrl.text.toLowerCase().trim();
    final restZone = _restaurantLocation.toLowerCase();

    final filtered = _allSuppliers.where((supplier) {
      final matchesQuery = supplier.name.toLowerCase().contains(query) ||
          supplier.category.toLowerCase().contains(query) ||
          supplier.location.toLowerCase().contains(query) ||
          supplier.deliveryCoverage.toLowerCase().contains(query);

      final matchesCategory = _selectedCategory == 'Todos' ||
          supplier.category
              .toLowerCase()
              .contains(_selectedCategory.toLowerCase());

      final matchesZone = _supplierMatchesZone(supplier, _selectedZone);

      return matchesQuery && matchesCategory && matchesZone;
    }).toList();

    if (_sortByNearest) {
      filtered.sort((a, b) {
        final distA = _distanceKmTo(a);
        final distB = _distanceKmTo(b);
        if (distA != null && distB != null) {
          return distA.compareTo(distB);
        }
        if (distA != null) return -1;
        if (distB != null) return 1;

        final restMainZone = restZone.split(',').first.trim();
        final aSameZone = restMainZone.isNotEmpty &&
            '${a.location} ${a.deliveryCoverage}'
                .toLowerCase()
                .contains(restMainZone);
        final bSameZone = restMainZone.isNotEmpty &&
            '${b.location} ${b.deliveryCoverage}'
                .toLowerCase()
                .contains(restMainZone);
        if (aSameZone && !bSameZone) return -1;
        if (!aSameZone && bSameZone) return 1;
        return 0;
      });
    }

    setState(() {
      _filteredSuppliers = filtered;
    });
  }

  Widget _buildSupplierAvatar(Supplier supplier) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withOpacity(0.14),
            AppColors.tealMint.withOpacity(0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppColors.primaryBlue.withOpacity(0.18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: (supplier.avatarUrl != null && supplier.avatarUrl!.isNotEmpty)
          ? Image.network(
              supplier.avatarUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildAvatarInitial(supplier),
            )
          : _buildAvatarInitial(supplier),
    );
  }

  Widget _buildAvatarInitial(Supplier supplier) {
    return Center(
      child: Text(
        supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : 'D',
        style: const TextStyle(
          color: AppColors.navyDark,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
      ),
    );
  }

  Widget _buildHeroHeader(bool isDesktop) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF001A2C), Color(0xFF1B3452)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        isDesktop ? 28 : 18,
        12,
        isDesktop ? 28 : 18,
        20,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra superior integrada
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.tealMint.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.storefront_rounded,
                            color: AppColors.tealMint, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Abasto',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: AppColors.tealMint,
                          foregroundColor: const Color(0xFF001A2C),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: _showPriceComparatorModal,
                        icon: const Icon(Icons.compare_arrows_rounded, size: 17),
                        label: const Text(
                          'Comparar Precios',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.10),
                          foregroundColor: AppColors.tealMint,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () => InteractiveTutorialModal.show(
                            context,
                            isSupplier: false),
                        icon: const Icon(Icons.help_outline_rounded, size: 17),
                        label: const Text(
                          'Tutorial',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Actualizar catálogo',
                        icon: const Icon(Icons.refresh_rounded,
                            color: Colors.white70),
                        onPressed: () {
                          _loadRestaurantProfile();
                          setState(() {
                            _suppliersFuture = _fetchSuppliers();
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Datos del restaurante
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _restaurantName,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_restaurantLocation.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 14, color: AppColors.tealMint),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _restaurantLocation,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isDesktop)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_outlined,
                              color: AppColors.tealMint, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${_allSuppliers.length} distribuidor(es) activos',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Barra de búsqueda completamente dentro del bloque navy
              Container(
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => _applyFilter(),
                  decoration: InputDecoration(
                    hintText:
                        'Buscar distribuidor, verduras, lácteos, empaques...',
                    hintStyle: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.subtitleGrey,
                    ),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: AppColors.primaryBlue),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _applyFilter();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSupplierCard(Supplier supplier) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SupplierDetailScreen(supplier: supplier),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSupplierAvatar(supplier),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        supplier.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.navyDark,
                                        ),
                                      ),
                                    ),
                                    if (supplier.isVerified) ...[
                                      const SizedBox(width: 5),
                                      const Icon(
                                        Icons.verified_rounded,
                                        size: 17,
                                        color: AppColors.tealMint,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  BusinessInfoSheet.show(
                                    context,
                                    businessId: supplier.id,
                                    defaultName: supplier.name,
                                    role: 'supplier',
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: const Color(0xFFFDE68A)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star_rounded,
                                          size: 16, color: Color(0xFFF59E0B)),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${supplier.rating.toStringAsFixed(1)} (${supplier.reviewsCount})',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF92400E),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primaryBlue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              supplier.category,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 15, color: Color(0xFF0F766E)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                () {
                                  final km = _distanceKmTo(supplier);
                                  final kmText = km != null
                                      ? ' (${km.toStringAsFixed(1)} km)'
                                      : '';
                                  final covText =
                                      supplier.deliveryCoverage.isNotEmpty
                                          ? ' • Reparte: ${supplier.deliveryCoverage}'
                                          : '';
                                  return '${supplier.location}$kmText$covText';
                                }(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: const [
                          Text(
                            'Ver catálogo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          SizedBox(width: 3),
                          Icon(Icons.arrow_forward_rounded,
                              size: 15, color: AppColors.primaryBlue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _showPriceComparatorModal() {
    final compSearchCtrl = TextEditingController();
    List<dynamic> results = [];
    bool isSearching = false;
    bool hasSearched = false;

    Future<void> runSearch(String query, StateSetter setModalState) async {
      final clean = query.trim();
      if (clean.length < 2) return;
      setModalState(() {
        isSearching = true;
        hasSearched = true;
      });
      try {
        final res = await supabase
            .from('products')
            .select('id, name, price, unit, category, bulk_tiers, supplier_id')
            .eq('is_available', true)
            .ilike('name', '%$clean%')
            .order('price', ascending: true)
            .limit(30);

        final suppMap = {for (final s in _allSuppliers) s.id: s};
        final List<dynamic> enriched = [];

        for (final row in (res as List<dynamic>)) {
          final sId = row['supplier_id']?.toString() ?? '';
          final supp = suppMap[sId];
          if (supp == null) continue;
          final basePrice = (row['price'] as num?)?.toDouble() ?? 0.0;
          final finalPrice = double.parse((basePrice * 1.03).toStringAsFixed(2));
          enriched.add({
            'product_id': row['id'],
            'product_name': row['name'] ?? 'Insumo',
            'unit': row['unit'] ?? 'unidad',
            'final_price': finalPrice,
            'bulk_tiers': row['bulk_tiers'] ?? [],
            'supplier': supp,
          });
        }

        enriched.sort((a, b) =>
            (a['final_price'] as double).compareTo(b['final_price'] as double));

        setModalState(() {
          results = enriched;
          isSearching = false;
        });
      } catch (_) {
        setModalState(() => isSearching = false);
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.tealMint.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.compare_arrows_rounded,
                              color: Color(0xFF0F766E), size: 22),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Comparador de Precios B2B',
                          style: TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.navyDark,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Busca un insumo y compara al instante qué distribuidores lo tienen más económico.',
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.subtitleGrey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: compSearchCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (val) => runSearch(val, setModalState),
                  onChanged: (val) {
                    if (val.trim().length >= 3) {
                      runSearch(val, setModalState);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Ej. Tomate, Queso duro, Harina, Aceite...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded,
                          color: AppColors.primaryBlue),
                      onPressed: () =>
                          runSearch(compSearchCtrl.text, setModalState),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : !hasSearched
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.price_check_rounded,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Escribe el nombre del insumo para comparar precios.',
                                    style: TextStyle(
                                        color: AppColors.subtitleGrey,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : results.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No se encontraron insumos activos con ese nombre.',
                                    style: TextStyle(
                                        color: AppColors.subtitleGrey),
                                  ),
                                )
                              : ListView.separated(
                                  controller: scrollCtrl,
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, idx) {
                                    final item = results[idx];
                                    final Supplier supp = item['supplier'];
                                    final double finalPrice =
                                        item['final_price'];
                                    final tiers =
                                        (item['bulk_tiers'] as List<dynamic>?) ??
                                            [];
                                    final isBest = idx == 0;

                                    return Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: isBest
                                            ? const Color(0xFFF0FDF4)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isBest
                                              ? const Color(0xFF86EFAC)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (isBest)
                                                  Container(
                                                    margin:
                                                        const EdgeInsets.only(
                                                            bottom: 4),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFF16A34A),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                    ),
                                                    child: const Text(
                                                      'MEJOR PRECIO',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 9.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                Text(
                                                  '${item['product_name']} (${item['unit']})',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    color: AppColors.navyDark,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        supp.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: AppColors
                                                              .primaryBlue,
                                                        ),
                                                      ),
                                                    ),
                                                    if (supp.isVerified) ...[
                                                      const SizedBox(width: 4),
                                                      const Icon(Icons.verified,
                                                          size: 14,
                                                          color: AppColors
                                                              .tealMint),
                                                    ],
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '★ ${supp.rating.toStringAsFixed(1)}',
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            Color(0xFFB45309),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                if (tiers.isNotEmpty) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    'Mayoreo desde ${tiers.first['min_qty']} unid. a \$${(((tiers.first['price'] as num).toDouble()) * 1.03).toStringAsFixed(2)} c/u',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF0F766E),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '\$${finalPrice.toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.navyDark,
                                                ),
                                              ),
                                              const Text(
                                                'Tarifa incl.',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color:
                                                        AppColors.subtitleGrey),
                                              ),
                                              const SizedBox(height: 6),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      const Color(0xFF001A2C),
                                                  foregroundColor: Colors.white,
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 6),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                ),
                                                onPressed: () {
                                                  Navigator.pop(ctx);
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          SupplierDetailScreen(
                                                        supplier: supp,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: const Text(
                                                  'Ir a tienda',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.tealMint,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 850;

        return Scaffold(
          backgroundColor: const Color(0xFFF1F5F9),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeroHeader(isDesktop),

                // Carrusel de categorías con iconos
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 28 : 16),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final String label = cat['label'] as String;
                          final IconData icon = cat['icon'] as IconData;
                          final isSelected = _selectedCategory == label;

                          return ChoiceChip(
                            avatar: Icon(
                              icon,
                              size: 16,
                              color: isSelected
                                  ? AppColors.tealMint
                                  : AppColors.primaryBlue,
                            ),
                            label: Text(label),
                            selected: isSelected,
                            showCheckmark: false,
                            backgroundColor: Colors.white,
                            selectedColor: AppColors.navyDark,
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.navyDark
                                  : const Color(0xFFCBD5E1),
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppColors.navyDark,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 12.5,
                            ),
                            onSelected: (val) {
                              if (val) {
                                setState(() => _selectedCategory = label);
                                _applyFilter();
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // Barra de Filtro por Zona y Proximidad GPS ("Más cerca de mí")
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      isDesktop ? 28 : 16,
                      4,
                      isDesktop ? 28 : 16,
                      6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedZone,
                                isExpanded: true,
                                icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.navyDark,
                                ),
                                items: _zones
                                    .map((z) => DropdownMenuItem(
                                          value: z,
                                          child: Row(
                                            children: [
                                              const Icon(
                                                  Icons.place_outlined,
                                                  size: 15,
                                                  color: AppColors.primaryBlue),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  z,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedZone = val);
                                    _applyFilter();
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 38,
                          child: FilterChip(
                            selected: _sortByNearest,
                            showCheckmark: false,
                            avatar: _isLocating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Icon(
                                    Icons.near_me_rounded,
                                    size: 15,
                                    color: _sortByNearest
                                        ? AppColors.tealMint
                                        : AppColors.primaryBlue,
                                  ),
                            label: Text(
                              _sortByNearest
                                  ? 'Más cercanos ✓'
                                  : 'Más cerca de mí',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _sortByNearest
                                    ? Colors.white
                                    : AppColors.navyDark,
                              ),
                            ),
                            backgroundColor: Colors.white,
                            selectedColor: AppColors.navyDark,
                            side: BorderSide(
                              color: _sortByNearest
                                  ? AppColors.navyDark
                                  : const Color(0xFFCBD5E1),
                            ),
                            onSelected: (_) => _toggleNearestSort(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Listado / Grid de distribuidores
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
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Icon(Icons.search_off_rounded,
                                  size: 40, color: Colors.grey.shade400),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No se encontraron distribuidores con ese filtro.',
                              style: TextStyle(
                                color: AppColors.subtitleGrey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: isDesktop
                            ? GridView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                    28, 10, 28, 24),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: 152,
                                ),
                                itemCount: _filteredSuppliers.length,
                                itemBuilder: (context, index) =>
                                    _buildSupplierCard(
                                        _filteredSuppliers[index]),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 20),
                                itemCount: _filteredSuppliers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) =>
                                    _buildSupplierCard(
                                        _filteredSuppliers[index]),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }
}