import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_daily_stats.dart';
import '../domain/driver_operational_state.dart';

final driverOperationsRepositoryProvider = Provider<DriverOperationsRepository>(
  (ref) {
    return DriverOperationsRepository(ref.watch(dioProvider));
  },
);

class DriverOperationsRepository {
  DriverOperationsRepository(this._dio);

  final Dio _dio;

  Future<DriverOperationalState> goOnline() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/online',
    );

    return _readState(response.data);
  }

  Future<DriverOperationalState> goOffline() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/offline',
    );

    return _readState(response.data);
  }

  Future<DriverOperationalState> getStatus() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'drivers/me/operational-status',
    );

    return _readState(response.data);
  }

  Future<DriverOperationalState> heartbeat() async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/operational-status/heartbeat',
    );

    return _readState(response.data);
  }

  Future<DriverDailyStats> getDailyStats() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'drivers/me/stats/daily',
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverDailyStats.fromJson(data);
  }

  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
    double? accuracy,
  }) async {
    final data = <String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
    };

    if (heading != null && heading.isFinite && heading >= 0 && heading <= 360) {
      data['heading'] = heading;
    }

    if (speed != null && speed.isFinite && speed >= 0) {
      data['speed'] = speed;
    }

    if (accuracy != null &&
        accuracy.isFinite &&
        accuracy >= 0.1 &&
        accuracy <= 1000) {
      data['accuracy'] = accuracy;
    }

    await _dio.put<Map<String, dynamic>>('drivers/me/location', data: data);
  }

  /// Parsing defensivo: si Backend solo devuelve `status`, el resto
  /// de campos queda en null. Si devuelve el objeto completo
  /// (id, connectedAt, lastSeenAt, ...), se conserva todo.
  DriverOperationalState _readState(Map<String, dynamic>? data) {
    if (data == null) {
      return const DriverOperationalState(
        status: DriverOperationalStatus.unknown,
      );
    }

    return DriverOperationalState.fromJson(data);
  }
}
