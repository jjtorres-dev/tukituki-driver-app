import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_application.dart';

final driverProfileRepositoryProvider = Provider<DriverProfileRepository>((
  ref,
) {
  return DriverProfileRepository(ref.watch(dioProvider));
});

/// `POST`/`PATCH drivers/me` — Paso 2 del onboarding ("Sobre ti") y su
/// edición desde el Paso 5 ("Revisar y enviar", `DRIVER-ONBOARDING-
/// R3.7`). También expone `submitApplication()` (`POST drivers/me/
/// submit`, Paso 5 real): mismo dueño de dominio que el resto de
/// acciones sobre `DriverProfile`, sin crear un repository nuevo.
class DriverProfileRepository {
  DriverProfileRepository(this._dio);

  final Dio _dio;

  /// Nunca envía `address` (el onboarding nuevo no la pide) ni
  /// `photoUrl` (la foto se sube aparte vía Storage — ver
  /// `DriverStorageRepository` — y Backend la persiste como
  /// `photoObjectKey`, no por este DTO).
  Future<DriverApplication> createProfile({
    required String firstName,
    required String lastName,
    required IdentityDocumentType documentType,
    required String documentNumber,
    required String birthDate,
    String? email,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me',
      data: {
        'firstName': firstName,
        'lastName': lastName,
        'documentType': documentType.value,
        'documentNumber': documentNumber,
        'birthDate': birthDate,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverApplication.fromJson(data);
  }

  /// `PATCH drivers/me` — edición desde "Revisar y enviar" mientras la
  /// solicitud sigue en `DRAFT`/`REJECTED` (`UpdateDriverProfileDto` es
  /// un `PartialType` de los mismos campos de `createProfile`, sin
  /// `address` ni `photoUrl`, mismo criterio que arriba).
  Future<DriverApplication> updateProfile({
    required String firstName,
    required String lastName,
    required IdentityDocumentType documentType,
    required String documentNumber,
    required String birthDate,
    String? email,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me',
      data: {
        'firstName': firstName,
        'lastName': lastName,
        'documentType': documentType.value,
        'documentNumber': documentNumber,
        'birthDate': birthDate,
        if (email != null && email.isNotEmpty) 'email': email,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverApplication.fromJson(data);
  }

  /// `POST drivers/me/submit` — Paso 5 real ("Revisar y enviar").
  /// Backend no espera body (`DriversController.submitMyProfile` no
  /// declara `@Body()`); nunca reenviar los datos del perfil aquí.
  Future<DriverApplication> submitApplication() async {
    final response = await _dio.post<Map<String, dynamic>>('drivers/me/submit');

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverApplication.fromJson(data);
  }
}
