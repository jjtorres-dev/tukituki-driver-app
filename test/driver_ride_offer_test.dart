import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/domain/driver_ride_offer.dart';

void main() {
  DriverRideOffer offer({
    required String passengerFare,
    required String proposedFare,
  }) {
    return DriverRideOffer(
      id: 'offer-1',
      rideId: 'ride-1',
      status: 'PROPOSED',
      distanceToOriginMeters: 100,
      estimatedFare: '7.00',
      passengerOfferFare: passengerFare,
      proposedFare: proposedFare,
      proposedAt: DateTime.utc(2026),
      currency: 'PEN',
      originAddress: 'Origen',
      destinationAddress: 'Destino',
      expiresAt: DateTime.utc(2026, 1, 1, 0, 1),
    );
  }

  group('DriverRideOffer.isCounterOffer', () {
    test('7 / 7 no es contraoferta', () {
      expect(
        offer(passengerFare: '7.00', proposedFare: '7').isCounterOffer,
        isFalse,
      );
    });

    test('7 / 6 es contraoferta', () {
      expect(
        offer(passengerFare: '7.00', proposedFare: '6.00').isCounterOffer,
        isTrue,
      );
    });

    test('7 / 8 es contraoferta', () {
      expect(
        offer(passengerFare: '7.00', proposedFare: '8.00').isCounterOffer,
        isTrue,
      );
    });

    test('no clasifica valores que no se pueden parsear con seguridad', () {
      expect(
        offer(passengerFare: '7.00', proposedFare: 'NaN').isCounterOffer,
        isFalse,
      );
      expect(
        offer(passengerFare: '7.000', proposedFare: '8.00').isCounterOffer,
        isFalse,
      );
    });
  });

  group('DriverRideOffer.fromJson lat/lng (G4B2)', () {
    Map<String, dynamic> jsonWith({
      Map<String, dynamic>? origin,
      Map<String, dynamic>? destination,
    }) {
      return {
        'id': 'offer-1',
        'rideId': 'ride-1',
        'status': 'OFFERED',
        'distanceToOriginMeters': 500,
        'estimatedFare': '7.00',
        'passengerOfferFare': '7.00',
        'currency': 'PEN',
        'expiresAt': '2030-01-01T00:00:00.000Z',
        'ride': {
          'origin': origin ?? {'address': 'Origen'},
          'destination': destination ?? {'address': 'Destino'},
        },
      };
    }

    test('parsea latitude/longitude reales de origin/destination', () {
      final offer = DriverRideOffer.fromJson(
        jsonWith(
          origin: {
            'address': 'Origen',
            'latitude': -6.4879,
            'longitude': -76.3601,
          },
          destination: {
            'address': 'Destino',
            'latitude': -6.5,
            'longitude': -76.4,
          },
        ),
      );

      expect(offer.originLatitude, -6.4879);
      expect(offer.originLongitude, -76.3601);
      expect(offer.destinationLatitude, -6.5);
      expect(offer.destinationLongitude, -76.4);
      expect(offer.hasValidRouteCoordinates, isTrue);
    });

    test('acepta enteros (num) y los convierte a double sin crashear', () {
      final offer = DriverRideOffer.fromJson(
        jsonWith(
          origin: {'address': 'Origen', 'latitude': -6, 'longitude': -76},
        ),
      );

      expect(offer.originLatitude, -6.0);
      expect(offer.originLongitude, -76.0);
    });

    test(
      'coordenadas ausentes o no numéricas quedan null, sin crashear ni inventar 0.0',
      () {
        final missing = DriverRideOffer.fromJson(jsonWith());

        expect(missing.originLatitude, isNull);
        expect(missing.originLongitude, isNull);
        expect(missing.destinationLatitude, isNull);
        expect(missing.destinationLongitude, isNull);
        expect(missing.hasValidRouteCoordinates, isFalse);

        final invalid = DriverRideOffer.fromJson(
          jsonWith(
            origin: {
              'address': 'Origen',
              'latitude': 'no-es-numero',
              'longitude': null,
            },
          ),
        );

        expect(invalid.originLatitude, isNull);
        expect(invalid.originLongitude, isNull);
        expect(invalid.hasValidRouteCoordinates, isFalse);
      },
    );

    test(
      'hasValidRouteCoordinates es false si solo origin o solo destination tienen coordenadas',
      () {
        final onlyOrigin = DriverRideOffer.fromJson(
          jsonWith(
            origin: {
              'address': 'Origen',
              'latitude': -6.48,
              'longitude': -76.36,
            },
          ),
        );

        expect(onlyOrigin.hasValidRouteCoordinates, isFalse);
      },
    );
  });

  group('DriverRideOffer.fromJson passengerFirstName (G4B-R2)', () {
    Map<String, dynamic> jsonWith({Object? passenger}) {
      return {
        'id': 'offer-1',
        'rideId': 'ride-1',
        'status': 'OFFERED',
        'distanceToOriginMeters': 500,
        'estimatedFare': '7.00',
        'passengerOfferFare': '7.00',
        'currency': 'PEN',
        'expiresAt': '2030-01-01T00:00:00.000Z',
        'ride': {
          'passenger': passenger,
          'origin': {'address': 'Origen'},
          'destination': {'address': 'Destino'},
        },
      };
    }

    test('parsea el firstName real cuando Backend lo entrega', () {
      final offer = DriverRideOffer.fromJson(
        jsonWith(passenger: {'firstName': 'Carlos'}),
      );

      expect(offer.passengerFirstName, 'Carlos');
    });

    test('passenger ausente (null): passengerFirstName queda null, sin placeholder', () {
      final offer = DriverRideOffer.fromJson(jsonWith(passenger: null));

      expect(offer.passengerFirstName, isNull);
    });

    test('firstName vacío o solo espacios: se trata como null, no como string vacío', () {
      final empty = DriverRideOffer.fromJson(
        jsonWith(passenger: {'firstName': ''}),
      );
      final blank = DriverRideOffer.fromJson(
        jsonWith(passenger: {'firstName': '   '}),
      );

      expect(empty.passengerFirstName, isNull);
      expect(blank.passengerFirstName, isNull);
    });

    test('firstName con espacios extra se recorta (trim)', () {
      final offer = DriverRideOffer.fromJson(
        jsonWith(passenger: {'firstName': '  Carlos  '}),
      );

      expect(offer.passengerFirstName, 'Carlos');
    });

    test('firstName no-string no crashea, queda null', () {
      final offer = DriverRideOffer.fromJson(
        jsonWith(passenger: {'firstName': 12345}),
      );

      expect(offer.passengerFirstName, isNull);
    });
  });
}
