import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_ride_payment.dart';

final driverPaymentsRepositoryProvider =
    Provider<DriverPaymentsRepository>((ref) {
  return DriverPaymentsRepository(
    ref.watch(dioProvider),
  );
});

class DriverPaymentsRepository {
  DriverPaymentsRepository(this._dio);

  final Dio _dio;

  Future<DriverRidePayment> getPayment(
    String rideId,
  ) async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/payment',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'No se pudo consultar el pago.',
      );
    }

    return DriverRidePayment.fromJson(data);
  }

  Future<DriverRidePayment> confirmCashPayment({
    required String rideId,
    required String cashReceived,
  }) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'drivers/me/rides/$rideId/payment/cash/confirm',
      data: {
        'cashReceived': cashReceived,
        'notes':
            'Pago en efectivo confirmado desde Driver App',
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend no devolvió el pago confirmado.',
      );
    }

    return DriverRidePayment.fromJson(data);
  }
}