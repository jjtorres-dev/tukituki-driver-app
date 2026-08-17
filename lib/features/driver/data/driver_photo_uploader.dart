import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final driverPhotoUploaderProvider = Provider<DriverPhotoUploader>((ref) {
  return DriverPhotoUploader();
});

/// `PUT` directo a una URL presignada de Railway Storage.
///
/// CRÍTICO DE SEGURIDAD: usa un `Dio()` efímero, sin `AuthInterceptor`
/// — el `dioProvider` compartido agregaría el Bearer token de sesión
/// de TukiTuki a un dominio de bucket externo, filtrando la
/// credencial. Mismo patrón que `_performRefresh` en
/// `core/network/api_client.dart`.
///
/// Envía únicamente el header `Content-Type` exacto que exige el
/// presign — nada de `Authorization`, cookies ni headers adicionales.
///
/// `dioFactory` es inyectable (por defecto crea un `Dio()` nuevo por
/// cada subida) para que los tests puedan sustituirlo por un `Dio`
/// con un `HttpClientAdapter` fijo y así verificar el request real
/// sin red, siguiendo el mismo patrón sin librerías de mocking del
/// resto del repo.
class DriverPhotoUploader {
  DriverPhotoUploader({Dio Function()? dioFactory})
    : _dioFactory = dioFactory ?? Dio.new;

  final Dio Function() _dioFactory;

  Future<void> upload({
    required String uploadUrl,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final dio = _dioFactory();

    await dio.put<void>(
      uploadUrl,
      data: bytes,
      options: Options(headers: {'Content-Type': contentType}),
    );
  }
}
