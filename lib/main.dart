import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';

import 'config/supabase_config.dart';
import 'config/session_manager.dart';
import 'services/notification_service.dart';
import 'screens/crm_screen.dart';
import 'screens/home_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/supplier/supplier_catalog_view.dart';
import 'screens/supplier/supplier_crm_screen.dart';
import 'screens/supplier/supplier_incoming_orders_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme/app_theme.dart';

import 'dart:html' as html;

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicialización de Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  // 2. Inicialización de Firebase Web
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'AIzaSy' 'BtMzLjo_jFiLmPUytCC2J0bxhCZgUiJp0',
        authDomain: 'abasto-sv.firebaseapp.com',
        projectId: 'abasto-sv',
        storageBucket: 'abasto-sv.firebasestorage.app',
        messagingSenderId: '467568058533',
        appId: '1:467568058533:web:a36598ccf13196df232d4c',
      ),
    );
  } catch (e) {
    debugPrint('Aviso Firebase: $e');
  }

  // 3. Si ya hay una sesión guardada activa, inicializar notificaciones de inmediato
  if (supabase.auth.currentUser != null) {
    NotificationService.initializeAndRegisterToken();
  }

  final uri = Uri.base;
  final paidOrderCode = uri.queryParameters['identificadorEnlaceComercio'];
  final txId = uri.queryParameters['idTransaccion'];

  if (paidOrderCode != null && paidOrderCode.isNotEmpty && txId != null) {
    // Le avisa al modal padre que Wompi aprobó el pago
    html.window.parent?.postMessage({
      'type': 'WOMPI_PAYMENT_APPROVED',
      'orderCode': paidOrderCode,
      'transactionId': txId,
    }, '*');
    return; // Detiene la carga de la pantalla de inicio dentro del iframe
  }

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

Widget _buildNavIconWithBadge(IconData iconData, bool showBadge) {
  if (!showBadge) return Icon(iconData);
  return Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(iconData),
      Positioned(
        top: -2,
        right: -3,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      ),
    ],
  );
}

/// Contenedor de navegación para Restaurante
class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;
  bool _hasUnreadChat = false;
  RealtimeChannel? _navMsgChannel;

  String get _uid =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  final List<Widget> _screens = const [
    HomeScreen(),
    OrdersScreen(),
    CrmScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkInitialUnread();
    _listenIncomingMessages();
  }

  @override
  void dispose() {
    _navMsgChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkInitialUnread() async {
    if (_uid.isEmpty) return;
    try {
      final orders = await supabase
          .from('orders')
          .select('id')
          .eq('restaurant_id', _uid);
      final orderIds =
          (orders as List<dynamic>).map((o) => o['id'].toString()).toList();
      if (orderIds.isEmpty) return;

      final msgs = await supabase
          .from('order_messages')
          .select('order_id, created_at')
          .filter('order_id', 'in', orderIds)
          .neq('sender_id', _uid)
          .order('created_at', ascending: false)
          .limit(20);

      for (final m in (msgs as List<dynamic>)) {
        final oid = m['order_id']?.toString() ?? '';
        final msgTime = DateTime.tryParse(m['created_at'].toString());
        final lastReadStr =
            html.window.localStorage['abasto_chat_read_${_uid}_$oid'];
        final lastRead =
            lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;
        if (msgTime != null &&
            (lastRead == null || msgTime.isAfter(lastRead))) {
          if (mounted) setState(() => _hasUnreadChat = true);
          return;
        }
      }
    } catch (_) {}
  }

  void _listenIncomingMessages() {
    _navMsgChannel = supabase
        .channel('public:nav_restaurant_msg_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_messages',
          callback: (payload) async {
            final newMsg = payload.newRecord;
            final senderId = newMsg['sender_id']?.toString() ?? '';
            final orderId = newMsg['order_id']?.toString() ?? '';
            if (senderId == _uid || orderId.isEmpty) return;

            final ord = await supabase
                .from('orders')
                .select('restaurant_id')
                .eq('id', orderId)
                .maybeSingle();
            if (ord != null &&
                ord['restaurant_id']?.toString() == _uid &&
                mounted) {
              setState(() => _hasUnreadChat = true);
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
            if (idx == 1) _hasUnreadChat = false;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: _buildNavIconWithBadge(
                Icons.receipt_long_outlined, _hasUnreadChat),
            selectedIcon:
                _buildNavIconWithBadge(Icons.receipt_long, _hasUnreadChat),
            label: 'Pedidos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Mis Gastos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

/// Contenedor de navegación para Distribuidor / Proveedor
class SupplierNavigationHolder extends StatefulWidget {
  const SupplierNavigationHolder({super.key});

  @override
  State<SupplierNavigationHolder> createState() =>
      _SupplierNavigationHolderState();
}

class _SupplierNavigationHolderState extends State<SupplierNavigationHolder> {
  int _currentIndex = 0;
  bool _hasUnreadChat = false;
  RealtimeChannel? _navMsgChannel;

  String get _uid =>
      supabase.auth.currentUser?.id ?? SessionManager.currentUserId;

  final List<Widget> _screens = const [
    SupplierIncomingOrdersScreen(),
    SupplierCatalogView(),
    SupplierCrmScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkInitialUnread();
    _listenIncomingMessages();
  }

  @override
  void dispose() {
    _navMsgChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _checkInitialUnread() async {
    if (_uid.isEmpty) return;
    try {
      final orders = await supabase
          .from('orders')
          .select('id')
          .eq('supplier_id', _uid);
      final orderIds =
          (orders as List<dynamic>).map((o) => o['id'].toString()).toList();
      if (orderIds.isEmpty) return;

      final msgs = await supabase
          .from('order_messages')
          .select('order_id, created_at')
          .filter('order_id', 'in', orderIds)
          .neq('sender_id', _uid)
          .order('created_at', ascending: false)
          .limit(20);

      for (final m in (msgs as List<dynamic>)) {
        final oid = m['order_id']?.toString() ?? '';
        final msgTime = DateTime.tryParse(m['created_at'].toString());
        final lastReadStr =
            html.window.localStorage['abasto_chat_read_${_uid}_$oid'];
        final lastRead =
            lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;
        if (msgTime != null &&
            (lastRead == null || msgTime.isAfter(lastRead))) {
          if (mounted) setState(() => _hasUnreadChat = true);
          return;
        }
      }
    } catch (_) {}
  }

  void _listenIncomingMessages() {
    _navMsgChannel = supabase
        .channel('public:nav_supplier_msg_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_messages',
          callback: (payload) async {
            final newMsg = payload.newRecord;
            final senderId = newMsg['sender_id']?.toString() ?? '';
            final orderId = newMsg['order_id']?.toString() ?? '';
            if (senderId == _uid || orderId.isEmpty) return;

            final ord = await supabase
                .from('orders')
                .select('supplier_id')
                .eq('id', orderId)
                .maybeSingle();
            if (ord != null &&
                ord['supplier_id']?.toString() == _uid &&
                mounted) {
              setState(() => _hasUnreadChat = true);
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
            if (idx == 0) _hasUnreadChat = false;
          });
        },
        destinations: [
          NavigationDestination(
            icon: _buildNavIconWithBadge(
                Icons.receipt_long_outlined, _hasUnreadChat),
            selectedIcon:
                _buildNavIconWithBadge(Icons.receipt_long, _hasUnreadChat),
            label: 'Despachos',
          ),
          const NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Mi Catálogo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'CRM',
          ),
          const NavigationDestination(
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