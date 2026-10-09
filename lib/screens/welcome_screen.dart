// En lib/screens/welcome_screen.dart:
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../config/session_manager.dart';
import 'auth_screen.dart'; // <-- IMPORTA AUTH SCREEN

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
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navyDark),
              ),
              const SizedBox(height: 10),
              const Text(
                'Selecciona tu tipo de perfil para continuar:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.subtitleGrey),
              ),
              const SizedBox(height: 20),

              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment<UserRole>(
                    value: UserRole.restaurant,
                    label: Text('Restaurante'),
                    icon: Icon(Icons.check),
                  ),
                  ButtonSegment<UserRole>(
                    value: UserRole.supplier,
                    label: Text('Distribuidor'),
                    icon: Icon(Icons.local_shipping),
                  ),
                ],
                selected: {_selectedRole},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedRole = newSelection.first;
                  });
                },
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: const Color(0xFF26A69A), // Verde menta / teal característico
                  selectedForegroundColor: Colors.white,            // Texto e icono en blanco
                  backgroundColor: Colors.white,                    // Fondo del no seleccionado
                  foregroundColor: const Color(0xFF334155),         // Texto del no seleccionado
                  side: const BorderSide(color: Color(0xFFCBD5E1)), // Borde sutil gris
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),        // Bordes redondeados elegantes
                  ),
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                  onPressed: () {
                    // Navega a la pantalla de Login / Registro pasando el rol elegido
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
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
    );
  }
}