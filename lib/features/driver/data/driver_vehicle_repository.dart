import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_vehicle.dart';

final driverVehicleRepositoryProvider = Provider<DriverVehicleRepository>((
  ref,
) {
  return DriverVehicleRepository(ref.watch(dioProvider));
});

/// `POST/PATCH drivers/me/vehicle` — Paso 3 del onboarding ("Tu
/// mototaxi"). `GET drivers/me/vehicle` vive en `AuthRepository`
/// (`getVehicle()`), no aquí: es la misma "única fuente de lectura"
/// que ya usa `resolveSessionState()` para el routing, mismo patrón
/// que `getDriverProfile()` en R3.4.
class DriverVehicleRepository {
  DriverVehicleRepository(this._dio);

  final Dio _dio;

  /// Nunca envía `vehicleType` (Backend lo fija a `MOTOTAXI`),
  /// `engineNumber`/`chassisNumber` (el onboarding nuevo no los pide)
  /// ni `driverProfileId` (Backend lo resuelve por sesión).
  Future<DriverVehicle> createVehicle({
    required String plate,
    required String brand,
    required String model,
    required int year,
    required String color,
    required VehicleOwnership ownership,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/vehicle',
      data: {
        'plate': plate,
        'brand': brand,
        'model': model,
        'year': year,
        'color': color,
        'ownership': ownership.value,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverVehicle.fromJson(data);
  }

  /// Preparado para la edición de un vehículo `REJECTED` (fuera de
  /// alcance de este checkpoint, ver `decisiones.md`). Ninguna
  /// pantalla lo invoca todavía.
  Future<DriverVehicle> updateVehicle({
    String? plate,
    String? brand,
    String? model,
    int? year,
    String? color,
    VehicleOwnership? ownership,
  }) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/vehicle',
      data: {
        'plate': ?plate,
        'brand': ?brand,
        'model': ?model,
        'year': ?year,
        'color': ?color,
        'ownership': ?ownership?.value,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverVehicle.fromJson(data);
  }
}
