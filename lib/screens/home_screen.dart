import 'package:flutter/material.dart';
import '../main.dart';
import '../models/supplier.dart';
import '../widgets/supplier_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Supplier>> _suppliersFuture;
  Map<String, dynamic>? _restaurantProfile;

  @override
  void initState() {
    super.initState();
    _suppliersFuture = _fetchSuppliers();
    _fetchRestaurantData();
  }

  Future<void> _fetchRestaurantData() async {
    try {
      final data = await supabase
          .from('profiles')
          .select('business_name, address')
          .eq('role', 'restaurant')
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _restaurantProfile = data;
        });
      }
    } catch (_) {}
  }

  Future<List<Supplier>> _fetchSuppliers() async {
    // 1. Obtener los detalles de todos los proveedores
    final suppliersData = await supabase
        .from('supplier_details')
        .select('*');

    final list = suppliersData as List<dynamic>;
    if (list.isEmpty) return [];

    // 2. Obtener los nombres comerciales desde profiles
    final profileIds = list.map((s) => s['profile_id'].toString()).toSet().toList();
    final profilesData = await supabase
        .from('profiles')
        .select('id, business_name')
        .filter('id', 'in', profileIds);

    final nameMap = <String, String>{};
    for (var prof in profilesData as List<dynamic>) {
      nameMap[prof['id'].toString()] = prof['business_name'] ?? 'Proveedor';
    }

    // 3. Mapear cada proveedor con su nombre
    return list.map((s) {
      final sMap = Map<String, dynamic>.from(s as Map);
      final pId = sMap['profile_id']?.toString() ?? '';
      sMap['profiles'] = {'business_name': nameMap[pId] ?? 'Distribuidor de Alimentos'};
      return Supplier.fromMap(sMap);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 12),
            Image.asset(
              'assets/images/logo.png',
              height: 32,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.storefront, color: Colors.teal, size: 28),
            ),
            const SizedBox(width: 8),
            const Text(
              'Abasto',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _suppliersFuture = _fetchSuppliers();
              });
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal.shade50,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _restaurantProfile?['business_name'] ?? 'Restaurante El Buen Sabor',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        _restaurantProfile?['address'] ?? 'Sucursal Santa Tecla • Enfoque Alimentos Frescos',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.verified, size: 16, color: Colors.white),
                  label: const Text('Línea B2B', style: TextStyle(color: Colors.white, fontSize: 11)),
                  backgroundColor: Colors.teal.shade700,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Proveedores verificados en tu zona',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Supplier>>(
              future: _suppliersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error al cargar proveedores: ${snapshot.error}'),
                  );
                }
                final suppliers = snapshot.data ?? [];
                if (suppliers.isEmpty) {
                  return const Center(child: Text('No hay proveedores disponibles.'));
                }
                return ListView.builder(
                  itemCount: suppliers.length,
                  itemBuilder: (context, index) {
                    return SupplierCard(supplier: suppliers[index]);
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