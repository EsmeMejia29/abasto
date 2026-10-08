import 'package:supabase_flutter/supabase_flutter.dart';

class ErrorHandler {
  static String parse(dynamic error) {
    // 1. Excepciones de Autenticación de Supabase (AuthApiException / AuthException)
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      final code = error.code?.toLowerCase() ?? '';

      if (code == 'invalid_credentials' ||
          msg.contains('invalid login credentials')) {
        return 'Correo o contraseña incorrectos. Verifica tus datos o regístrate si aún no tienes cuenta.';
      }
      if (code == 'user_already_exists' ||
          msg.contains('user already registered') ||
          msg.contains('already registered')) {
        return 'Ya existe una cuenta registrada con este correo electrónico. Intenta iniciar sesión.';
      }
      if (msg.contains('password should be at least')) {
        return 'La contraseña debe tener al menos 6 caracteres.';
      }
      if (msg.contains('invalid email') ||
          msg.contains('unable to validate email')) {
        return 'Por favor ingresa un correo electrónico válido.';
      }
      if (msg.contains('email not confirmed')) {
        return 'Tu correo electrónico aún no ha sido confirmado';
      }
      if (msg.contains('over_email_send_rate_limit')) {
        return 'Demasiados intentos. Espera unos momentos antes de volver a intentar.';
      }
      return 'Error de autenticación: ${error.message}';
    }

    // 2. Excepciones de Base de Datos de Supabase (PostgrestException)
    if (error is PostgrestException) {
      final code = error.code ?? '';
      final msg = error.message.toLowerCase();

      if (code == '42501' || msg.contains('row-level security')) {
        return 'No tienes permisos suficientes para realizar esta acción o guardar estos datos.';
      }
      if (code == '23505' || msg.contains('duplicate key')) {
        return 'Este registro o código ya existe en la plataforma.';
      }
      if (code == '23503' || msg.contains('violates foreign key')) {
        return 'No se encontró la información o el usuario de referencia.';
      }
      if (code == 'PGRST200' || msg.contains('could not find a relationship')) {
        return 'Error al cargar los registros relacionados. Intenta recargar la pantalla.';
      }
      return 'Error en la base de datos: ${error.message}';
    }

    // 3. Errores generales / Red
    final errStr = error.toString().toLowerCase();
    if (errStr.contains('failed to fetch') ||
        errStr.contains('network') ||
        errStr.contains('connection')) {
      return 'Error de conexión. Verifica tu acceso a internet.';
    }

    return 'Ocurrió un error inesperado. Por favor, intenta de nuevo.';
  }
}