import 'package:flutter/material.dart';

class AppColors {
  // Colores extraídos directamente del logo
  static const Color navyDark = Color(0xFF162A45);       // Azul noche del texto ABASTO
  static const Color primaryBlue = Color(0xFF1C4E77);   // Azul medio de la flecha
  static const Color tealMint = Color(0xFF3EC4A5);      // Verde menta / turquesa de la flecha
  static const Color mintLight = Color(0xFF52D1B2);     // Acento claro superior
  static const Color subtitleGrey = Color(0xFF4A5568);  // Gris texto secundario
  static const Color background = Color(0xFFF8FAFC);    // Fondo sutil frío
  static const Color surface = Colors.white;

  // Gradiente característico del logo para tarjetas y cabeceras
  static const LinearGradient logoGradient = LinearGradient(
    colors: [navyDark, primaryBlue, tealMint],
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
  );
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.light(
        primary: AppColors.primaryBlue,
        secondary: AppColors.tealMint,
        surface: AppColors.surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.navyDark,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.navyDark),
        titleTextStyle: TextStyle(
          color: AppColors.navyDark,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.tealMint.withOpacity(0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryBlue);
          }
          return const IconThemeData(color: AppColors.subtitleGrey);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.primaryBlue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            );
          }
          return const TextStyle(color: AppColors.subtitleGrey, fontSize: 12);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      // Reemplaza CardTheme por CardThemeData:
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}