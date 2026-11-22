import 'dart:html' as html;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../config/session_manager.dart';

class NotificationService {
  static const String _vapidKey =
      'BEY2h-KBcw4MkpGHOXVIwosQ6LsDHtzvTDa4uA1gvQ48vpd4ShUdiS90hHzE4HEGdKmb_U7BPC1BW3eYVIHXDcA';

  static Future<void> initializeAndRegisterToken() async {
    try {
      final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
      if (uid.isEmpty) return;

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('[Push] Permiso denegado por el usuario');
        return;
      }

      final token = await messaging.getToken(vapidKey: _vapidKey);
      if (token != null && token.isNotEmpty) {
        await supabase
            .from('profiles')
            .update({'fcm_token': token}).eq('id', uid);
        debugPrint('[Push] fcm_token guardado correctamente');
      }

      messaging.onTokenRefresh.listen((newToken) async {
        if (newToken.isNotEmpty) {
          await supabase
              .from('profiles')
              .update({'fcm_token': newToken}).eq('id', uid);
        }
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? 'Abasto';
        final body = message.notification?.body ?? '';
        if (html.Notification.supported &&
            html.Notification.permission == 'granted') {
          html.Notification(
            title,
            body: body,
            icon: '/icons/Icon-192.png',
          );
        }
      });
    } catch (e) {
      debugPrint('[Push] Error inicializando notificaciones: $e');
    }
  }
}