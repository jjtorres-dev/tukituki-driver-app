import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_application.dart';

final driverProfileRepositoryProvider = Provider<DriverProfileRepository>((
  ref,
) {
  return DriverProfileRepository(ref.watch(dioProvider));
});

/// `POST drivers/me` — Paso 2 del onboarding ("Sobre ti"). Crea el
/// `DriverProfile` en estado `DRAFT`.
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
}
