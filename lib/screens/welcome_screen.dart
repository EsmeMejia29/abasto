import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../main.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),

              // Logo de Abasto
              Center(
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Column(
                    children: const [
                      Icon(Icons.storefront, size: 80, color: AppColors.primaryBlue),
                      SizedBox(height: 8),
                      Text(
                        'ABASTO',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.navyDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Título y lema de la propuesta de valor
              const Text(
                'El canal directo entre restaurantes y distribuidores',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navyDark,
                  height: 1.3,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Automatiza tus pedidos de insumos perecederos y accede a financiamiento en cuotas para cuidar tu flujo de caja.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.subtitleGrey,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              // Botón principal para ingresar a la plataforma
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  onPressed: () {
                    // Navega a la navegación principal (Home, Pedidos, Crédito)
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const MainNavigationHolder(),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Comenzar',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Santa Tecla & Zona Metropolitana • El Salvador',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}