import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../config/session_manager.dart';
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
  bool _isLogin = true;
  bool _isLoading = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
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
    _businessNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final businessName = _businessNameCtrl.text.trim();

    if (email.isEmpty || password.isEmpty || (!_isLogin && businessName.isEmpty)) {
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
      if (!_isLogin) {
        // ========================================================
        // 1. FLUJO EXCLUSIVO DE REGISTRO
        // ========================================================
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
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

        // Cerrar la sesión activa generada por el registro
          await supabase.auth.signOut();

          if (mounted) {
            setState(() {
              _isLogin = true;
              _passwordCtrl.clear();
              _businessNameCtrl.clear();
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
          return;
      }

      // ========================================================
      // 2. FLUJO EXCLUSIVO DE INICIO DE SESIÓN
      // ========================================================
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final currentUserId = res.user?.id;
      if (currentUserId != null) {
        final prof = await supabase
            .from('profiles')
            .select('role')
            .eq('id', currentUserId)
            .maybeSingle();

        if (prof != null) {
          final roleStr = prof['role'] as String?;
          final userRole =
              roleStr == 'supplier' ? UserRole.supplier : UserRole.restaurant;
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

      // Solo si el login fue exitoso y el onboarding ya está completado
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationHolder()),
          (route) => false,
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

  @override
  Widget build(BuildContext context) {
    final roleName =
        _role == UserRole.restaurant ? 'Restaurante' : 'Distribuidor';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLogin ? 'Ingresar a Abasto' : 'Crear Cuenta'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                _isLogin ? 'Bienvenido de nuevo' : 'Regístrate en Abasto',
                style: const TextStyle(
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

              if (!_isLogin) ...[
                TextField(
                  controller: _businessNameCtrl,
                  decoration: InputDecoration(
                    labelText: _role == UserRole.restaurant
                        ? 'Nombre del Restaurante'
                        : 'Nombre de la Distribuidora',
                    prefixIcon: const Icon(Icons.business),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

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
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isLogin ? 'Iniciar Sesión' : 'Completar Registro',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
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
  }
}