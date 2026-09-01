import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_id_store.dart';
import 'push_messaging_service.dart';
import 'push_registration_repository.dart';

final pushRegistrationCoordinatorProvider =
    Provider<PushRegistrationCoordinator>((ref) {
      final coordinator = PushRegistrationCoordinator(
        ref.watch(pushMessagingServiceProvider),
        ref.watch(deviceIdStoreProvider),
        ref.watch(pushRegistrationRepositoryProvider),
      );

      ref.onDispose(coordinator.dispose);

      return coordinator;
    });

/// `DRIVER-PUSH-R1` (Etapa 1). Orquesta el registro del dispositivo
/// push tras confirmar una sesión válida (lo llama
/// `DriverSplashScreen._checkSession`).
///
/// Todo es best-effort: un fallo (permiso denegado, sin token, Backend
/// caído, Firebase sin inicializar) nunca lanza ni interrumpe el flujo
/// normal de la app — solo `debugPrint`. Sigue el patrón "best-effort"
/// del repo (logout remoto, heartbeats de presencia).
///
/// Etapa 1 NO maneja notificaciones visibles (foreground / background /
/// tap): eso es Etapa 2 y 3.
class PushRegistrationCoordinator {
  PushRegistrationCoordinator(
    this._messaging,
    this._deviceIdStore,
    this._repository,
  );

  final PushMessagingService _messaging;
  final DeviceIdStore _deviceIdStore;
  final PushRegistrationRepository _repository;

  bool _tokenRefreshWired = false;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Etapa 1: `appVersion` no se envía todavía (campo opcional del
  /// backend). No existe mecanismo de versión del paquete en el repo;
  /// se decidirá aparte (package_info_plus o --dart-define).
  static const String? _appVersion = null;

  /// Pide permiso (best-effort), obtiene el token FCM y registra el
  /// dispositivo. Idempotente: se puede llamar en cada arranque.
  Future<void> syncDeviceRegistration() async {
    try {
      // El resultado y los errores del permiso se ignoran a propósito:
      // aunque el conductor lo deniegue, el token FCM sigue siendo
      // válido y registramos igual (la notificación simplemente no se
      // mostrará hasta que habilite el permiso desde Ajustes).
      try {
        final granted = await _messaging.requestPermission();
        debugPrint('DRIVER PUSH - permiso de notificaciones: $granted');
      } catch (error) {
        debugPrint('DRIVER PUSH - requestPermission() falló: $error');
      }

      final token = await _messaging.getToken();

      if (token == null || token.isEmpty) {
        debugPrint('DRIVER PUSH - sin token FCM, se omite el registro');
        return;
      }

      final deviceId = await _deviceIdStore.getOrCreate();

      await _repository.registerDevice(
        pushToken: token,
        deviceId: deviceId,
        appVersion: _appVersion,
      );

      debugPrint('DRIVER PUSH - dispositivo registrado');

      _wireTokenRefresh();
    } catch (error) {
      debugPrint('DRIVER PUSH - registro best-effort falló: $error');
    }
  }

  /// Suscribe `onTokenRefresh` una sola vez (aunque
  /// `syncDeviceRegistration` se llame varias veces): cada rotación de
  /// token re-registra el dispositivo con el token nuevo y el mismo
  /// `deviceId` persistido.
  void _wireTokenRefresh() {
    if (_tokenRefreshWired) {
      return;
    }

    _tokenRefreshWired = true;

    _tokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) async {
      if (newToken.isEmpty) {
        return;
      }

      try {
        final deviceId = await _deviceIdStore.getOrCreate();

        await _repository.registerDevice(
          pushToken: newToken,
          deviceId: deviceId,
          appVersion: _appVersion,
        );

        debugPrint('DRIVER PUSH - token rotado, dispositivo re-registrado');
      } catch (error) {
        debugPrint('DRIVER PUSH - re-registro por token rotado falló: $error');
      }
    });
  }

  void dispose() {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
