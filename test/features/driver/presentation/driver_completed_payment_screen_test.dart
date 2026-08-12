import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
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
        overrides: [
          driverRidesRepositoryProvider.overrideWithValue(rides),
          driverOperationsRepositoryProvider.overrideWithValue(
            _FakeOperationsRepository(),
          ),
        ],
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

  group('Checkpoint F1: presence heartbeat (restore COMPLETED)', () {
    testWidgets(
      'heartbeat arranca al encontrar un pending real, en foreground',
      (tester) async {
        final rides = _FakeRidesRepository(
          pendingPayments: [_pendingPaymentFixture(rideId: 'ride-1')],
        );
        final operations = _FakeOperationsRepository();

        await _pumpScreen(
          tester,
          rideId: 'ride-1',
          rides: rides,
          operations: operations,
        );
        await tester.pump();

        expect(find.text('¡Viaje completado!'), findsOneWidget);
        expect(operations.heartbeatCalls, 1);

        final baseline = operations.heartbeatCalls;

        await tester.pump(const Duration(seconds: 30));
        expect(operations.heartbeatCalls, baseline + 1);
        expect(operations.updateLocationCalls, 0);
      },
    );

    testWidgets(
      'sin pending real (rideId sin coincidencia): no arranca heartbeat',
      (tester) async {
        final rides = _FakeRidesRepository(
          pendingPayments: [_pendingPaymentFixture(rideId: 'otro-ride')],
        );
        final operations = _FakeOperationsRepository();

        await _pumpScreen(
          tester,
          rideId: 'ride-1',
          rides: rides,
          operations: operations,
        );
        await tester.pump();

        await tester.pump(const Duration(seconds: 90));

        expect(operations.heartbeatCalls, 0);
      },
    );

    testWidgets('heartbeat 400 (OFFLINE real) no rompe el restore', (
      tester,
    ) async {
      final rides = _FakeRidesRepository(
        pendingPayments: [_pendingPaymentFixture(rideId: 'ride-1')],
      );
      final operations = _FakeOperationsRepository(
        heartbeatError: DioException(
          requestOptions: RequestOptions(
            path: 'drivers/me/operational-status/heartbeat',
          ),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(
              path: 'drivers/me/operational-status/heartbeat',
            ),
            statusCode: 400,
          ),
        ),
      );

      await _pumpScreen(
        tester,
        rideId: 'ride-1',
        rides: rides,
        operations: operations,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('¡Viaje completado!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));

      expect(tester.takeException(), isNull);
      expect(find.text('¡Viaje completado!'), findsOneWidget);
    });

    testWidgets('CTA "Cobrar efectivo" desmonta y detiene el heartbeat', (
      tester,
    ) async {
      final rides = _FakeRidesRepository(
        pendingPayments: [_pendingPaymentFixture(rideId: 'ride-9')],
      );
      final operations = _FakeOperationsRepository();

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
              body: Text('CASH_PAYMENT_ROUTE ${state.pathParameters['rideId']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            driverRidesRepositoryProvider.overrideWithValue(rides),
            driverOperationsRepositoryProvider.overrideWithValue(operations),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      expect(operations.heartbeatCalls, 1);

      await tester.tap(find.text('Cobrar efectivo'));
      await tester.pumpAndSettle();

      expect(find.text('CASH_PAYMENT_ROUTE ride-9'), findsOneWidget);

      final afterNavigation = operations.heartbeatCalls;

      await tester.pump(const Duration(seconds: 90));

      expect(operations.heartbeatCalls, afterNavigation);
    });
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String rideId,
  required _FakeRidesRepository rides,
  _FakeOperationsRepository? operations,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        driverRidesRepositoryProvider.overrideWithValue(rides),
        driverOperationsRepositoryProvider.overrideWithValue(
          operations ?? _FakeOperationsRepository(),
        ),
      ],
      child: MaterialApp(home: DriverCompletedPaymentScreen(rideId: rideId)),
    ),
  );
}

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository({this.heartbeatError}) : super(Dio());

  /// Fija a propósito (no cola): igual criterio que en
  /// `driver_cash_payment_screen_test.dart`.
  DioException? heartbeatError;

  int heartbeatCalls = 0;
  int updateLocationCalls = 0;

  @override
  Future<DriverOperationalState> heartbeat() async {
    heartbeatCalls++;

    final error = heartbeatError;

    if (error != null) {
      throw error;
    }

    return const DriverOperationalState(
      status: DriverOperationalStatus.available,
    );
  }

  @override
  Future<void> updateLocation({
    required double latitude,
    required double longitude,
    double? heading,
    double? speed,
    double? accuracy,
  }) async {
    updateLocationCalls++;
  }
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
