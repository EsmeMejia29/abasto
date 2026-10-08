import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'config/session_manager.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/inventory_screen.dart'; // <-- MI INVENTARIO
import 'screens/profile_screen.dart';
import 'screens/supplier/supplier_incoming_orders_screen.dart';
import 'screens/supplier/supplier_inventory_screen.dart';

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
      theme: AppTheme.lightTheme,
      home: const WelcomeScreen(),
    );
  }
}

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isRestaurant = SessionManager.currentRole.value == UserRole.restaurant;

    final List<Widget> screens = isRestaurant
        ? const [HomeScreen(), OrdersScreen(), InventoryScreen(), ProfileScreen()]
        : const [SupplierIncomingOrdersScreen(), SupplierInventoryScreen(), ProfileScreen()];

    final List<NavigationDestination> destinations = isRestaurant
        ? const [
            NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Proveedores'),
            NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'Mis Pedidos'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Mi Inventario'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Mi Perfil'),
          ]
        : const [
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Despachos'),
            NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Mi Catálogo'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Mi Perfil'),
          ];

    return Scaffold(
      body: screens[_currentIndex.clamp(0, screens.length - 1)],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex.clamp(0, destinations.length - 1),
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: destinations,
      ),
    );
  }
}