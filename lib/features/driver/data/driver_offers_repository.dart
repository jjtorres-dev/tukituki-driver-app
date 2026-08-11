import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/driver_pending_proposal.dart';
import '../domain/driver_ride_offer.dart';

final driverOffersRepositoryProvider = Provider<DriverOffersRepository>((ref) {
  return DriverOffersRepository(ref.watch(dioProvider));
});

class DriverOffersRepository {
  DriverOffersRepository(this._dio);

  final Dio _dio;

  Future<List<DriverRideOffer>> getActiveOffers() async {
    final response = await _dio.get<List<dynamic>>(
      'drivers/me/ride-offers/active',
    );

    final data = response.data ?? const <dynamic>[];

    final offers = <DriverRideOffer>[];

    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      final json = Map<String, dynamic>.from(item);

      final offer = DriverRideOffer.fromJson(json);

      // El endpoint es de ofertas vigentes,
      // pero mantenemos una protección extra.
      if (offer.status == 'OFFERED') {
        offers.add(offer);
      }
    }

    offers.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));

    return offers;
  }

  Future<DriverRideOffer> getOffer(String offerId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'drivers/me/ride-offers/$offerId',
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverRideOffer.fromJson(data);
  }

  Future<DriverRideOffer> acceptOffer(String offerId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/ride-offers/$offerId/accept',
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverRideOffer.fromJson(data);
  }

  Future<DriverRideOffer> counterOffer(
    String offerId,
    String proposedFare,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'drivers/me/ride-offers/$offerId/counter-offer',
      data: {'proposedFare': proposedFare},
    );

    final data = response.data;

    if (data == null) {
      throw Exception('El backend devolvió una respuesta vacía.');
    }

    return DriverRideOffer.fromJson(data);
  }

  Future<void> rejectOffer(String offerId) async {
    await _dio.post<void>('drivers/me/ride-offers/$offerId/reject');
  }

  /// Propuestas PROPOSED del conductor, pendientes de que el
  /// pasajero decida. Es la fuente de verdad recuperable
  /// después de un restart de la app (0..N elementos).
  Future<List<DriverPendingProposal>> getPendingProposals() async {
    final response = await _dio.get<List<dynamic>>(
      'drivers/me/ride-offers/proposals/pending',
    );

    final data = response.data ?? const <dynamic>[];

    final proposals = <DriverPendingProposal>[];

    for (final item in data) {
      if (item is! Map) {
        continue;
      }

      proposals.add(
        DriverPendingProposal.fromJson(Map<String, dynamic>.from(item)),
      );
    }

    return proposals;
  }
}
