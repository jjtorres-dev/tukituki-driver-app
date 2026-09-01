import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

class StorageKeys {
  const StorageKeys._();

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const sessionId = 'session_id';

  /// `DRIVER-PUSH-R1`: identificador estable **por instalación de la
  /// app**, no por cuenta. Se genera una sola vez (`DeviceIdStore`,
  /// `Uuid().v4()`) y se envía a Backend en `POST /me/devices` como
  /// `deviceId`.
  ///
  /// Deliberadamente **no** se borra en `AuthRepository.clearSession()`
  /// ni en `AuthInterceptor._clearSession()` (ambos borran una lista
  /// explícita de claves y esta no está en ella): cerrar sesión termina
  /// la sesión, no la identidad del dispositivo. Debe sobrevivir
  /// logout, cambio de cuenta y cerrar/reabrir la app, para que Backend
  /// pueda seguir revocando el registro anterior por `deviceId` cuando
  /// otro conductor inicia sesión en el mismo teléfono.
  static const deviceId = 'device_id';

  /// `DRIVER-ONBOARDING-R3.8`/`R3.8B`: marcador local no sensible —
  /// nunca la razón de rechazo, ni ningún dato del expediente — que
  /// indica que la solicitud del conductor identificado por [userId]
  /// sigue en un ciclo de corrección/reenvío tras un rechazo.
  ///
  /// **Scoped por [userId]** (`AuthenticatedUser.id`, nunca DNI/
  /// email/teléfono): un booleano global compartido por toda la
  /// instalación filtraría el contexto de una cuenta a otra si dos
  /// conductores usan el mismo dispositivo (`R3.8B`, hallazgo físico
  /// pre-review). Por eso este marcador **no** se borra en
  /// `AuthRepository.clearSession()` — el logout termina la sesión,
  /// no el ciclo administrativo de esa cuenta — y debe sobrevivir
  /// cerrar/abrir la app, cerrar sesión y volver a iniciarla con la
  /// misma cuenta. Ver `AuthRepository.markResubmissionContext()`.
  static String driverResubmissionContext(String userId) =>
      'driver_resubmission_context:$userId';
}
