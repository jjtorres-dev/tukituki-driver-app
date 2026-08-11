import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/domain/driver_pending_proposal.dart';

void main() {
  group('DriverPendingProposal.fromJson', () {
    test('parsea el contrato real de Backend, incluidas las coordenadas', () {
      final proposal = DriverPendingProposal.fromJson({
        'offerId': 'offer-1',
        'rideId': 'ride-1',
        'status': 'PROPOSED',
        'proposedFare': '7.50',
        'passengerOfferFare': '7.00',
        'estimatedFare': '7.20',
        'currency': 'PEN',
        'expiresAt': '2026-08-10T10:05:00.000Z',
        'origin': {
          'address': 'Av. Los Pinos 123',
          'latitude': -12.046,
          'longitude': -77.042,
        },
        'destination': {
          'address': 'Jr. Las Rosas 456',
          'latitude': -12.051,
          'longitude': -77.038,
        },
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

      // A: origin/destination completos, con dirección y coordenadas.
      expect(proposal.originAddress, 'Av. Los Pinos 123');
      expect(proposal.originLatitude, -12.046);
      expect(proposal.originLongitude, -77.042);
      expect(proposal.destinationAddress, 'Jr. Las Rosas 456');
      expect(proposal.destinationLatitude, -12.051);
      expect(proposal.destinationLongitude, -77.038);

      expect(proposal.distanceToOriginMeters, 350);
    });

    test('B: latitude/longitude se parsean desde int, double y num', () {
      final proposalWithInts = DriverPendingProposal.fromJson({
        'offerId': 'offer-int',
        'rideId': 'ride-int',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
        'origin': {'address': 'Origen', 'latitude': -12, 'longitude': -77},
        'destination': {
          'address': 'Destino',
          'latitude': -12.5,
          'longitude': -77.5,
        },
      });

      expect(proposalWithInts.originLatitude, -12.0);
      expect(proposalWithInts.originLatitude, isA<double>());
      expect(proposalWithInts.originLongitude, -77.0);
      expect(proposalWithInts.destinationLatitude, -12.5);
      expect(proposalWithInts.destinationLongitude, -77.5);

      final proposalWithStrings = DriverPendingProposal.fromJson({
        'offerId': 'offer-str',
        'rideId': 'ride-str',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
        'origin': {
          'address': 'Origen',
          'latitude': '-12.046',
          'longitude': '-77.042',
        },
      });

      expect(proposalWithStrings.originLatitude, -12.046);
      expect(proposalWithStrings.originLongitude, -77.042);
    });

    test('C: coordenadas ausentes quedan null, sin valores ficticios', () {
      final proposal = DriverPendingProposal.fromJson({
        'offerId': 'offer-4',
        'rideId': 'ride-4',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
        'origin': {'address': 'Solo dirección, sin coordenadas'},
        'destination': 'Destino literal sin mapa',
      });

      expect(proposal.originLatitude, isNull);
      expect(proposal.originLongitude, isNull);
      expect(proposal.destinationLatitude, isNull);
      expect(proposal.destinationLongitude, isNull);

      // D: el address se preserva aunque no haya coordenadas.
      expect(proposal.originAddress, 'Solo dirección, sin coordenadas');
      expect(proposal.destinationAddress, 'Destino literal sin mapa');
    });

    test('sin origin/destination en absoluto no lanza excepción '
        'y deja todo null/por defecto', () {
      final proposal = DriverPendingProposal.fromJson({
        'offerId': 'offer-5',
        'rideId': 'ride-5',
        'passengerOfferFare': '5.00',
        'estimatedFare': '5.00',
      });

      expect(proposal.originLatitude, isNull);
      expect(proposal.originLongitude, isNull);
      expect(proposal.destinationLatitude, isNull);
      expect(proposal.destinationLongitude, isNull);
      expect(proposal.originAddress, 'Origen');
      expect(proposal.destinationAddress, 'Destino');
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
