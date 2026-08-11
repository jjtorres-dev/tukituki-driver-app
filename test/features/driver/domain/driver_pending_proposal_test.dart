import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/domain/driver_pending_proposal.dart';

void main() {
  group('DriverPendingProposal.fromJson', () {
    test('parsea el contrato real de Backend', () {
      final proposal = DriverPendingProposal.fromJson({
        'offerId': 'offer-1',
        'rideId': 'ride-1',
        'status': 'PROPOSED',
        'proposedFare': '7.50',
        'passengerOfferFare': '7.00',
        'estimatedFare': '7.20',
        'currency': 'PEN',
        'expiresAt': '2026-08-10T10:05:00.000Z',
        'origin': {'address': 'Av. Los Pinos 123'},
        'destination': {'address': 'Jr. Las Rosas 456'},
        'distanceToOriginMeters': 350,
      });

      expect(proposal.offerId, 'offer-1');
      expect(proposal.rideId, 'ride-1');
      expect(proposal.status, 'PROPOSED');
      expect(proposal.proposedFare, '7.50');
      expect(proposal.passengerOfferFare, '7.00');
      expect(proposal.estimatedFare, '7.20');
      expect(proposal.currency, 'PEN');
      expect(proposal.expiresAt, DateTime.parse('2026-08-10T10:05:00.000Z'));
      expect(proposal.originAddress, 'Av. Los Pinos 123');
      expect(proposal.destinationAddress, 'Jr. Las Rosas 456');
      expect(proposal.distanceToOriginMeters, 350);
    });

    test('acepta id como alias de offerId', () {
      final proposal = DriverPendingProposal.fromJson({
        'id': 'offer-2',
        'rideId': 'ride-2',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
        'origin': 'Origen literal',
        'destination': 'Destino literal',
      });

      expect(proposal.offerId, 'offer-2');
      expect(proposal.originAddress, 'Origen literal');
      expect(proposal.destinationAddress, 'Destino literal');
    });

    test('lista con 0..N elementos se mapea sin perder ninguno', () {
      final raw = [
        {
          'offerId': 'a',
          'rideId': 'ra',
          'passengerOfferFare': '1.00',
          'estimatedFare': '1.00',
        },
        {
          'offerId': 'b',
          'rideId': 'rb',
          'passengerOfferFare': '2.00',
          'estimatedFare': '2.00',
        },
      ];

      final proposals = raw
          .map((json) => DriverPendingProposal.fromJson(json))
          .toList();

      expect(proposals, hasLength(2));
      expect(proposals[0].offerId, 'a');
      expect(proposals[1].offerId, 'b');
    });

    test('no inventa campos de Passenger que no vienen en el contrato', () {
      final proposal = DriverPendingProposal.fromJson({
        'offerId': 'offer-3',
        'rideId': 'ride-3',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
      });

      expect(proposal.proposedFare, isNull);
      expect(proposal.originAddress, 'Origen');
      expect(proposal.destinationAddress, 'Destino');
    });
  });
}
