import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_active_ride.dart';

Map<String, dynamic> _baseJson({
  Map<String, dynamic>? origin,
  Map<String, dynamic>? destination,
  Object? passenger = const _Absent(),
  Object? agreedFare = const _Absent(),
  Object? distanceToOriginMeters = const _Absent(),
  Object? paymentMethod = const _Absent(),
}) {
  final json = <String, dynamic>{
    'id': 'ride-1',
    'status': 'DRIVER_ASSIGNED',
    'estimatedFare': '10.00',
    'currency': 'PEN',
    'origin': origin ?? {'address': 'Jr. Lima 250', 'latitude': -6.4877, 'longitude': -76.3599},
    'destination':
        destination ??
        {
          'address': 'Plaza de Armas',
          'latitude': -6.4812,
          'longitude': -76.3655,
        },
    'distanceMeters': 3200,
    'estimatedDurationSeconds': 720,
  };

  if (passenger is! _Absent) {
    json['passenger'] = passenger;
  }

  if (agreedFare is! _Absent) {
    json['agreedFare'] = agreedFare;
  }

  if (distanceToOriginMeters is! _Absent) {
    json['distanceToOriginMeters'] = distanceToOriginMeters;
  }

  if (paymentMethod is! _Absent) {
    json['paymentMethod'] = paymentMethod;
  }

  return json;
}

class _Absent {
  const _Absent();
}

void main() {
  group('DriverActiveRide.fromJson', () {
    test('A: parsea un passenger real completo', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(
          passenger: const {
            'profileId': 'passenger-1',
            'firstName': 'María',
            'photoUrl': 'https://cdn.tukituki.pe/maria.jpg',
            'ratingAverage': '4.85',
            'ratingCount': 32,
          },
        ),
      );

      expect(ride.passenger, isNotNull);
      expect(ride.passenger!.firstName, 'María');
      expect(ride.passenger!.profileId, 'passenger-1');
    });

    test('B: passenger null no rompe el parsing', () {
      final ride = DriverActiveRide.fromJson(_baseJson(passenger: null));

      expect(ride.passenger, isNull);
    });

    test('B2: passenger ausente del JSON tampoco rompe el parsing', () {
      final json = _baseJson();
      json.remove('passenger');

      final ride = DriverActiveRide.fromJson(json);

      expect(ride.passenger, isNull);
    });

    test('C: rating sin historial se preserva (no se inventa)', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(
          passenger: const {
            'profileId': 'passenger-1',
            'firstName': 'María',
            'ratingAverage': '0.00',
            'ratingCount': 0,
          },
        ),
      );

      expect(ride.passenger!.hasRating, isFalse);
      expect(ride.passenger!.ratingAverage, '0.00');
      expect(ride.passenger!.ratingCount, 0);
    });

    test('D: agreedFare real se usa como displayFare', () {
      final ride = DriverActiveRide.fromJson(_baseJson(agreedFare: '8.00'));

      expect(ride.agreedFare, '8.00');
      expect(ride.displayFare, '8.00');
    });

    test(
      'D2: agreedFare null cae al fallback funcional (estimatedFare)',
      () {
        final ride = DriverActiveRide.fromJson(_baseJson(agreedFare: null));

        expect(ride.agreedFare, isNull);
        expect(ride.displayFare, ride.estimatedFare);
      },
    );

    test('E: distanceToOriginMeters real se parsea', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(distanceToOriginMeters: 650),
      );

      expect(ride.distanceToOriginMeters, 650);
    });

    test('E2: distanceToOriginMeters null se preserva como null', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(distanceToOriginMeters: null),
      );

      expect(ride.distanceToOriginMeters, isNull);
    });

    test('F: coordenadas reales de origin/destination se parsean', () {
      final ride = DriverActiveRide.fromJson(_baseJson());

      expect(ride.originLatitude, -6.4877);
      expect(ride.originLongitude, -76.3599);
      expect(ride.destinationLatitude, -6.4812);
      expect(ride.destinationLongitude, -76.3655);
    });

    test('G: coordenadas fuera de rango se descartan de forma segura', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(
          origin: const {
            'address': 'Origen',
            'latitude': 999.0,
            'longitude': -76.3599,
          },
          destination: const {
            'address': 'Destino',
            'latitude': -6.4812,
            'longitude': 999.0,
          },
        ),
      );

      expect(ride.originLatitude, isNull);
      expect(ride.originLongitude, -76.3599);
      expect(ride.destinationLatitude, -6.4812);
      expect(ride.destinationLongitude, isNull);
    });

    test('G2: coordenadas no numéricas se descartan de forma segura', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(
          origin: const {
            'address': 'Origen',
            'latitude': 'not-a-number',
            'longitude': -76.3599,
          },
        ),
      );

      expect(ride.originLatitude, isNull);
    });

    test('H: paymentMethod real se parsea (antes se perdía en el parseo)', () {
      final ride = DriverActiveRide.fromJson(
        _baseJson(paymentMethod: 'YAPE'),
      );

      expect(ride.paymentMethod, 'YAPE');
    });

    test('H2: paymentMethod ausente queda null, nunca se asume CASH', () {
      final ride = DriverActiveRide.fromJson(_baseJson());

      expect(ride.paymentMethod, isNull);
    });

    test('H3: paymentMethod vacío o no-string se trata como null', () {
      expect(
        DriverActiveRide.fromJson(_baseJson(paymentMethod: '  ')).paymentMethod,
        isNull,
      );
      expect(
        DriverActiveRide.fromJson(_baseJson(paymentMethod: 42)).paymentMethod,
        isNull,
      );
    });
  });
}
