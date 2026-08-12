import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_pending_payment.dart';
import 'package:driver/features/driver/domain/driver_ride_payment.dart';

void main() {
  group('DriverPendingPayment.fromJson', () {
    test('parsea el contrato real de pending-payments', () {
      final payment = DriverPendingPayment.fromJson({
        'rideId': 'ride-1',
        'rideStatus': 'COMPLETED',
        'originAddress': 'Jr. Lima 250',
        'destinationAddress': 'Plaza de Armas',
        'completedAt': '2026-08-10T12:00:00.000Z',
        'finalFare': '8.00',
        'currency': 'PEN',
        'payment': {
          'id': 'payment-1',
          'rideId': 'ride-1',
          'method': 'CASH',
          'status': 'PENDING',
          'amountDue': '8.00',
          'grossAmount': '8.00',
          'discountAmount': '0.00',
          'currency': 'PEN',
        },
      });

      expect(payment.rideId, 'ride-1');
      expect(payment.finalFare, '8.00');
      expect(payment.payment.method, 'CASH');
      expect(payment.payment.status, 'PENDING');
      expect(payment.payment.amountDue, '8.00');
    });

    test('finalFare null se preserva (contrato nullable real)', () {
      final payment = DriverPendingPayment.fromJson({
        'rideId': 'ride-1',
        'rideStatus': 'COMPLETED',
        'originAddress': 'Jr. Lima 250',
        'destinationAddress': 'Plaza de Armas',
        'completedAt': null,
        'finalFare': null,
        'currency': 'PEN',
        'payment': {
          'method': 'CASH',
          'status': 'PENDING',
          'amountDue': '8.00',
          'grossAmount': '8.00',
          'discountAmount': '0.00',
          'currency': 'PEN',
        },
      });

      expect(payment.finalFare, isNull);
      expect(payment.completedAt, isNull);
    });
  });

  group('selectMostRecentCashPendingPayment', () {
    DriverPendingPayment fixture({
      required String rideId,
      required String method,
      required String status,
    }) {
      return DriverPendingPayment(
        rideId: rideId,
        rideStatus: 'COMPLETED',
        originAddress: 'Origen',
        destinationAddress: 'Destino',
        completedAt: DateTime.utc(2026, 8, 10),
        finalFare: '8.00',
        currency: 'PEN',
        payment: DriverRidePayment(
          id: 'payment-$rideId',
          rideId: rideId,
          method: method,
          status: status,
          amountDue: '8.00',
          grossAmount: '8.00',
          discountAmount: '0.00',
          currency: 'PEN',
        ),
      );
    }

    test('selecciona el primer CASH+PENDING sin reordenar', () {
      final recent = fixture(rideId: 'ride-recent', method: 'CASH', status: 'PENDING');
      final old = fixture(rideId: 'ride-old', method: 'CASH', status: 'PENDING');

      final selected = selectMostRecentCashPendingPayment([recent, old]);

      expect(selected?.rideId, 'ride-recent');
    });

    test('ignora métodos distintos de CASH aunque estén PENDING', () {
      final yape = fixture(rideId: 'ride-yape', method: 'YAPE', status: 'PENDING');
      final cash = fixture(rideId: 'ride-cash', method: 'CASH', status: 'PENDING');

      final selected = selectMostRecentCashPendingPayment([yape, cash]);

      expect(selected?.rideId, 'ride-cash');
    });

    test('ignora CASH que no está PENDING', () {
      final paid = fixture(rideId: 'ride-paid', method: 'CASH', status: 'PAID');

      final selected = selectMostRecentCashPendingPayment([paid]);

      expect(selected, isNull);
    });

    test('retorna null si la lista está vacía', () {
      expect(selectMostRecentCashPendingPayment(const []), isNull);
    });
  });
}
