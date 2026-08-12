import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../data/driver_operations_repository.dart';

/// Mantiene `lastSeenAt` vivo en Backend durante COMPLETED, el
/// cobro en efectivo y PAID (Checkpoint F1), sin decidir
/// disponibilidad ni publicar ubicación.
///
/// Backend degrada AVAILABLE -> OFFLINE si `lastSeenAt` supera su
/// TTL de presencia (~90s) la próxima vez que se consulta
/// `GET operational-status`. Estas tres pantallas no tenían ningún
/// heartbeat propio (a diferencia de Home/ActiveRide, que sí lo
/// hacen cada 10s), así que un cobro largo podía dejar al Driver
/// "desconectado" al volver al Home aunque siguiera usando la app
/// activamente.
///
/// Reutiliza exclusivamente el heartbeat presence-only ya existente
/// (`POST drivers/me/operational-status/heartbeat`, sin body, sin
/// GPS). Nunca llama `goOnline`/`goOffline`/`updateLocation`, nunca
/// muta `operationalState` localmente: Backend sigue siendo la
/// única autoridad. Es best-effort — cualquier error (400 porque el
/// Driver está realmente OFFLINE, red, 5xx) se ignora en silencio y
/// se espera al siguiente ciclo, sin romper la pantalla que lo usa.
///
/// Solo activo en foreground: se detiene en `paused`/`inactive`/etc.
/// y se reanuda con un heartbeat inmediato en `resumed`. No hay
/// background service ni WorkManager: si la app muere, no queda
/// ningún heartbeat pendiente.
class DriverPostRidePresence with WidgetsBindingObserver {
  DriverPostRidePresence({
    required this.repository,
    this.interval = const Duration(seconds: 30),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _sendHeartbeat();
    _startTimer();
  }

  final DriverOperationsRepository repository;
  final Duration interval;

  Timer? _timer;
  bool _disposed = false;

  @visibleForTesting
  bool get debugIsActive => _timer != null;

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _sendHeartbeat());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _sendHeartbeat() async {
    try {
      await repository.heartbeat();
    } on DioException catch (error) {
      // Best-effort: 400 (Driver realmente OFFLINE), timeout o 5xx
      // nunca deben romper COMPLETED/Cash/PAID, forzar goOnline ni
      // disparar un reintento agresivo. Se espera al próximo ciclo.
      debugPrint(
        'DRIVER POST-RIDE PRESENCE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );
    } catch (error) {
      debugPrint('DRIVER POST-RIDE PRESENCE ERROR inesperado: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) {
      return;
    }

    if (state == AppLifecycleState.resumed) {
      _sendHeartbeat();
      _startTimer();

      return;
    }

    _stopTimer();
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _stopTimer();
    WidgetsBinding.instance.removeObserver(this);
  }
}
