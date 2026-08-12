import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_payments_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_active_ride.dart';
import 'package:driver/features/driver/domain/driver_assigned_passenger.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
import 'package:driver/features/driver/domain/driver_ride_payment.dart';
import 'package:driver/features/driver/presentation/driver_cash_payment_screen.dart';

void main() {
  group('Checkpoint E: comprobante PAID', () {
    testWidgets('A/B: header "Pago confirmado" y "¡Pago recibido!"', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('Pago confirmado'), findsOneWidget);
      expect(find.text('¡Pago recibido!'), findsOneWidget);
    });

    testWidgets('C: TOTAL COBRADO usa payment.amountDue', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('TOTAL COBRADO'), findsOneWidget);
      expect(find.text('S/ 17.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('D: método de pago muestra Efectivo para CASH', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('Efectivo'), findsOneWidget);
    });

    testWidgets('E/F: cashReceived y changeGiven reales', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('Efectivo recibido'), findsOneWidget);
      expect(find.text('S/ 20.00'), findsOneWidget);
      expect(find.text('Vuelto entregado'), findsOneWidget);
      expect(find.text('S/ 3.00'), findsOneWidget);
    });

    testWidgets('G/H: estado visual PAGADO, nunca el raw PAID', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('PAGADO'), findsOneWidget);
      expect(find.text('PAID'), findsNothing);
    });

    testWidgets('I/J: CTA es "Volver al inicio", nunca "Finalizar"', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '17.00',
          status: 'PAID',
          cashReceived: '20.00',
          changeGiven: '3.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('Volver al inicio'), findsOneWidget);
      expect(find.text('Finalizar'), findsNothing);
    });

    testWidgets(
      'nullable: cashReceived/changeGiven null no inventan S/ 0.00',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '17.00', status: 'PAID'),
        );

        await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
        await tester.pump();

        expect(find.text('Efectivo recibido'), findsNothing);
        expect(find.text('Vuelto entregado'), findsNothing);
        expect(find.text('S/ 0.00'), findsNothing);
      },
    );

    testWidgets('vuelto real en cero sí se muestra (dato real, no inventado)', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(
          amountDue: '5.00',
          status: 'PAID',
          cashReceived: '5.00',
          changeGiven: '0.00',
        ),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('Vuelto entregado'), findsOneWidget);
      expect(find.text('S/ 0.00'), findsOneWidget);
    });

    testWidgets(
      'CTA "Volver al inicio" no llama confirmCash/getPayment de nuevo',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(
            amountDue: '17.00',
            status: 'PAID',
            cashReceived: '20.00',
            changeGiven: '3.00',
          ),
        );

        final router = GoRouter(
          initialLocation: '/cash-payment/ride-1',
          routes: [
            GoRoute(
              path: '/cash-payment/:rideId',
              builder: (context, state) => DriverCashPaymentScreen(
                rideId: state.pathParameters['rideId']!,
              ),
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const Scaffold(body: Text('HOME_ROUTE')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              driverPaymentsRepositoryProvider.overrideWithValue(payments),
              driverRidesRepositoryProvider.overrideWithValue(
                _FakeRidesRepositoryForCash(),
              ),
              driverOperationsRepositoryProvider.overrideWithValue(
                _FakeOperationsRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        expect(payments.getPaymentCalls, 1);
        expect(payments.confirmCalls, 0);

        await tester.ensureVisible(find.text('Volver al inicio'));
        await tester.tap(find.text('Volver al inicio'));
        await tester.pumpAndSettle();

        expect(find.text('HOME_ROUTE'), findsOneWidget);
        expect(payments.getPaymentCalls, 1);
        expect(payments.confirmCalls, 0);
      },
    );

    testWidgets(
      'CTA "Volver al inicio" limpia el back stack (go, no push)',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(
            amountDue: '17.00',
            status: 'PAID',
            cashReceived: '20.00',
            changeGiven: '3.00',
          ),
        );

        final router = GoRouter(
          initialLocation: '/cash-payment/ride-1',
          routes: [
            GoRoute(
              path: '/cash-payment/:rideId',
              builder: (context, state) => DriverCashPaymentScreen(
                rideId: state.pathParameters['rideId']!,
              ),
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const Scaffold(body: Text('HOME_ROUTE')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              driverPaymentsRepositoryProvider.overrideWithValue(payments),
              driverRidesRepositoryProvider.overrideWithValue(
                _FakeRidesRepositoryForCash(),
              ),
              driverOperationsRepositoryProvider.overrideWithValue(
                _FakeOperationsRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        await tester.ensureVisible(find.text('Volver al inicio'));
        await tester.tap(find.text('Volver al inicio'));
        await tester.pumpAndSettle();

        expect(find.text('HOME_ROUTE'), findsOneWidget);

        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        expect(navigator.canPop(), isFalse);
      },
    );
  });

  group('TOTAL A COBRAR y quick amounts', () {
    testWidgets('A: TOTAL A COBRAR usa amountDue real', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '17.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(find.text('TOTAL A COBRAR'), findsOneWidget);
      // El quick amount "exacto" también coincide con el mismo valor
      // formateado, por eso se acepta más de una coincidencia.
      expect(find.text('S/ 17.00'), findsAtLeastNWidgets(1));
    });

    testWidgets('B: input decimal actualiza el preview', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '10.50');
      await tester.pump();

      expect(find.text('VUELTO A ENTREGAR'), findsOneWidget);
      expect(find.text('S/ 5.50'), findsOneWidget);
    });

    testWidgets('C: quick amounts 5 -> 5/10/20', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(_quickAmountText(tester, 0), 'S/ 5.00');
      expect(_quickAmountText(tester, 1), 'S/ 10.00');
      expect(_quickAmountText(tester, 2), 'S/ 20.00');
    });

    testWidgets('D: quick amounts 17 -> 17/20/50', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '17.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(_quickAmountText(tester, 0), 'S/ 17.00');
      expect(_quickAmountText(tester, 1), 'S/ 20.00');
      expect(_quickAmountText(tester, 2), 'S/ 50.00');
    });

    testWidgets('E: quick amounts 23 -> 23/50/100', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '23.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      expect(_quickAmountText(tester, 0), 'S/ 23.00');
      expect(_quickAmountText(tester, 1), 'S/ 50.00');
      expect(_quickAmountText(tester, 2), 'S/ 100.00');
    });

    testWidgets('tocar un quick amount rellena el input sin confirmar', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('quick-amount-1')));
      await tester.pump();

      expect(find.text('VUELTO A ENTREGAR'), findsOneWidget);
      // total + quick-amount exacto + vuelto comparten el mismo valor.
      expect(find.text('S/ 5.00'), findsAtLeastNWidgets(2));
      expect(payments.confirmCalls, 0);
    });
  });

  group('Vuelto / insuficiente', () {
    testWidgets('F: preview 10 - 5 = 5', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '10.00');
      await tester.pump();

      expect(find.text('VUELTO A ENTREGAR'), findsOneWidget);
      // total + quick-amount exacto + vuelto comparten el mismo valor.
      expect(find.text('S/ 5.00'), findsAtLeastNWidgets(2));
    });

    testWidgets('G: exacto 5 - 5 = 0 es un vuelto válido', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();

      expect(find.text('VUELTO A ENTREGAR'), findsOneWidget);
      expect(find.text('S/ 0.00'), findsOneWidget);
    });

    testWidgets('H/I: insuficiente 3 < 5 no muestra vuelto negativo', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '3.00');
      await tester.pump();

      expect(find.text('Monto insuficiente'), findsOneWidget);
      expect(find.text('Faltan S/ 2.00'), findsOneWidget);
      expect(find.text('VUELTO A ENTREGAR'), findsNothing);
      expect(find.textContaining('-S/'), findsNothing);
    });

    testWidgets('J: CTA deshabilitado con monto insuficiente', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '3.00');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('CTA habilitado con monto suficiente', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });

  group('Confirm dialog', () {
    testWidgets(
      'tocar Confirmar pago muestra el diálogo y NO llama confirmCash',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '5.00'),
        );

        await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
        await tester.pump();

        await tester.enterText(find.byType(TextField), '10.00');
        await tester.pump();

        await tester.ensureVisible(find.text('Confirmar pago'));
        await tester.tap(find.text('Confirmar pago'));
        await tester.pump();

        expect(find.text('¿Confirmar pago recibido?'), findsOneWidget);
        expect(
          find.textContaining('El pasajero entregó S/ 10.00.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Vuelto a entregar: S/ 5.00.'),
          findsOneWidget,
        );
        expect(find.text('Volver'), findsOneWidget);
        expect(find.text('Sí, confirmar pago'), findsOneWidget);
        expect(payments.confirmCalls, 0);
      },
    );

    testWidgets('tocar Volver cierra el diálogo sin confirmar', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '10.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();

      await tester.tap(find.text('Volver'));
      await tester.pump();

      expect(find.text('¿Confirmar pago recibido?'), findsNothing);
      expect(payments.confirmCalls, 0);
      expect(find.text('Cobro en efectivo'), findsOneWidget);
    });
  });

  group('Confirm success / idempotente', () {
    testWidgets(
      'éxito: llama al repository una vez con string de 2 decimales y pasa a PAID',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '5.00'),
          confirmQueue: [
            _paymentFixture(
              amountDue: '5.00',
              status: 'PAID',
              cashReceived: '10.00',
              changeGiven: '5.00',
            ),
          ],
        );

        await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
        await tester.pump();

        await tester.enterText(find.byType(TextField), '10.00');
        await tester.pump();
        await tester.ensureVisible(find.text('Confirmar pago'));
        await tester.tap(find.text('Confirmar pago'));
        await tester.pump();
        await tester.tap(find.text('Sí, confirmar pago'));
        await tester.pump();
        await tester.pump();

        expect(payments.confirmCalls, 1);
        expect(payments.lastCashReceived, '10.00');
        expect(find.text('¡Pago recibido!'), findsOneWidget);
      },
    );

    testWidgets('idempotente: 200 PAID se trata como éxito, no como error', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
        confirmQueue: [
          _paymentFixture(
            amountDue: '5.00',
            status: 'PAID',
            cashReceived: '5.00',
            changeGiven: '0.00',
          ),
        ],
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();
      await tester.tap(find.text('Sí, confirmar pago'));
      await tester.pump();
      await tester.pump();

      expect(find.text('¡Pago recibido!'), findsOneWidget);
      expect(find.textContaining('no puede confirmarse'), findsNothing);
    });
  });

  group('Errores confirmCash', () {
    testWidgets('400: monto insuficiente detectado por Backend', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
        confirmQueue: [
          _dioError(
            statusCode: 400,
            data: const {'message': 'El efectivo recibido no cubre la tarifa final'},
          ),
        ],
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();
      await tester.tap(find.text('Sí, confirmar pago'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('El efectivo no cubre el monto a cobrar.'),
        findsOneWidget,
      );
      expect(find.text('Cobro en efectivo'), findsOneWidget);
    });

    testWidgets('404: pago no encontrado', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
        confirmQueue: [_dioError(statusCode: 404)],
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();
      await tester.tap(find.text('Sí, confirmar pago'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('No encontramos el pago de este viaje.'),
        findsOneWidget,
      );
    });

    testWidgets('409: pago ya no confirmable', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
        confirmQueue: [_dioError(statusCode: 409)],
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();
      await tester.tap(find.text('Sí, confirmar pago'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Este pago ya no puede confirmarse.'), findsOneWidget);
    });

    testWidgets('network/5xx: mensaje de retry, pantalla se mantiene segura', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
        confirmQueue: [_dioNetworkError()],
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '5.00');
      await tester.pump();
      await tester.ensureVisible(find.text('Confirmar pago'));
      await tester.tap(find.text('Confirmar pago'));
      await tester.pump();
      await tester.tap(find.text('Sí, confirmar pago'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('No se pudo conectar con TukiTuki. Inténtalo nuevamente.'),
        findsOneWidget,
      );
      expect(find.text('Cobro en efectivo'), findsOneWidget);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);
    });
  });

  group('Passenger firstName (best-effort)', () {
    testWidgets('subtítulo usa firstName real cuando getRide lo expone', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );
      final rides = _FakeRidesRepositoryForCash(
        rideResult: _activeRideFixture(passengerFirstName: 'Rosa'),
      );

      await _pumpCashPayment(
        tester,
        rideId: 'ride-1',
        payments: payments,
        rides: rides,
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Ingresa el monto que te entregó Rosa'),
        findsOneWidget,
      );
    });

    testWidgets('subtítulo neutral cuando no hay Passenger disponible', (
      tester,
    ) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );

      await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Ingresa el monto que te entregó el pasajero'),
        findsOneWidget,
      );
    });
  });

  group('Checkpoint E: responsive comprobante PAID', () {
    testWidgets('360x640 sin overflow', (tester) async {
      await _pumpPaidResponsive(tester, const Size(360, 640));
    });

    testWidgets('390x844 sin overflow', (tester) async {
      await _pumpPaidResponsive(tester, const Size(390, 844));
    });

    testWidgets('412x915 sin overflow', (tester) async {
      await _pumpPaidResponsive(tester, const Size(412, 915));
    });
  });

  group('Checkpoint F1: presence heartbeat', () {
    testWidgets(
      'heartbeat arranca en collecting (PENDING) y continúa en PAID '
      '(mismo State)',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '5.00'),
          confirmQueue: [
            _paymentFixture(
              amountDue: '5.00',
              status: 'PAID',
              cashReceived: '5.00',
              changeGiven: '0.00',
            ),
          ],
        );
        final operations = _FakeOperationsRepository();

        await _pumpCashPayment(
          tester,
          rideId: 'ride-1',
          payments: payments,
          operations: operations,
        );
        await tester.pump();

        // Inmediato al montar (collecting), antes de confirmar nada.
        expect(operations.heartbeatCalls, 1);

        await tester.enterText(find.byType(TextField), '5.00');
        await tester.pump();
        await tester.ensureVisible(find.text('Confirmar pago'));
        await tester.tap(find.text('Confirmar pago'));
        await tester.pump();
        await tester.tap(find.text('Sí, confirmar pago'));
        await tester.pump();
        await tester.pump();

        expect(find.text('¡Pago recibido!'), findsOneWidget);

        final beforeAdvance = operations.heartbeatCalls;

        // Sigue el mismo mecanismo (mismo State), ya en PAID.
        await tester.pump(const Duration(seconds: 30));
        expect(operations.heartbeatCalls, beforeAdvance + 1);
      },
    );

    testWidgets('nunca llama updateLocation en ninguna rama', (tester) async {
      final payments = _FakePaymentsRepository(
        paymentResult: _paymentFixture(amountDue: '5.00'),
      );
      final operations = _FakeOperationsRepository();

      await _pumpCashPayment(
        tester,
        rideId: 'ride-1',
        payments: payments,
        operations: operations,
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 90));

      expect(operations.updateLocationCalls, 0);
    });

    testWidgets(
      'heartbeat 400 (Driver realmente OFFLINE) no rompe la pantalla de '
      'cobro',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '5.00'),
        );
        final operations = _FakeOperationsRepository(
          heartbeatError: _dioHeartbeatError(400),
        );

        await _pumpCashPayment(
          tester,
          rideId: 'ride-1',
          payments: payments,
          operations: operations,
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Cobro en efectivo'), findsOneWidget);

        await tester.pump(const Duration(seconds: 30));

        expect(tester.takeException(), isNull);
        expect(find.text('Cobro en efectivo'), findsOneWidget);
      },
    );

    testWidgets(
      'CTA "Volver al inicio" desmonta la pantalla y detiene el heartbeat',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(
            amountDue: '17.00',
            status: 'PAID',
            cashReceived: '20.00',
            changeGiven: '3.00',
          ),
        );
        final operations = _FakeOperationsRepository();

        final router = GoRouter(
          initialLocation: '/cash-payment/ride-1',
          routes: [
            GoRoute(
              path: '/cash-payment/:rideId',
              builder: (context, state) => DriverCashPaymentScreen(
                rideId: state.pathParameters['rideId']!,
              ),
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) =>
                  const Scaffold(body: Text('HOME_ROUTE')),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              driverPaymentsRepositoryProvider.overrideWithValue(payments),
              driverRidesRepositoryProvider.overrideWithValue(
                _FakeRidesRepositoryForCash(),
              ),
              driverOperationsRepositoryProvider.overrideWithValue(
                operations,
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        expect(operations.heartbeatCalls, 1);

        await tester.ensureVisible(find.text('Volver al inicio'));
        await tester.tap(find.text('Volver al inicio'));
        await tester.pumpAndSettle();

        expect(find.text('HOME_ROUTE'), findsOneWidget);

        final afterNavigation = operations.heartbeatCalls;

        await tester.pump(const Duration(seconds: 90));

        expect(operations.heartbeatCalls, afterNavigation);
      },
    );

    testWidgets(
      'Cash -> Back -> COMPLETED no es un flujo alcanzable (go() reemplaza '
      'todo el stack; no hay owner de heartbeat que arbitrar entre pantallas)',
      (tester) async {
        final payments = _FakePaymentsRepository(
          paymentResult: _paymentFixture(amountDue: '5.00'),
        );

        final router = GoRouter(
          initialLocation: '/active-ride',
          routes: [
            GoRoute(
              path: '/active-ride',
              builder: (context, state) =>
                  const Scaffold(body: Text('ACTIVE_RIDE_ROUTE')),
            ),
            GoRoute(
              path: '/cash-payment/:rideId',
              builder: (context, state) => DriverCashPaymentScreen(
                rideId: state.pathParameters['rideId']!,
              ),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              driverPaymentsRepositoryProvider.overrideWithValue(payments),
              driverRidesRepositoryProvider.overrideWithValue(
                _FakeRidesRepositoryForCash(),
              ),
              driverOperationsRepositoryProvider.overrideWithValue(
                _FakeOperationsRepository(),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        // Simula exactamente la navegación real: COMPLETED -> Cobrar
        // efectivo usa `context.go`, nunca `push`.
        router.go('/cash-payment/ride-1');
        await tester.pump();
        await tester.pump();

        expect(find.text('Cobro en efectivo'), findsOneWidget);

        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );

        // Sin entradas para volver: el stack quedó reemplazado por
        // completo, así que no existe un "Back" real hacia COMPLETED
        // ni riesgo de dos heartbeats post-ride concurrentes.
        expect(navigator.canPop(), isFalse);
      },
    );
  });
}

DioException _dioHeartbeatError(int statusCode) {
  final requestOptions = RequestOptions(
    path: 'drivers/me/operational-status/heartbeat',
  );

  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
    ),
  );
}

