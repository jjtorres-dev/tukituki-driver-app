import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../driver/domain/driver_application.dart';
import '../../driver/domain/driver_document.dart';
import '../../driver/domain/driver_vehicle.dart';
import '../domain/authenticated_user.dart';
import '../domain/driver_session_state.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(secureStorageProvider),
  );
});

class AuthRepository {
  AuthRepository(this._dio, this._storage);

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/login',
      data: {'phoneE164': phoneE164, 'password': password},
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final sessionId = data['sessionId'] as String?;

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      throw Exception('La respuesta de inicio de sesión es inválida.');
    }

    try {
      await _storage.write(key: StorageKeys.accessToken, value: accessToken);

      await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);

      await _storage.write(key: StorageKeys.sessionId, value: sessionId);
    } catch (_) {
      await clearSession();
      rethrow;
    }
  }

  Future<bool> hasSession() async {
    final accessToken = await _storage.read(key: StorageKeys.accessToken);

    final refreshToken = await _storage.read(key: StorageKeys.refreshToken);

    final sessionId = await _storage.read(key: StorageKeys.sessionId);

    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty;
  }

  /// Registra una cuenta nueva vía `POST auth/register/passenger`,
  /// reutilizada internamente para Driver App (decisión de producto:
  /// no existe `POST auth/register/driver`). Esta respuesta NUNCA
  /// trae sesión/tokens — el caller debe llamar [login] por
  /// separado con las mismas credenciales.
  Future<void> registerPassenger({
    required String phoneE164,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/register/passenger',
      data: {'phoneE164': phoneE164, 'password': password},
    );

    if (response.data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }
  }

  /// `GET auth/me` — única fuente de verdad de `roles`/
  /// `isPhoneVerified` en el cliente.
  Future<AuthenticatedUser> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('auth/me');

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return AuthenticatedUser.fromJson(data);
  }

  /// `GET drivers/me` — la solicitud de conductor de la cuenta
  /// actual, o `null` si todavía no existe (404, contrato esperado
  /// documentado en `decisiones.md`: NO_PROFILE, no un error fatal).
  /// Cualquier otro `DioException` se relanza sin envolver.
  Future<DriverApplication?> getDriverProfile() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('drivers/me');

      final data = response.data;

      if (data == null) {
        throw Exception('El backend devolvió una respuesta vacía.');
      }

      return DriverApplication.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  /// `GET drivers/me/vehicle` — el vehículo del conductor, o `null`
  /// si todavía no existe (404, mismo contrato que
  /// `getDriverProfile`: NO_PROFILE/sin vehículo no es un error).
  /// Cualquier otro `DioException` se relanza sin envolver.
  Future<DriverVehicle?> getVehicle() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'drivers/me/vehicle',
      );

      final data = response.data;

      if (data == null) {
        throw Exception('El backend devolvió una respuesta vacía.');
      }

      return DriverVehicle.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  /// `GET drivers/me/documents` — el expediente completo del
  /// conductor (puede incluir tipos legacy). A diferencia de
  /// `getDriverProfile`/`getVehicle`, Backend nunca devuelve 404 aquí
  /// — una lista vacía ya representa "sin documentos". Cualquier
  /// `DioException` se relanza sin envolver.
  Future<List<DriverDocument>> getMyDocuments() async {
    final response = await _dio.get<List<dynamic>>('drivers/me/documents');

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return data
        .map((item) => DriverDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Orquesta `getMe()` + `getDriverProfile()` (+ `getVehicle()` y,
  /// si el vehículo ya existe, `getMyDocuments()`, para distinguir
  /// Paso 3 de Paso 4/5 — ver `DriverSessionKind`) en la única fuente
  /// de verdad de routing que usan Splash y Login:
  /// `resolveDriverApplicationState`.
  ///
  /// DECISIÓN DE PRODUCTO MVP (`DRIVER-ONBOARDING-R3.3`): siempre se
  /// consulta `drivers/me`, sin importar `isPhoneVerified`. La
  /// verificación OTP queda diferida hasta un proveedor SMS real
  /// (`OTP-R3`); no bloquea el onboarding de Driver.
  ///
  /// `DRIVER-ONBOARDING-R3.8`: `REJECTED` también carga `vehicle`/
  /// `documents` (mismo GET que `DRAFT`) para poder construir
  /// "Correcciones requeridas" con granularidad real. La primera vez
  /// que se detecta `REJECTED` se marca el contexto de reenvío local
  /// (`markResubmissionContext()`); ese marcador (no la Backend) es
  /// lo único que permite reconocer un `DRAFT` ya corregido como
  /// "todavía en ciclo de reenvío" tras cerrar y reabrir la app.
  ///
  /// `DRIVER-ONBOARDING-R3.8B`: además, cualquier estado en el que
  /// Backend confirma inequívocamente que el ciclo terminó
  /// (`PENDING_REVIEW`/`APPROVED`/`SUSPENDED`) limpia el marcador de
  /// forma defensiva — refuerza (idempotente) la limpieza explícita
  /// que ya hace `DriverOnboardingSubmitReviewScreen` tras un submit
  /// exitoso, cubriendo el caso de que ese paso nunca llegara a
  /// ejecutarse (p.ej. la app se cerró a mitad del submit).
  Future<DriverSessionState> resolveSessionState() async {
    final user = await getMe();

    final application = await getDriverProfile();

    final isDraft = application?.status == DriverApplicationStatus.draft;
    final isRejected = application?.status == DriverApplicationStatus.rejected;
    final noLongerNeedsResubmission =
        application?.status == DriverApplicationStatus.pendingReview ||
        application?.status == DriverApplicationStatus.approved ||
        application?.status == DriverApplicationStatus.suspended;

    if (isRejected) {
      await markResubmissionContext(userId: user.id);
    } else if (noLongerNeedsResubmission) {
      await clearResubmissionContext(userId: user.id);
    }

    final needsVehicle = isDraft || isRejected;

    final vehicle = needsVehicle ? await getVehicle() : null;

    final documents = needsVehicle && vehicle != null
        ? await getMyDocuments()
        : null;

    final resubmissionContext = await hasResubmissionContext(userId: user.id);

    return resolveDriverApplicationState(
      user: user,
      application: application,
      vehicle: vehicle,
      documents: documents,
      hasResubmissionContext: resubmissionContext,
    );
  }

  /// `DRIVER-ONBOARDING-R3.8`/`R3.8B`: marca localmente que la
  /// solicitud de [userId] sigue en un ciclo de corrección/reenvío
  /// tras un rechazo. Nunca almacena la razón de rechazo ni ningún
  /// dato del expediente — solo un marcador no sensible, **scoped por
  /// cuenta** (nunca un booleano global: dos conductores en el mismo
  /// dispositivo no deben compartirlo). Sobrevive cerrar y reabrir la
  /// app y cerrar/volver a iniciar sesión con la misma cuenta —
  /// `clearSession()` (logout) deliberadamente **no** lo borra, ya
  /// que terminar la sesión no termina el ciclo administrativo de la
  /// solicitud. Se limpia explícitamente tras un reenvío exitoso
  /// (`clearResubmissionContext()`, llamado desde
  /// `DriverOnboardingSubmitReviewScreen` y, defensivamente, desde
  /// `resolveSessionState()` en cualquier estado terminal).
  Future<void> markResubmissionContext({required String userId}) async {
    await _storage.write(
      key: StorageKeys.driverResubmissionContext(userId),
      value: 'true',
    );
  }

  Future<bool> hasResubmissionContext({required String userId}) async {
    final value = await _storage.read(
      key: StorageKeys.driverResubmissionContext(userId),
    );

    return value == 'true';
  }

  Future<void> clearResubmissionContext({required String userId}) async {
    await _storage.delete(key: StorageKeys.driverResubmissionContext(userId));
  }

  /// `POST auth/otp/request` — preparado para cuando exista
  /// transporte SMS real (`OTP-R3`, hoy pausado). Ninguna pantalla
  /// de este checkpoint lo invoca todavía: Backend genera/hashea el
  /// código pero no hay proveedor que lo entregue al teléfono.
  Future<void> requestPhoneOtp(String phoneE164) async {
    await _dio.post<Map<String, dynamic>>(
      'auth/otp/request',
      data: {'phoneE164': phoneE164},
    );
  }

  /// `POST auth/otp/verify` — mismo estado que [requestPhoneOtp]:
  /// preparado, no invocado por ninguna pantalla todavía.
  Future<void> verifyPhoneOtp({
    required String phoneE164,
    required String code,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      'auth/otp/verify',
      data: {'phoneE164': phoneE164, 'code': code},
    );
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>('auth/logout');
    } on DioException {
      // El logout remoto es best-effort.
      //
      // Si el access token ya venció, la sesión fue
      // revocada o el backend no está disponible,
      // igualmente debemos cerrar la sesión local.
    } finally {
      await clearSession();
    }
  }

  /// `DRIVER-ONBOARDING-R3.8B`: deliberadamente **no** toca el
  /// marcador de reenvío (`driverResubmissionContext`) — está scoped
  /// por `userId`, así que nunca se filtra entre cuentas distintas en
  /// el mismo dispositivo, y cerrar sesión no termina el ciclo
  /// administrativo de la solicitud (ver `markResubmissionContext`).
  /// Solo borra credenciales/identificadores de sesión.
  Future<void> clearSession() async {
    await _storage.delete(key: StorageKeys.accessToken);

    await _storage.delete(key: StorageKeys.refreshToken);

    await _storage.delete(key: StorageKeys.sessionId);
  }
}
