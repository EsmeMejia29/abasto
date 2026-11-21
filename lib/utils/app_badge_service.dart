import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../config/session_manager.dart';

class AppBadgeService {
  static RealtimeChannel? _ordersChannel;
  static RealtimeChannel? _messagesChannel;
  static int _unreadCount = 0;

  static void startListening() {
    stopListening();
    final uid = supabase.auth.currentUser?.id ?? SessionManager.currentUserId;
    debugPrint('[Badge] Iniciando escucha Realtime para uid: $uid');
    if (uid.isEmpty) return;

    // 1. Escuchar nuevos pedidos recibidos como Distribuidor
    _ordersChannel = supabase
        .channel('global_badge_orders_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: (payload) {
            final supplierId =
                payload.newRecord['supplier_id']?.toString() ?? '';
            debugPrint('[Badge] Nuevo pedido detectado -> supplier_id: $supplierId');
            if (supplierId == uid) {
              incrementBadge();
            }
          },
        )
        .subscribe((status, [error]) {
      debugPrint('[Badge] Estado canal orders: $status $error');
    });

    // 2. Escuchar nuevos mensajes de chat de otros usuarios
    _messagesChannel = supabase
        .channel('global_badge_messages_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_messages',
          callback: (payload) {
            final senderId =
                payload.newRecord['sender_id']?.toString() ?? '';
            debugPrint('[Badge] Nuevo mensaje detectado -> sender_id: $senderId');
            if (senderId.isNotEmpty && senderId != uid) {
              incrementBadge();
            }
          },
        )
        .subscribe((status, [error]) {
      debugPrint('[Badge] Estado canal messages: $status $error');
    });
  }

  static void incrementBadge() {
    _unreadCount++;
    debugPrint('[Badge] Incrementando contador a $_unreadCount');
    _applyBadge(_unreadCount);
  }

  static void clearBadge() {
    _unreadCount = 0;
    _applyBadge(0);
  }

  static void _applyBadge(int count) {
    // 1. Badge en ícono de app instalada (PWA / teléfono / escritorio)
    try {
      final nav = html.window.navigator;
      if (js_util.hasProperty(nav, 'setAppBadge')) {
        if (count > 0) {
          js_util.callMethod(nav, 'setAppBadge', [count]);
        } else {
          js_util.callMethod(nav, 'clearAppBadge', []);
        }
      }
    } catch (e) {
      debugPrint('[Badge] Aviso setAppBadge: $e');
    }

    // 2. Título de pestaña en navegador
    html.document.title = count > 0 ? '🔴 ($count) Abasto' : 'Abasto';

    // 3. Favicon dinámico con puntito rojo dibujado en Canvas
    void setIconHref(String href) {
      final existing = html.document.querySelectorAll("link[rel*='icon']");
      for (final el in existing) {
        el.remove();
      }
      final link = html.LinkElement()
        ..rel = 'icon'
        ..type = 'image/png'
        ..href = href;
      html.document.head?.append(link);
    }

    if (count <= 0) {
      setIconHref('favicon.png?v=2');
      return;
    }

    final img = html.ImageElement(src: 'favicon.png?v=2');
    img.onLoad.listen((_) {
      final canvas = html.CanvasElement(width: 64, height: 64);
      final ctx = canvas.context2D;
      ctx.drawImageScaled(img, 0, 0, 64, 64);

      ctx.beginPath();
      ctx.arc(48, 16, 15, 0, 2 * 3.141592653589793);
      ctx.fillStyle = '#EF4444';
      ctx.fill();
      ctx.lineWidth = 3;
      ctx.strokeStyle = '#FFFFFF';
      ctx.stroke();

      setIconHref(canvas.toDataUrl('image/png'));
    });
    img.onError.listen((_) {
      final canvas = html.CanvasElement(width: 64, height: 64);
      final ctx = canvas.context2D;
      ctx.beginPath();
      ctx.arc(32, 32, 26, 0, 2 * 3.141592653589793);
      ctx.fillStyle = '#EF4444';
      ctx.fill();
      setIconHref(canvas.toDataUrl('image/png'));
    });
  }

  static void stopListening() {
    _ordersChannel?.unsubscribe();
    _messagesChannel?.unsubscribe();
    _ordersChannel = null;
    _messagesChannel = null;
  }
  
  static void decrementBadge() {
    if (_unreadCount > 0) {
      _unreadCount--;
    }
    _applyBadge(_unreadCount);
  }
}