Future<void> _pumpPaidResponsive(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final payments = _FakePaymentsRepository(
    paymentResult: _paymentFixture(
      amountDue: '123.45',
      status: 'PAID',
      cashReceived: '200.00',
      changeGiven: '156.55',
    ),
  );

  await _pumpCashPayment(tester, rideId: 'ride-1', payments: payments);
  await tester.pump();

  expect(tester.takeException(), isNull);
}

Future<void> _pumpCashPayment(
  WidgetTester tester, {
  required String rideId,
  required _FakePaymentsRepository payments,
  DriverRidesRepository? rides,
  _FakeOperationsRepository? operations,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        driverPaymentsRepositoryProvider.overrideWithValue(payments),
        driverRidesRepositoryProvider.overrideWithValue(
          rides ?? _FakeRidesRepositoryForCash(),
        ),
        driverOperationsRepositoryProvider.overrideWithValue(
          operations ?? _FakeOperationsRepository(),
        ),
      ],
      child: MaterialApp(home: DriverCashPaymentScreen(rideId: rideId)),
    ),
  );
}

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository({this.heartbeatError}) : super(Dio());

  /// Fija a propósito (no cola): cada llamada de heartbeat se
  /// comporta igual, suficiente para probar el ciclo best-effort sin
  /// necesitar secuencias distintas por llamada.
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

