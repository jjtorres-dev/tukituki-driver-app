import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_notifications_service.dart';

final pushMessageHandlerProvider = Provider<PushMessageHandler>((ref) {
  final handler = PushMessageHandler(
    _firebaseOnMessage(),
    ref.watch(localNotificationsProvider),
  );

  ref.onDispose(handler.dispose);

  return handler;
});

/// Acceso best-effort a `FirebaseMessaging.onMessage`. Si Firebase no
/// inicializó (sin conexión al arrancar, Play Services ausente, etc.),
/// tocar el stream no debe romper la app: se devuelve un stream vacío
/// y el conductor sigue viendo las propuestas por el polling de 3s del
/// Home.
Stream<RemoteMessage> _firebaseOnMessage() {
  try {
    return FirebaseMessaging.onMessage;
  } catch (error) {
    debugPrint(
      'DRIVER PUSH - FirebaseMessaging.onMessage no disponible: $error',
    );
    return const Stream<RemoteMessage>.empty();
  }
}

/// `DRIVER-PUSH-R1` (Etapa 2). Hermana de `PushRegistrationCoordinator`
/// (no la extiende ni la modifica): materializa en la barra de estado
/// las `RemoteMessage` que llegan con la app en foreground —el único
/// caso donde FCM no dibuja nada por su cuenta.
///
/// Todo es best-effort: un fallo nunca lanza ni interrumpe el flujo
/// normal; solo `debugPrint`. Sigue el patrón "best-effort" del repo
/// (registro push de Etapa 1, heartbeats de presencia).
///
/// Etapa 2 NO maneja el tap de la notificación (solo trae la app al
/// frente), ni `onMessageOpenedApp` / `onBackgroundMessage` /
/// `getInitialMessage`: eso es Etapa 3.
class PushMessageHandler {
  PushMessageHandler(this._messages, this._localNotifications);

  final Stream<RemoteMessage> _messages;
  final LocalNotifications _localNotifications;

  /// Guard de suscripción única (mismo patrón que `_tokenRefreshWired`
  /// en Etapa 1): aunque `start()` se llame en cada arranque, solo se
  /// suscribe una vez.
  bool _started = false;
  StreamSubscription<RemoteMessage>? _subscription;

  /// Suscripción síncrona al stream de mensajes en foreground.
  /// Idempotente. Best-effort: si suscribirse fallara, se traga el
  /// error.
  void start() {
    if (_started) {
      return;
    }

    _started = true;

    try {
      _subscription = _messages.listen(_handleMessage);
    } catch (error) {
      debugPrint(
        'DRIVER PUSH - PushMessageHandler no pudo suscribirse a onMessage: '
        '$error',
      );
    }
  }

  void _handleMessage(RemoteMessage message) {
    try {
      final screen = message.data['screen'];

      if (screen != 'ride-offer') {
        debugPrint(
          "DRIVER PUSH - mensaje ignorado (screen=$screen, se esperaba "
          "'ride-offer')",
        );
        return;
      }

      final title = message.notification?.title ?? 'Nueva solicitud de viaje';
      final body =
          message.notification?.body ?? 'Toca para ver los detalles';

      unawaited(_localNotifications.show(title: title, body: body));
    } catch (error) {
      debugPrint('DRIVER PUSH - error procesando mensaje push: $error');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
