import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_pending_payment.dart';
import 'package:driver/features/driver/domain/driver_ride_payment.dart';
import 'package:driver/features/driver/presentation/driver_completed_payment_screen.dart';

void main() {
  testWidgets('renderiza "Viaje completado" con los datos del pending payment', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      pendingPayments: [
        _pendingPaymentFixture(rideId: 'ride-1', finalFare: '12.30'),
      ],
    );

    await _pumpScreen(tester, rideId: 'ride-1', rides: rides);
    await tester.pump();

    expect(find.text('¡Viaje completado!'), findsOneWidget);
    expect(find.text('S/ 12.30'), findsOneWidget);
    expect(find.text('Efectivo'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Cobrar efectivo'), findsOneWidget);
  });

  testWidgets('no muestra Passenger (contrato pending-payments no lo expone)', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      pendingPayments: [_pendingPaymentFixture(rideId: 'ride-1')],
    );

    await _pumpScreen(tester, rideId: 'ride-1', rides: rides);
    await tester.pump();

    expect(find.text('¡Viaje completado!'), findsOneWidget);
    expect(find.text('Llegaste al destino con éxito'), findsOneWidget);
  });

  testWidgets('CTA navega a /cash-payment/:rideId', (tester) async {
    final rides = _FakeRidesRepository(
      pendingPayments: [_pendingPaymentFixture(rideId: 'ride-9')],
    );

    final router = GoRouter(
      initialLocation: '/completed-payment/ride-9',
      routes: [
        GoRoute(
          path: '/completed-payment/:rideId',
          builder: (context, state) => DriverCompletedPaymentScreen(
            rideId: state.pathParameters['rideId']!,
          ),
        ),
        GoRoute(
          path: '/cash-payment/:rideId',
          builder: (context, state) => Scaffold(
            body: Text(
              'CASH_PAYMENT_ROUTE ${state.pathParameters['rideId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [driverRidesRepositoryProvider.overrideWithValue(rides)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Cobrar efectivo'));
    await tester.pumpAndSettle();

    expect(find.text('CASH_PAYMENT_ROUTE ride-9'), findsOneWidget);
  });

  testWidgets('rideId sin coincidencia muestra estado seguro (no crash)', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      pendingPayments: [_pendingPaymentFixture(rideId: 'otro-ride')],
    );

    await _pumpScreen(tester, rideId: 'ride-1', rides: rides);
    await tester.pump();

    expect(
      find.textContaining('Ya no encontramos un cobro pendiente'),
      findsOneWidget,
    );
    expect(find.text('Volver al inicio'), findsOneWidget);
  });

  testWidgets('error de red muestra estado recuperable con reintentar', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      pendingPaymentsError: DioException(
        requestOptions: RequestOptions(
          path: 'drivers/me/rides/pending-payments',
        ),
        type: DioExceptionType.connectionError,
      ),
    );

    await _pumpScreen(tester, rideId: 'ride-1', rides: rides);
    await tester.pump();

    expect(
      find.text('No se pudo consultar el cobro pendiente.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String rideId,
  required _FakeRidesRepository rides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [driverRidesRepositoryProvider.overrideWithValue(rides)],
      child: MaterialApp(home: DriverCompletedPaymentScreen(rideId: rideId)),
    ),
  );
}

DriverPendingPayment _pendingPaymentFixture({
  required String rideId,
  String finalFare = '8.00',
  String method = 'CASH',
  String status = 'PENDING',
}) {
  return DriverPendingPayment(
    rideId: rideId,
    rideStatus: 'COMPLETED',
    originAddress: 'Jr. Lima 250',
    destinationAddress: 'Plaza de Armas',
    completedAt: DateTime.utc(2026, 8, 10, 12),
    finalFare: finalFare,
    currency: 'PEN',
    payment: DriverRidePayment(
      id: 'payment-$rideId',
      rideId: rideId,
      method: method,
      status: status,
      amountDue: finalFare,
      grossAmount: finalFare,
      discountAmount: '0.00',
      currency: 'PEN',
    ),
  );
}

class _FakeRidesRepository extends DriverRidesRepository {
  _FakeRidesRepository({
    this.pendingPayments = const [],
    this.pendingPaymentsError,
  }) : super(Dio());

  final List<DriverPendingPayment> pendingPayments;
  final DioException? pendingPaymentsError;

  @override
  Future<List<DriverPendingPayment>> getPendingPayments() async {
    final error = pendingPaymentsError;

    if (error != null) {
      throw error;
    }

    return pendingPayments;
  }
}
