import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final pushRegistrationRepositoryProvider = Provider<PushRegistrationRepository>((
  ref,
) {
  return PushRegistrationRepository(ref.watch(dioProvider));
});

/// `DRIVER-PUSH-R1`: registra/actualiza el dispositivo push de la
/// cuenta autenticada.
///
/// Contrato del backend (`POST me/devices`, `@Controller('me')` +
/// `@Post('devices')`): upsert por `(userId, deviceId)`; además revoca
/// cualquier otra fila activa con el mismo `pushToken`, sin filtrar por
/// `userId` — por eso NO hace falta un des-registro explícito en
/// logout. `409` si el token quedó activo en otra fila por una carrera
/// (raro; el próximo intento lo resuelve).
class PushRegistrationRepository {
  PushRegistrationRepository(this._dio);

  final Dio _dio;

  /// App Android-only: no hay carpeta `ios/` en el repo.
  static const _platformAndroid = 'ANDROID';

  /// Emite `POST me/devices`. Deja propagar cualquier `DioException`:
  /// el llamador (`PushRegistrationCoordinator`) decide que un fallo de
  /// registro es best-effort y no debe romper el flujo.
  Future<void> registerDevice({
    required String pushToken,
    required String deviceId,
    String? appVersion,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      'me/devices',
      data: {
        'platform': _platformAndroid,
        'pushToken': pushToken,
        'deviceId': deviceId,
        if (appVersion != null && appVersion.isNotEmpty)
          'appVersion': appVersion,
      },
    );
  }
}
