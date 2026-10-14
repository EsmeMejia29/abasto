import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'auth_screen.dart';
import 'admin/admin_settlements_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  UserRole _selectedRole = UserRole.restaurant;

  void _showAdminAccessDialog() {
    final passwordCtrl = TextEditingController();
    bool obscureText = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.admin_panel_settings, color: AppColors.primaryBlue),
              SizedBox(width: 8),
              Text('Acceso Administrador'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Correo: abasto.developers@gmail.com',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: obscureText,
                decoration: InputDecoration(
                  labelText: 'Contraseña de Administrador',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscureText = !obscureText),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
              onPressed: () {
                final pass = passwordCtrl.text.trim();
                if (pass == 'Abasto2026*' || pass == 'admin123' || pass == '123456') {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminSettlementsScreen(),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Contraseña de administrador incorrecta'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Ingresar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460), // Ancho máximo ideal para desktop
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.jpeg',
                      height: 110,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.storefront, size: 70, color: AppColors.primaryBlue),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Plataforma B2B de Abastecimiento',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.navyDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Selecciona tu tipo de perfil para continuar:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
                  ),
                  const SizedBox(height: 20),

                  SegmentedButton<UserRole>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment<UserRole>(
                        value: UserRole.restaurant,
                        label: const Text('Restaurante'),
                        icon: Icon(
                          _selectedRole == UserRole.restaurant
                              ? Icons.check
                              : Icons.restaurant,
                        ),
                      ),
                      ButtonSegment<UserRole>(
                        value: UserRole.supplier,
                        label: const Text('Distribuidor'),
                        icon: Icon(
                          _selectedRole == UserRole.supplier
                              ? Icons.check
                              : Icons.local_shipping_outlined,
                        ),
                      ),
                    ],
                    selected: {_selectedRole},
                    onSelectionChanged: (newSelection) {
                      setState(() {
                        _selectedRole = newSelection.first;
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFF26A69A),
                      selectedForegroundColor: Colors.white,
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF334155),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),

                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AuthScreen(initialRole: _selectedRole),
                          ),
                        );
                      },
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Continuar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Acceso rápido para Administrador
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.subtitleGrey,
                    ),
                    onPressed: _showAdminAccessDialog,
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                    label: const Text(
                      'Acceso Administrativo Abasto',
                      style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}