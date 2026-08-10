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
}
