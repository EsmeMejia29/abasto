import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/crm_screen.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/supplier/supplier_catalog_view.dart';
import 'screens/supplier/supplier_crm_screen.dart';
import 'screens/supplier/supplier_incoming_orders_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const AbastoApp());
}

class AbastoApp extends StatelessWidget {
  const AbastoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Abasto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppColors.primaryBlue,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          primary: AppColors.primaryBlue,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Contenedor de navegación para Restaurante (4 pestañas, sin financiamiento)
class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    OrdersScreen(),
    CrmScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'CRM',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Contenedor de navegación para Distribuidor / Proveedor (Despachos, Catálogo, CRM y Perfil)
class SupplierNavigationHolder extends StatefulWidget {
  const SupplierNavigationHolder({super.key});

  @override
  State<SupplierNavigationHolder> createState() =>
      _SupplierNavigationHolderState();
}

class _SupplierNavigationHolderState extends State<SupplierNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    SupplierIncomingOrdersScreen(),
    SupplierCatalogView(),
    SupplierCrmScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Despachos',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Mi Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'CRM',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Mi Perfil',
          ),
        ],
      ),
    );
  }
}

/// Manejador de persistencia de sesión y enrutamiento por rol
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  Widget _targetScreen = const WelcomeScreen();

  @override
  void initState() {
    super.initState();
    _checkPersistedSession();
  }

  Future<void> _checkPersistedSession() async {
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (session == null || user == null) {
      if (mounted) {
        setState(() {
          _targetScreen = const WelcomeScreen();
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      final roleStr = profile?['role']?.toString().toLowerCase().trim() ?? '';
      final businessName =
          profile?['business_name']?.toString().toLowerCase() ?? '';

      final bool isSupplier = roleStr == 'supplier' ||
          roleStr == 'distribuidor' ||
          roleStr == 'proveedor' ||
          businessName.contains('distribuidor');

      if (isSupplier) {
        _targetScreen = const SupplierNavigationHolder();
      } else {
        _targetScreen = const MainNavigationHolder();
      }
    } catch (_) {
      _targetScreen = const WelcomeScreen();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryBlue,
          ),
        ),
      );
    }
    return _targetScreen;
  }
}