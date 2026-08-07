import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final driverOperationsRepositoryProvider =
    Provider<DriverOperationsRepository>((ref) {
  return DriverOperationsRepository(
    ref.watch(dioProvider),
  );
});

class DriverOperationsRepository {
  DriverOperationsRepository(this._dio);

  final Dio _dio;

  Future<String> goOnline() async {
    final response =
        await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/online',
    );

    return response.data?['status']?.toString() ??
        'UNKNOWN';
  }

  Future<String> goOffline() async {
    final response =
        await _dio.patch<Map<String, dynamic>>(
      'drivers/me/operational-status/offline',
    );

    return response.data?['status']?.toString() ??
        'UNKNOWN';
  }

  Future<String> getStatus() async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'drivers/me/operational-status',
    );

    return response.data?['status']?.toString() ??
        'UNKNOWN';
  }

  Future<void> updateTestLocation() async {
    await _dio.put<Map<String, dynamic>>(
      'drivers/me/location',
      data: {
        'latitude': -6.4877,
        'longitude': -76.3599,
        'heading': 0,
        'speed': 0,
        'accuracy': 8,
      },
    );
  }

  Future<void> heartbeat() async {
    await _dio.post<Map<String, dynamic>>(
      'drivers/me/operational-status/heartbeat',
    );
  }
}