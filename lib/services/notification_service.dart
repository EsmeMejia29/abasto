import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initializeAndRegisterToken() async {
    try {
      // 1. Solicitar permiso al usuario en el navegador / sistema
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('Permiso de notificaciones concedido por el usuario.');

        // 2. Obtener el Token FCM del dispositivo usando tu VAPID Key
        String? token;
        if (kIsWeb) {
          token = await _messaging.getToken(
            vapidKey: 'BEY2h-KBcw4MkpGHOXVIwosQ6LsDHtzvTDa4uA1gvQ48vpd4ShUdiS90hHzE4HEGdKmb_U7BPC1BW3eYVIHXDcA',
          );
        } else {
          token = await _messaging.getToken();
        }

        if (token != null) {
          debugPrint('Token FCM obtenido: $token');
          await _saveTokenToSupabase(token);
        }

        // 3. Escuchar si el token se renueva
        _messaging.onTokenRefresh.listen((newToken) {
          _saveTokenToSupabase(newToken);
        });

        // 4. Escuchar notificaciones mientras la app está abierta
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('Notificación recibida en primer plano: ${message.notification?.title}');
        });
      } else {
        debugPrint('El usuario denegó los permisos de notificación.');
      }
    } catch (e) {
      debugPrint('Error en NotificationService: $e');
    }
  }

  static Future<void> _saveTokenToSupabase(String token) async {
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) return;

    try {
      await supabase.from('profiles').update({
        'fcm_token': token,
      }).eq('id', currentUserId);
      debugPrint('Token guardado en Supabase para el usuario: $currentUserId');
    } catch (e) {
      debugPrint('Error al guardar token en profiles: $e');
    }
  }
}