String? _quickAmountText(WidgetTester tester, int index) {
  final finder = find.byKey(ValueKey('quick-amount-$index'));
  final button = tester.widget<OutlinedButton>(finder);
  final text = button.child;

  if (text is Text) {
    return text.data;
  }

  return null;
}

DriverRidePayment _paymentFixture({
  String id = 'payment-1',
  String rideId = 'ride-1',
  String method = 'CASH',
  String status = 'PENDING',
  required String amountDue,
  String? cashReceived,
  String? changeGiven,
}) {
  return DriverRidePayment(
    id: id,
    rideId: rideId,
    method: method,
    status: status,
    amountDue: amountDue,
    grossAmount: amountDue,
    discountAmount: '0.00',
    cashReceived: cashReceived,
    changeGiven: changeGiven,
    currency: 'PEN',
  );
}

DriverActiveRide _activeRideFixture({String? passengerFirstName}) {
  return DriverActiveRide(
    id: 'ride-1',
    status: 'COMPLETED',
    estimatedFare: '5.00',
    currency: 'PEN',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    distanceMeters: 3200,
    estimatedDurationSeconds: 720,
    passenger: passengerFirstName != null
        ? AssignedPassenger(
            profileId: 'passenger-1',
            firstName: passengerFirstName,
            ratingAverage: '4.85',
            ratingCount: 32,
          )
        : null,
  );
}

