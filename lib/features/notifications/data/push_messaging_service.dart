import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pushMessagingServiceProvider = Provider<PushMessagingService>((ref) {
  return FirebasePushMessagingService();
});

/// `DRIVER-PUSH-R1`: seam fino sobre `FirebaseMessaging` para que
/// `PushRegistrationCoordinator` sea testeable con un doble a mano
/// (no se puede usar el plugin real dentro de `flutter_test`).
abstract class PushMessagingService {
  /// Solicita permiso de notificaciones. En Android 13+ dispara el
  /// diálogo `POST_NOTIFICATIONS`; en versiones anteriores es efectivo
  /// no-op. Devuelve `true` si quedó autorizado o provisional.
  Future<bool> requestPermission();

  /// Token de registro FCM de esta instalación, o `null` si todavía no
  /// hay uno (p.ej. sin Google Play Services o error transitorio).
  Future<String?> getToken();

  /// Emite cada vez que FCM rota el token de registro.
  Stream<String> get onTokenRefresh;
}

class FirebasePushMessagingService implements PushMessagingService {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
