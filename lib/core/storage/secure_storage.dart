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
