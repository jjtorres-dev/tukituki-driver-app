import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final driverOperationsRepositoryProvider = Provider<DriverOperationsRepository>(
  (ref) {
    return DriverOperationsRepository(ref.watch(dioProvider));
  },
);

class DriverOperationsRepository {
  DriverOperationsRepository(this._dio);

  final Dio _dio;

  Future<String> goOnline() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/online',
    );

    return _readStatus(response.data);
  }

  Future<String> goOffline() async {
    final response = await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/offline',
    );

    return _readStatus(response.data);
  }

  Future<String> getStatus() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'drivers/me/operational-status',
    );

    return _readStatus(response.data);
  }

  Future<String> heartbeat() async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/operational-status/heartbeat',
    );

    return _readStatus(response.data);
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

  String _readStatus(Map<String, dynamic>? data) {
    return data?['status']?.toString() ?? 'UNKNOWN';
  }
}
