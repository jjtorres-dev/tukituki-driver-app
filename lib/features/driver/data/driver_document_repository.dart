import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_document.dart';

final driverDocumentRepositoryProvider = Provider<DriverDocumentRepository>((
  ref,
) {
  return DriverDocumentRepository(ref.watch(dioProvider));
});

/// `PATCH drivers/me/documents/:id` — metadata del Paso 4 ("Tus
/// documentos"). `GET drivers/me/documents` vive en `AuthRepository`
/// (`getMyDocuments()`), no aquí: mismo patrón exacto que
/// `getDriverProfile()`/`getVehicle()` en R3.4/R3.5 — una única
/// fuente de lectura, reutilizada tanto por el routing como por la
/// propia pantalla al abrir Paso 4, sin duplicar la llamada.
class DriverDocumentRepository {
  DriverDocumentRepository(this._dio);

  final Dio _dio;

  /// `expiresAt` es opcional porque `VEHICLE_REGISTRATION` no lo
  /// exige (a diferencia de `DRIVER_LICENSE`/`SOAT`).
  Future<DriverDocument> updateDocumentMetadata({
    required String documentId,
    required String documentNumber,
    required String issuedAt,
    String? expiresAt,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/documents/$documentId',
      data: {
        'documentNumber': documentNumber,
        'issuedAt': issuedAt,
        'expiresAt': ?expiresAt,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverDocument.fromJson(data);
  }
}
