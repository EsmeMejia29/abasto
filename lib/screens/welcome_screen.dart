import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'auth_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  UserRole _selectedRole = UserRole.restaurant;

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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}