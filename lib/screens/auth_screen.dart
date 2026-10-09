import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/session_manager.dart';
import '../main.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import 'restaurant_onboarding_screen.dart';
import 'supplier/supplier_onboarding_screen.dart';

class AuthScreen extends StatefulWidget {
  final UserRole initialRole;

  const AuthScreen({super.key, required this.initialRole});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true; // Para alternar únicamente en vista móvil
  bool _isLoading = false;

  // Controladores para Iniciar Sesión
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  // Controladores para Crear Cuenta
  final _regBusinessNameCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPasswordCtrl = TextEditingController();

  late UserRole _role;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _regBusinessNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPasswordCtrl.dispose();
    super.dispose();
  }

  // ========================================================
  // 1. FLUJO EXCLUSIVO DE INICIO DE SESIÓN
  // ========================================================
  Future<void> _submitLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos requeridos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final currentUserId = res.user?.id;
      if (currentUserId != null) {
        final prof = await supabase
            .from('profiles')
            .select('role, business_name')
            .eq('id', currentUserId)
            .maybeSingle();

        if (prof != null) {
          final roleStr = (prof['role'] ?? '').toString().toLowerCase().trim();
          final bName = (prof['business_name'] ?? '').toString().toLowerCase().trim();

          final bool isSupplier = roleStr == 'supplier' ||
              roleStr == 'distribuidor' ||
              roleStr == 'proveedor' ||
              bName.contains('distribuidor');

          final userRole = isSupplier ? UserRole.supplier : UserRole.restaurant;
          SessionManager.switchRole(userRole);
          _role = userRole;
        }

        // Verificación de Onboarding
        if (_role == UserRole.restaurant) {
          final restDetails = await supabase
              .from('restaurant_details')
              .select('onboarding_completed')
              .eq('profile_id', currentUserId)
              .maybeSingle();

          final bool completed = restDetails?['onboarding_completed'] ?? false;
          if (!completed && mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    RestaurantOnboardingScreen(restaurantId: currentUserId),
              ),
              (route) => false,
            );
            return;
          }
        } else if (_role == UserRole.supplier) {
          final suppDetails = await supabase
              .from('supplier_details')
              .select('onboarding_completed')
              .eq('profile_id', currentUserId)
              .maybeSingle();

          final bool completed = suppDetails?['onboarding_completed'] ?? false;
          if (!completed && mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    SupplierOnboardingScreen(supplierId: currentUserId),
              ),
              (route) => false,
            );
            return;
          }
        }
      }

      // Redirección condicionada según el rol real del usuario
      if (mounted) {
        if (_role == UserRole.supplier) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const SupplierNavigationHolder()),
            (route) => false,
          );
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        final friendlyMessage = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ========================================================
  // 2. FLUJO EXCLUSIVO DE REGISTRO
  // ========================================================
  Future<void> _submitRegister() async {
    // Si estamos en mobile toma del formulario móvil, si es desktop toma del controlador de registro
    final email = (_isLogin ? _emailCtrl.text : _regEmailCtrl.text.isEmpty ? _emailCtrl.text : _regEmailCtrl.text).trim();
    final password = (_isLogin ? _passwordCtrl.text : _regPasswordCtrl.text.isEmpty ? _passwordCtrl.text : _regPasswordCtrl.text).trim();
    final businessName = _regBusinessNameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty || businessName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos requeridos.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La contraseña debe tener al menos 6 caracteres.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: 'https://abasto-flame.vercel.app/',
      );

      final newUserId = res.user?.id;
      if (newUserId != null) {
        final roleString =
            _role == UserRole.restaurant ? 'restaurant' : 'supplier';

        // Guardar en la tabla base de profiles
        await supabase.from('profiles').upsert({
          'id': newUserId,
          'email': email,
          'business_name': businessName,
          'role': roleString,
          'created_at': DateTime.now().toIso8601String(),
        });

        // Guardar registro inicial en la tabla correspondiente
        if (_role == UserRole.restaurant) {
          await supabase.from('restaurant_details').upsert({
            'profile_id': newUserId,
            'branch_count': 1,
            'monthly_budget': 500.0,
            'onboarding_completed': false,
          });
        } else {
          await supabase.from('supplier_details').upsert({
            'profile_id': newUserId,
            'category': 'Distribución General',
            'delivery_coverage': 'Área Metropolitana',
            'delivery_days': 'Lunes a Viernes',
            'rating': 5.0,
            'reviews_count': 0,
            'onboarding_completed': false,
          });
        }
      }

      await supabase.auth.signOut();

      if (mounted) {
        setState(() {
          _isLogin = true;
          _passwordCtrl.clear();
          _regPasswordCtrl.clear();
          _regBusinessNameCtrl.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '¡Cuenta registrada con éxito!',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hemos enviado un enlace a $email. Revisa tu bandeja de entrada o spam para confirmar tu correo antes de ingresar.',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: AppColors.tealMint,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final friendlyMessage = ErrorHandler.parse(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyMessage),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- Formulario de Iniciar Sesión ---
  Widget _buildLoginForm({bool isDesktop = false}) {
    final roleName = _role == UserRole.restaurant ? 'Restaurante' : 'Distribuidor';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Bienvenido de nuevo',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Accediendo como perfil de: $roleName',
          style: const TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña (mínimo 6 caracteres)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: _isLoading ? null : _submitLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Iniciar Sesión',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // --- Formulario de Registro ---
  Widget _buildRegisterForm({bool isDesktop = false}) {
    final roleName = _role == UserRole.restaurant ? 'Restaurante' : 'Distribuidor';
    final emailController = isDesktop ? _regEmailCtrl : _emailCtrl;
    final passwordController = isDesktop ? _regPasswordCtrl : _passwordCtrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Regístrate en Abasto',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.navyDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Crear nueva cuenta para: $roleName',
          style: const TextStyle(color: AppColors.subtitleGrey, fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _regBusinessNameCtrl,
          decoration: InputDecoration(
            labelText: _role == UserRole.restaurant
                ? 'Nombre del Restaurante'
                : 'Nombre de la Distribuidora',
            prefixIcon: const Icon(Icons.business),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña (mínimo 6 caracteres)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF26A69A)),
            onPressed: _isLoading ? null : _submitRegister,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text(
                    'Completar Registro',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Ingresar a Abasto' : 'Crear Cuenta'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 850;

            // ==========================================
            // VISTA ESCRITORIO (Dos columnas lado a lado)
            // ==========================================
            if (isDesktop) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1050),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/logo.jpeg',
                            height: 90,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.storefront, size: 70, color: AppColors.primaryBlue),
                          ),
                        ),
                        const SizedBox(height: 36),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Columna Izquierda: Iniciar Sesión
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _buildLoginForm(isDesktop: true),
                              ),
                            ),
                            const SizedBox(width: 32),
                            // Columna Derecha: Registrarse
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(28),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _buildRegisterForm(isDesktop: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ==========================================
            // VISTA MÓVIL (Tarjeta compacta tradicional)
            // ==========================================
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset(
                          'assets/images/logo.jpeg',
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.storefront, size: 60, color: AppColors.primaryBlue),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _isLogin ? _buildLoginForm() : _buildRegisterForm(),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(() => _isLogin = !_isLogin),
                          child: Text(
                            _isLogin
                                ? '¿No tienes cuenta? Regístrate aquí'
                                : '¿Ya tienes cuenta? Inicia sesión',
                            style: const TextStyle(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}