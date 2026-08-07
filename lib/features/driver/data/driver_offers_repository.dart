import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_ride_offer.dart';

final driverOffersRepositoryProvider =
    Provider<DriverOffersRepository>((ref) {
  return DriverOffersRepository(
    ref.watch(dioProvider),
  );
});

class DriverOffersRepository {
  DriverOffersRepository(this._dio);

  final Dio _dio;

  Future<List<DriverRideOffer>>
      getActiveOffers() async {
    final response =
        await _dio.get<List<dynamic>>(
      'drivers/me/ride-offers/active',
    );

    final data = response.data ?? [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(DriverRideOffer.fromJson)
        .toList();
  }

  Future<DriverRideOffer> acceptOffer(
    String offerId,
  ) async {
    final response =
        await _dio.post<Map<String, dynamic>>(
      'drivers/me/ride-offers/$offerId/accept',
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    return DriverRideOffer.fromJson(data);
  }
}