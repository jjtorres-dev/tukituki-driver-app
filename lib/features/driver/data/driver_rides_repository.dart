import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_active_ride.dart';
import '../domain/driver_ride_completion.dart';

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
}
