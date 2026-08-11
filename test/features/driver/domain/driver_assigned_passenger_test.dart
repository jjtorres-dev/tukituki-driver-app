import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_assigned_passenger.dart';

void main() {
  group('AssignedPassenger.fromJson', () {
    test('parsea un passenger completo real', () {
      final passenger = AssignedPassenger.fromJson(const {
        'profileId': 'passenger-1',
        'firstName': 'María',
        'photoUrl': 'https://cdn.tukituki.pe/maria.jpg',
        'ratingAverage': '4.85',
        'ratingCount': 32,
      });

      expect(passenger.profileId, 'passenger-1');
      expect(passenger.firstName, 'María');
      expect(passenger.photoUrl, 'https://cdn.tukituki.pe/maria.jpg');
      expect(passenger.ratingAverage, '4.85');
      expect(passenger.ratingCount, 32);
      expect(passenger.hasRating, isTrue);
    });

    test('photoUrl null no rompe el parsing', () {
      final passenger = AssignedPassenger.fromJson(const {
        'profileId': 'passenger-1',
        'firstName': 'María',
        'photoUrl': null,
        'ratingAverage': '4.85',
        'ratingCount': 32,
      });

      expect(passenger.photoUrl, isNull);
    });

    test('rating sin historial (defaults reales Backend) oculta el rating', () {
      final passenger = AssignedPassenger.fromJson(const {
        'profileId': 'passenger-1',
        'firstName': 'María',
        'ratingAverage': '0.00',
        'ratingCount': 0,
      });

      expect(passenger.hasRating, isFalse);
    });

    test('tryParse devuelve null si el json no es un Map', () {
      expect(AssignedPassenger.tryParse(null), isNull);
      expect(AssignedPassenger.tryParse('not-a-map'), isNull);
    });

    test('tryParse parsea un Map real', () {
      final passenger = AssignedPassenger.tryParse(const {
        'profileId': 'passenger-1',
        'firstName': 'María',
        'ratingAverage': '4.85',
        'ratingCount': 32,
      });

      expect(passenger, isNotNull);
      expect(passenger!.firstName, 'María');
    });
  });
}
