import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_document.dart';

/// Categoría de Storage usada por la foto de perfil de Driver
/// (`StorageCategory.DRIVER_PROFILE_PHOTO` en Backend).
const String driverProfilePhotoStorageCategory = 'DRIVER_PROFILE_PHOTO';

/// Categorías de Storage del Paso 4 ("Tus documentos") — mismos
/// nombres que `DriverDocumentType`, mapeo 1:1 explícito en Backend
/// (`storage-category.policy.ts`).
const String driverLicenseStorageCategory = 'DRIVER_LICENSE';
const String soatStorageCategory = 'SOAT';
const String vehicleRegistrationStorageCategory = 'VEHICLE_REGISTRATION';

/// Mapea un [DriverDocumentType] objetivo del Paso 4 a su categoría
/// real de Storage. Solo cubre los 3 tipos que este onboarding puede
/// crear — los legacy nunca se suben desde aquí.
String storageCategoryForDriverDocumentType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return driverLicenseStorageCategory;
    case DriverDocumentType.soat:
      return soatStorageCategory;
    case DriverDocumentType.vehicleRegistration:
      return vehicleRegistrationStorageCategory;
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      throw ArgumentError(
        'No hay categoría de Storage para el tipo de documento $type',
      );
  }
}

final driverStorageRepositoryProvider = Provider<DriverStorageRepository>((
  ref,
) {
  return DriverStorageRepository(ref.watch(dioProvider));
});

/// Resultado de `POST storage/uploads/presign`.
class DriverPresignedUpload {
  const DriverPresignedUpload({
    required this.objectKey,
    required this.uploadUrl,
    required this.contentType,
  });

  final String objectKey;
  final String uploadUrl;

  /// `requiredHeaders['Content-Type']` tal como lo devuelve Backend
  /// — el único header exigido por la URL presignada.
  final String contentType;
}

/// `POST storage/uploads/presign` + `POST storage/uploads/complete`
/// contra el Backend de TukiTuki (autenticado, vía `dioProvider`).
///
/// El `PUT` real al bucket NO vive aquí — ver `DriverPhotoUploader`,
/// que usa un `Dio` aislado sin `AuthInterceptor` para no filtrar el
/// Bearer token de TukiTuki a un dominio de bucket externo.
class DriverStorageRepository {
  DriverStorageRepository(this._dio);

  final Dio _dio;

  Future<DriverPresignedUpload> presignUpload({
    required String category,
    required String contentType,
    required int fileSize,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'storage/uploads/presign',
      data: {
        'category': category,
        'contentType': contentType,
        'fileSize': fileSize,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    final objectKey = data['objectKey'] as String?;
    final uploadUrl = data['uploadUrl'] as String?;
    final requiredHeaders = data['requiredHeaders'] as Map<String, dynamic>?;
    final requiredContentType = requiredHeaders?['Content-Type'] as String?;

    if (objectKey == null ||
        objectKey.isEmpty ||
        uploadUrl == null ||
        uploadUrl.isEmpty ||
        requiredContentType == null ||
        requiredContentType.isEmpty) {
      throw Exception('La respuesta de presign de Storage es inválida.');
    }

    return DriverPresignedUpload(
      objectKey: objectKey,
      uploadUrl: uploadUrl,
      contentType: requiredContentType,
    );
  }

  Future<void> completeUpload({
    required String category,
    required String objectKey,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'storage/uploads/complete',
      data: {'category': category, 'objectKey': objectKey},
    );

    if (response.data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }
  }
}
