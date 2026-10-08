import 'package:flutter/material.dart';

enum UserRole { restaurant, supplier }

class SessionManager {
  // IDs fijos de demo para alternar perfiles al instante
  static const String restaurantId = '11111111-1111-1111-1111-111111111111';
  static const String supplierId = '22222222-2222-2222-2222-222222222222';

  static final ValueNotifier<UserRole> currentRole =
      ValueNotifier<UserRole>(UserRole.restaurant);

  static String get currentUserId =>
      currentRole.value == UserRole.restaurant ? restaurantId : supplierId;

  static void switchRole(UserRole newRole) {
    currentRole.value = newRole;
  }
}