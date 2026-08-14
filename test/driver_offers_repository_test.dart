import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_offers_repository.dart';

/// Adapter fijo, sin red real ni paquetes de mocking adicionales:
/// solo responde con el JSON que cada test le pase, igual que
/// [DriverOffersRepository] lo recibiría de Backend.
class _FixedResponseAdapter implements HttpClientAdapter {
  _FixedResponseAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _offerJson({
  required String id,
  required int distanceMeters,
  required String expiresAtIso,
  String status = 'OFFERED',
}) {
  return {
    'id': id,
    'rideId': 'ride-$id',
    'status': status,
    'distanceToOriginMeters': distanceMeters,
    'estimatedFare': '9.00',
    'passengerOfferFare': '8.00',
    'currency': 'PEN',
    'expiresAt': expiresAtIso,
    'ride': {
      'origin': {'address': 'Origen'},
      'destination': {'address': 'Destino'},
    },
  };
}

void main() {
  group('DriverOffersRepository.getActiveOffers', () {
    test(
      'preserva el orden entregado por Backend (cercanía) y NO reordena por expiresAt',
      () async {
        // offer-near vence DESPUÉS que offer-far: si el repository
        // todavía reordenara por expiresAt ASC (bug detectado en
        // G4A-AUDIT), offer-far terminaría primero.
        final dio = Dio()
          ..httpClientAdapter = _FixedResponseAdapter(
            jsonEncode([
              _offerJson(
                id: 'offer-near',
                distanceMeters: 200,
                expiresAtIso: '2030-01-01T00:10:00.000Z',
              ),
              _offerJson(
                id: 'offer-far',
                distanceMeters: 900,
                expiresAtIso: '2030-01-01T00:01:00.000Z',
              ),
            ]),
          );

        final offers = await DriverOffersRepository(dio).getActiveOffers();

        expect(offers.map((offer) => offer.id).toList(), [
          'offer-near',
          'offer-far',
        ]);
      },
    );

    test('filtra elementos que no están en status OFFERED', () async {
      final dio = Dio()
        ..httpClientAdapter = _FixedResponseAdapter(
          jsonEncode([
            _offerJson(
              id: 'offer-offered',
              distanceMeters: 100,
              expiresAtIso: '2030-01-01T00:05:00.000Z',
            ),
            _offerJson(
              id: 'offer-rejected',
              distanceMeters: 50,
              status: 'REJECTED',
              expiresAtIso: '2030-01-01T00:02:00.000Z',
            ),
          ]),
        );

      final offers = await DriverOffersRepository(dio).getActiveOffers();

      expect(offers.map((offer) => offer.id).toList(), ['offer-offered']);
    });

    test(
      'devuelve TODAS las Offers activas del array, sin límite artificial',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _FixedResponseAdapter(
            jsonEncode(
              List.generate(
                7,
                (index) => _offerJson(
                  id: 'offer-$index',
                  distanceMeters: index * 100,
                  expiresAtIso: '2030-01-01T00:0$index:00.000Z',
                ),
              ),
            ),
          );

        final offers = await DriverOffersRepository(dio).getActiveOffers();

        expect(offers, hasLength(7));
      },
    );
  });
}