DioException _dioError({required int statusCode, Object? data}) {
  final requestOptions = RequestOptions(
    path: 'drivers/me/rides/ride-1/payment/cash/confirm',
  );

  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
      data: data,
    ),
  );
}

DioException _dioNetworkError() {
  return DioException(
    requestOptions: RequestOptions(
      path: 'drivers/me/rides/ride-1/payment/cash/confirm',
    ),
    type: DioExceptionType.connectionError,
  );
}

class _FakePaymentsRepository extends DriverPaymentsRepository {
  _FakePaymentsRepository({this.paymentResult, this.confirmQueue})
    : super(Dio());

  /// [DriverRidePayment] o [DioException].
  final Object? paymentResult;

  /// Elementos: [DriverRidePayment] (éxito) o [DioException] (falla).
  /// Si tiene un solo elemento, se repite en cada llamada.
  final List<Object>? confirmQueue;

  int getPaymentCalls = 0;
  int confirmCalls = 0;
  String? lastCashReceived;

  @override
  Future<DriverRidePayment> getPayment(String rideId) async {
    getPaymentCalls++;

    final result = paymentResult;

    if (result is DioException) {
      throw result;
    }

    if (result == null) {
      throw StateError('paymentResult no configurado en el fake');
    }

    return result as DriverRidePayment;
  }

  @override
  Future<DriverRidePayment> confirmCashPayment({
    required String rideId,
    required String cashReceived,
  }) async {
    confirmCalls++;
    lastCashReceived = cashReceived;

    final queue = confirmQueue;

    if (queue == null || queue.isEmpty) {
      throw StateError('confirmQueue no configurado en el fake');
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverRidePayment;
  }
}

class _FakeRidesRepositoryForCash extends DriverRidesRepository {
  _FakeRidesRepositoryForCash({this.rideResult}) : super(Dio());

  /// [DriverActiveRide] o `null` (simula una falla real de lookup:
  /// el subtítulo debe caer al texto neutral sin romper el flujo).
  final DriverActiveRide? rideResult;

  @override
  Future<DriverActiveRide> getRide(String rideId) async {
    final result = rideResult;

    if (result == null) {
      throw Exception('No se pudo consultar el viaje.');
    }

    return result;
  }
}
