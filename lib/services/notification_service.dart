import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../main.dart';
import '../config/session_manager.dart';
import '../utils/app_badge_service.dart';

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

      html.ServiceWorkerRegistration? swReg;
      try {
        swReg = await html.window.navigator.serviceWorker
            ?.register('/firebase-messaging-sw.js');
      } catch (e) {
        debugPrint('[Push] Aviso registrando SW: $e');
      }

      final token = await messaging.getToken(
        vapidKey: _vapidKey,
      );
      if (token != null && token.isNotEmpty) {
        await supabase
            .from('profiles')
            .update({'fcm_token': token}).eq('id', uid);
        debugPrint('[Push] fcm_token guardado correctamente: ${token.substring(0, 12)}...');
      } else {
        debugPrint('[Push] getToken devolvió null (revisa web/firebase-messaging-sw.js)');
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
        AppBadgeService.incrementBadge();
        showLocalSystemNotification(title, body);
      });
    } catch (e) {
      debugPrint('[Push] Error inicializando notificaciones: $e');
    }
  }

  static Future<void> showLocalSystemNotification(
      String title, String body) async {
    try {
      debugPrint(
          '[Push] Intentando mostrar notificación. supported=${html.Notification.supported}, permission=${html.Notification.permission}');
      if (!html.Notification.supported) return;

      if (html.Notification.permission != 'granted') {
        final perm = await html.Notification.requestPermission();
        debugPrint('[Push] Resultado requestPermission: $perm');
        if (perm != 'granted') return;
      }

      // 1. Notificación nativa inmediata de navegador/Windows
      final notif = html.Notification(
        title,
        body: body,
        icon: '/icons/Icon-192.png',
      );
      notif.onClick.listen((_) {
        try {
          js_util.callMethod(html.window, 'focus', []);
        } catch (_) {}
        notif.close();
      });
    } catch (e) {
      debugPrint('[Push] Error mostrando notificación: $e');
    }
  }
  
}