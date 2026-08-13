import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_active_ride.dart';
import '../domain/driver_cancellation_reason.dart';
import '../domain/driver_pending_payment.dart';
import '../domain/driver_ride_completion.dart';
import '../domain/driver_ride_waiting.dart';

final driverRidesRepositoryProvider = Provider((ref) {
  return DriverRidesRepository(ref.watch(dioProvider));
});

class DriverRidesRepository {
  DriverRidesRepository(this._dio);

  final Dio _dio;

  Future<DriverActiveRide?> getActiveRide() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'drivers/me/rides/active',
      );

      final data = response.data;

      if (data == null) {
        return null;
      }

      return DriverActiveRide.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  /// Rides COMPLETED del conductor con `RidePayment` todavía PENDING,
  /// ya ordenados `completedAt DESC` por Backend. Puede incluir
  /// métodos distintos de CASH: filtrar corresponde a quien consuma
  /// esta lista (Home restore), no a este repositorio.
  Future<List<DriverPendingPayment>> getPendingPayments() async {
    final response = await _dio.get<List<dynamic>>(
      'drivers/me/rides/pending-payments',
    );

    final data = response.data ?? const [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(DriverPendingPayment.fromJson)
        .toList();
  }

  Future<DriverActiveRide> getRide(String rideId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'drivers/me/rides/$rideId',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió '
        'una respuesta vacía.',
      );
    }

    return DriverActiveRide.fromJson(data);
  }

  Future<DriverActiveRide> startArrival(String rideId) async {
    await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/'
      '$rideId/start-arrival',
    );

    return getRide(rideId);
  }

  Future<DriverActiveRide> arrive(String rideId) async {
    await _dio.post<Map<String, dynamic>>('drivers/me/rides/$rideId/arrive');

    return getRide(rideId);
  }

  Future<DriverActiveRide> startRide({
    required String rideId,
    required String code,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/start',
      data: {'code': code},
    );

    return getRide(rideId);
  }

  Future<DriverRideCompletion> completeRide({required String rideId}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/complete',
      data: {
        'completionNotes':
            'Viaje completado '
            'desde Driver App staging',
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend no devolvió '
        'la finalización del viaje.',
      );
    }

    return DriverRideCompletion.fromJson(data);
  }

  /// Cancelación normal por el conductor. Solo válida mientras Backend
  /// considera el Ride cancelable (`DRIVER_ASSIGNED`/`DRIVER_ARRIVING`/
  /// `DRIVER_ARRIVED`); en `IN_PROGRESS` Backend responde 400. No se
  /// modela la respuesta completa (`RideCancellationResponseDto`)
  /// porque esta pantalla no necesita más que la confirmación de que
  /// el POST tuvo éxito: al volver a Home, `getActiveRide()` ya no
  /// devuelve este Ride.
  Future<void> cancelRide({
    required String rideId,
    required DriverCancellationReason reason,
    String? reasonDetail,
  }) async {
    final trimmedDetail = reasonDetail?.trim();

    await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/cancel',
      data: {
        'reason': reason.value,
        if (trimmedDetail != null && trimmedDetail.isNotEmpty)
          'reasonDetail': trimmedDetail,
      },
    );
  }

  // ---------------------------------------------------------------------
  // RideWaiting / Passenger No-show — Checkpoint G2
  // ---------------------------------------------------------------------

  /// Inicia (o recupera) la espera del Driver en el punto de recojo.
  /// Backend es idempotente: si ya existe un `RideWaiting` para este
  /// ride, este mismo POST lo recupera en vez de reiniciar el conteo.
  Future<DriverRideWaiting> startRideWaiting(String rideId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/waiting/start',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend no devolvió '
        'el estado de la espera.',
      );
    }

    return DriverRideWaiting.fromJson(data);
  }

  /// `null` únicamente cuando Backend confirma con 404 que no existe
  /// una espera activa para este ride. Cualquier otro error se
  /// relanza: nunca se confunde un fallo de red/servidor con "no
  /// existe espera".
  Future<DriverRideWaiting?> getRideWaiting(String rideId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'drivers/me/rides/$rideId/waiting',
      );

      final data = response.data;

      if (data == null) {
        return null;
      }

      return DriverRideWaiting.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }

      rethrow;
    }
  }

  /// Confirma que el pasajero no se presentó. Backend exige que el
  /// tiempo de espera ya se haya cumplido; si no, responde 409 (que
  /// esta llamada relanza sin envolver) para que quien la invoque
  /// reconcilie con [getRideWaiting]. Sin `reasonDetail` en el MVP:
  /// mismo criterio "sin body" que `arrive()`/`startArrival()`.
  Future<void> reportPassengerNoShow(String rideId) async {
    await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/no-show/passenger',
    );
  }
}
