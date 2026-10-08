import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'theme/app_theme.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/crm_screen.dart'; // <-- Reemplaza financing_screen

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

  final List<Widget> _screens = const [
    HomeScreen(),
    OrdersScreen(),
    CrmScreen(), // <-- Pestaña del CRM
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Proveedores',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Pedidos',
          ),
          NavigationDestination(
            icon: Icon(Icons.contact_phone_outlined),
            selectedIcon: Icon(Icons.contact_phone),
            label: 'Mi CRM',
          ),
        ],
      ),
    );
  }
}