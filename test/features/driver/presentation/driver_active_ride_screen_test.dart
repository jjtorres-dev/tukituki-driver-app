import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_active_ride.dart';
import 'package:driver/features/driver/domain/driver_assigned_passenger.dart';
import 'package:driver/features/driver/domain/driver_cancellation_reason.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
import 'package:driver/features/driver/domain/driver_ride_completion.dart';
import 'package:driver/features/driver/domain/driver_ride_waiting.dart';
import 'package:driver/features/driver/presentation/driver_active_ride_screen.dart';
import 'package:driver/features/driver/presentation/driver_home_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    driverActiveRideGpsFetcherOverride = ({required requestPermission}) async {
      return _fakePosition();
    };
  });

  tearDown(() {
    driverActiveRideGpsFetcherOverride = null;
    driverHomeMapBuilderOverride = null;
  });

  group('DRIVER_ASSIGNED', () {
    testWidgets('A: muestra "Pasajero asignado"', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Pasajero asignado'), findsOneWidget);
    });

    testWidgets('B: muestra firstName real del passenger', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text(ride.passenger!.firstName), findsOneWidget);
    });

    testWidgets('C: muestra rating real cuando hay historial', (tester) async {
      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'María',
          ratingAverage: '4.80',
          ratingCount: 32,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('⭐ 4.8 · 32 calificaciones'), findsOneWidget);
    });

    testWidgets('C2: sin historial NO muestra rating (ni 0.0)', (tester) async {
      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'María',
          ratingAverage: '0.00',
          ratingCount: 0,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.textContaining('⭐'), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
    });

    testWidgets('D: muestra agreedFare real (no estimatedFare)', (
      tester,
    ) async {
      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        agreedFare: '8.00',
        estimatedFare: '99.99',
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('S/ 8.00'), findsOneWidget);
      expect(find.text('S/ 99.99'), findsNothing);
    });

    testWidgets('E: muestra pickup/destination reales', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text(ride.originAddress), findsOneWidget);
      expect(find.text(ride.destinationAddress), findsOneWidget);
    });

    testWidgets('F: muestra distanceToOriginMeters real', (tester) async {
      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        distanceToOriginMeters: 650,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('650 m al recojo'), findsOneWidget);
    });

    testWidgets('G: NO muestra ETA/minutos', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      final texts = _visibleTexts(tester).join(' | ');

      expect(texts.toLowerCase(), isNot(contains('eta')));
      expect(
        RegExp(r'\d+\s*min\b', caseSensitive: false).hasMatch(texts),
        isFalse,
      );
    });

    testWidgets('H: NO muestra phone/chat', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.byIcon(Icons.call), findsNothing);
      expect(find.byIcon(Icons.phone), findsNothing);
      expect(find.byIcon(Icons.chat), findsNothing);
      expect(find.byIcon(Icons.chat_bubble), findsNothing);
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Chat'), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
    });

    testWidgets('I: NO muestra VIAJE # ni el UUID del ride', (tester) async {
      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        id: 'a1b2c3d4-1111-4de2-bd9f-11f33d64da64',
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.textContaining('VIAJE #'), findsNothing);
      expect(find.text(ride.id), findsNothing);
    });

    testWidgets(
      'J: SÍ muestra "Cancelar viaje" (Checkpoint G1: Backend permite '
      'cancelar en DRIVER_ASSIGNED)',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsOneWidget);
      },
    );

    testWidgets('K: CTA llama startArrival exactamente una vez', (
      tester,
    ) async {
      final assigned = _rideFixture(status: 'DRIVER_ASSIGNED');
      final arriving = _rideFixture(status: 'DRIVER_ARRIVING');

      final rides = _FakeRidesRepository(activeRideQueue: [assigned])
        ..startArrivalResult = arriving;

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.ensureVisible(find.text('Ir a recoger al pasajero'));
      await tester.tap(find.text('Ir a recoger al pasajero'));
      await tester.pump();
      await tester.pump();

      expect(rides.startArrivalCalls, 1);
    });

    testWidgets('L: no cambia status localmente antes de la respuesta real', (
      tester,
    ) async {
      final assigned = _rideFixture(status: 'DRIVER_ASSIGNED');
      final arriving = _rideFixture(status: 'DRIVER_ARRIVING');

      final rides = _FakeRidesRepository(activeRideQueue: [assigned])
        ..startArrivalGate = Completer<DriverActiveRide>();

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Pasajero asignado'), findsOneWidget);

      await tester.ensureVisible(find.text('Ir a recoger al pasajero'));
      await tester.tap(find.text('Ir a recoger al pasajero'));
      await tester.pump();

      // Todavía no respondió Backend: sigue mostrando el estado anterior.
      expect(find.text('Pasajero asignado'), findsOneWidget);
      expect(find.text('En camino al pasajero'), findsNothing);

      rides.startArrivalGate!.complete(arriving);
      await tester.pump();
      await tester.pump();

      expect(find.text('En camino al pasajero'), findsOneWidget);
    });
  });

  group('DRIVER_ARRIVING', () {
    testWidgets('A: muestra "En camino al pasajero"', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVING');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('En camino al pasajero'), findsOneWidget);
    });

    testWidgets('B: mismos datos reales (fare/passenger/pickup/destino)', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVING', agreedFare: '9.50');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('S/ 9.50'), findsOneWidget);
      expect(find.text(ride.passenger!.firstName), findsOneWidget);
      expect(find.text(ride.originAddress), findsOneWidget);
      expect(find.text(ride.destinationAddress), findsOneWidget);
    });

    testWidgets('C: CTA dice "Llegué al punto de recojo"', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVING');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Llegué al punto de recojo'), findsOneWidget);
    });

    testWidgets('D: CTA ejecuta arrive real exactamente una vez', (
      tester,
    ) async {
      final arriving = _rideFixture(status: 'DRIVER_ARRIVING');
      final arrived = _rideFixture(status: 'DRIVER_ARRIVED');

      final rides = _FakeRidesRepository(activeRideQueue: [arriving])
        ..arriveResult = arrived;

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.ensureVisible(find.text('Llegué al punto de recojo'));
      await tester.tap(find.text('Llegué al punto de recojo'));
      await tester.pump();
      await tester.pump();

      expect(rides.arriveCalls, 1);
    });

    testWidgets('E: passenger null y coordenadas ausentes no crashean', (
      tester,
    ) async {
      final ride = _rideFixture(
        status: 'DRIVER_ARRIVING',
        passenger: null,
        originLatitude: null,
        originLongitude: null,
        destinationLatitude: null,
        destinationLongitude: null,
        distanceToOriginMeters: null,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(
        find.text('Información del pasajero no disponible'),
        findsOneWidget,
      );
    });

    testWidgets('F: NO muestra ETA/minutos', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVING');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      final texts = _visibleTexts(tester).join(' | ');

      expect(texts.toLowerCase(), isNot(contains('eta')));
      expect(
        RegExp(r'\d+\s*min\b', caseSensitive: false).hasMatch(texts),
        isFalse,
      );
    });
  });

  group('DRIVER_ARRIVED', () {
    testWidgets('A: renderiza "¡Llegaste!"', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('¡Llegaste!'), findsOneWidget);
    });

    testWidgets('B: muestra firstName real del passenger en el subtítulo', (
      tester,
    ) async {
      final ride = _rideFixture(
        status: 'DRIVER_ARRIVED',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Maycol',
          ratingAverage: '4.85',
          ratingCount: 32,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Pide el código de 4 dígitos a Maycol'), findsOneWidget);
    });

    testWidgets('C: muestra fallback neutral si passenger es null', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED', passenger: null);
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(
        find.text('Pide al pasajero su código de 4 dígitos'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Pide el código de 4 dígitos a'),
        findsNothing,
      );
    });

    testWidgets('D: muestra agreedFare/displayFare real', (tester) async {
      final ride = _rideFixture(
        status: 'DRIVER_ARRIVED',
        agreedFare: '12.00',
        estimatedFare: '50.00',
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('S/ 12.00'), findsOneWidget);
      expect(find.text('S/ 50.00'), findsNothing);
    });

    testWidgets('E: muestra pickup/destination reales', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text(ride.originAddress), findsOneWidget);
      expect(find.text(ride.destinationAddress), findsOneWidget);
    });

    testWidgets('F: muestra 4 cajas vacías', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      for (var index = 0; index < 4; index++) {
        expect(_pinBoxDigit(tester, index), '');
      }
    });

    testWidgets('G: NO muestra placeholder 0000', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('0000'), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('H: botón deshabilitado con 0-3 dígitos', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(_startButton(tester).onPressed, isNull);

      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();

      expect(_startButton(tester).onPressed, isNull);
    });

    testWidgets('I: botón habilitado con 4 dígitos', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [_rideFixture(status: 'IN_PROGRESS')];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      expect(_startButton(tester).onPressed, isNotNull);
    });

    testWidgets('J: NO hace auto-submit al cuarto dígito', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [_rideFixture(status: 'IN_PROGRESS')];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(rides.startRideCalls, 0);
    });

    testWidgets('K: submit llama al repository exactamente una vez', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [_rideFixture(status: 'IN_PROGRESS')];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(rides.startRideCalls, 1);
      expect(rides.lastStartRideCode, '1234');
    });

    testWidgets('L: no cambia status local antes de la respuesta real', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideGate = Completer<DriverActiveRide>();

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();

      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();

      expect(find.text('¡Llegaste!'), findsOneWidget);

      rides.startRideGate!.complete(_rideFixture(status: 'IN_PROGRESS'));
      await tester.pump();
      await tester.pump();

      expect(find.text('¡Llegaste!'), findsNothing);
      expect(find.text('Llegué al destino y finalizar viaje'), findsOneWidget);
    });

    testWidgets('rating: visible solo con historial real', (tester) async {
      final withRating = _rideFixture(
        status: 'DRIVER_ARRIVED',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Maycol',
          ratingAverage: '4.80',
          ratingCount: 32,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [withRating]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('⭐ 4.8 · 32 calificaciones'), findsOneWidget);
      expect(find.textContaining('viajes'), findsNothing);
    });

    testWidgets('rating: ausente sin historial (nunca "viajes")', (
      tester,
    ) async {
      final withoutRating = _rideFixture(
        status: 'DRIVER_ARRIVED',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Maycol',
          ratingAverage: '0.00',
          ratingCount: 0,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [withoutRating]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.textContaining('⭐'), findsNothing);
      expect(find.textContaining('viajes'), findsNothing);
    });

    testWidgets('input: solo dígitos, máximo 4 caracteres', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1a2!3 456');
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));

      expect(field.controller!.text, '1234');
    });

    testWidgets('input: borrar funciona', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '123');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();

      expect(_pinBoxDigit(tester, 0), '1');
      expect(_pinBoxDigit(tester, 1), '2');
      expect(_pinBoxDigit(tester, 2), '');
    });

    testWidgets(
      'PIN incorrecto: muestra "Código incorrecto" + intentos restantes reales, sin salir de DRIVER_ARRIVED',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..startRideQueue = [
            _dioError(
              statusCode: 400,
              data: const {
                'message': 'El código de inicio es incorrecto',
                'remainingAttempts': 4,
              },
            ),
          ];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.enterText(find.byType(TextField), '9999');
        await tester.pump();
        await tester.ensureVisible(find.text('Iniciar viaje'));
        await tester.tap(find.text('Iniciar viaje'));
        await tester.pump();
        await tester.pump();

        expect(find.text('Código incorrecto'), findsOneWidget);
        expect(find.text('4 intentos restantes'), findsOneWidget);
        expect(find.text('¡Llegaste!'), findsOneWidget);
      },
    );

    testWidgets('último intento: singular "1 intento restante", nunca plural', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [
          _dioError(
            statusCode: 400,
            data: const {
              'message': 'El código de inicio es incorrecto',
              'remainingAttempts': 1,
            },
          ),
        ];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '9999');
      await tester.pump();
      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('1 intento restante'), findsOneWidget);
      expect(find.text('1 intentos restantes'), findsNothing);
    });

    testWidgets('410: código vencido, no navega a IN_PROGRESS', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [
          _dioError(
            statusCode: 410,
            data: const {'message': 'El código de inicio venció'},
          ),
        ];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Código vencido'), findsOneWidget);
      expect(find.text('¡Llegaste!'), findsOneWidget);
      expect(find.text('Viaje en curso'), findsNothing);
    });

    testWidgets('423: código bloqueado, deja el submit deshabilitado', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [
          _dioError(
            statusCode: 423,
            data: const {
              'message': 'El código fue bloqueado por demasiados intentos',
            },
          ),
        ];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Código bloqueado'), findsOneWidget);

      // Aunque se reingresen 4 dígitos, el submit sigue bloqueado.
      await tester.enterText(find.byType(TextField), '5678');
      await tester.pump();

      expect(_startButton(tester).onPressed, isNull);
    });

    testWidgets('400 de GPS/distancia NO se muestra como "Código incorrecto"', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [
          _dioError(
            statusCode: 400,
            data: const {
              'message':
                  'Debes estar cerca del punto de origen para iniciar el viaje',
              'distanceToOriginMeters': 320,
              'maximumStartDistanceMeters': 200,
            },
          ),
        ];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Código incorrecto'), findsNothing);
      expect(find.text('No pudimos validar tu ubicación'), findsOneWidget);
      expect(
        find.text('Estás a 320 m del punto de recojo (máximo 200 m).'),
        findsOneWidget,
      );
    });

    testWidgets(
      'error de red: muestra mensaje de retry y conserva el PIN ingresado',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..startRideQueue = [_dioNetworkError()];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.enterText(find.byType(TextField), '1234');
        await tester.pump();
        await tester.ensureVisible(find.text('Iniciar viaje'));
        await tester.tap(find.text('Iniciar viaje'));
        await tester.pump();
        await tester.pump();

        expect(find.text('No pudimos iniciar el viaje'), findsOneWidget);
        expect(find.text('Inténtalo nuevamente.'), findsOneWidget);

        // El PIN sigue ingresado: no se obligó a pedirlo de nuevo.
        expect(_pinBoxDigit(tester, 0), '1');
        expect(_pinBoxDigit(tester, 1), '2');
        expect(_pinBoxDigit(tester, 2), '3');
        expect(_pinBoxDigit(tester, 3), '4');
      },
    );

    testWidgets('éxito: pasa a IN_PROGRESS y renderiza la pantalla legacy', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..startRideQueue = [_rideFixture(status: 'IN_PROGRESS')];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.ensureVisible(find.text('Iniciar viaje'));
      await tester.tap(find.text('Iniciar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('¡Llegaste!'), findsNothing);
      expect(find.text('Llegué al destino y finalizar viaje'), findsOneWidget);
    });

    testWidgets(
      'restore: monta directo en DRIVER_ARRIVED sin pasar por otros estados',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('¡Llegaste!'), findsOneWidget);
        expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
        expect(find.text(ride.passenger!.firstName), findsOneWidget);
        expect(rides.getActiveRideCalls, greaterThanOrEqualTo(1));
      },
    );

    group('Responsive', () {
      testWidgets('360x640 con teclado abierto sin overflow', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);

        await _pumpArrivedStressScenario(tester);
      });

      testWidgets('390x844 sin overflow', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpArrivedStressScenario(tester);
      });

      testWidgets('412x915 sin overflow', (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpArrivedStressScenario(tester);
      });
    });
  });

  group('Passenger No-show (Checkpoint G2)', () {
    testWidgets('1: sin waiting activo muestra "Iniciar tiempo de espera"', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [null];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      expect(find.text('Iniciar tiempo de espera'), findsOneWidget);
      expect(find.text('Esperando al pasajero'), findsNothing);
    });

    testWidgets('2: tap "Iniciar tiempo de espera" dispara startRideWaiting '
        'una sola vez', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture();
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [null]
        ..startRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Iniciar tiempo de espera'));
      await tester.tap(find.text('Iniciar tiempo de espera'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(rides.startRideWaitingCalls, 1);
      expect(find.text('Esperando al pasajero'), findsOneWidget);
    });

    testWidgets('3: loading evita doble tap en "Iniciar tiempo de espera"', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [null]
        ..startRideWaitingGate = Completer<DriverRideWaiting>();

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Iniciar tiempo de espera'));
      await tester.tap(find.text('Iniciar tiempo de espera'));
      await tester.pump();

      expect(find.text('Iniciando espera...'), findsOneWidget);

      await tester.tap(find.text('Iniciando espera...'), warnIfMissed: false);
      await tester.pump();

      expect(rides.startRideWaitingCalls, 1);

      rides.startRideWaitingGate!.complete(_waitingFixture());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('4: waiting activo muestra el contador MM:SS real de '
        'Backend', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(remainingWaitingSeconds: 277);
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      expect(find.text('Esperando al pasajero'), findsOneWidget);
      expect(find.text('04:37'), findsOneWidget);
    });

    testWidgets('5: canReportNoShow=false: CTA "Pasajero no se presentó" '
        'deshabilitado', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(
        canReportNoShow: false,
        remainingWaitingSeconds: 120,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Pasajero no se presentó'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(button.onPressed, isNull);
      expect(find.text('Disponible en 02:00'), findsOneWidget);
    });

    testWidgets(
      '6: remaining=0 pero canReportNoShow=false: CTA SIGUE deshabilitado '
      '(la autoridad es Backend, nunca el contador local)',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(
          remainingWaitingSeconds: 0,
          canReportNoShow: false,
        );
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(find.text('00:00'), findsWidgets);

        final button = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text('Pasajero no se presentó'),
            matching: find.byType(OutlinedButton),
          ),
        );

        expect(button.onPressed, isNull);
      },
    );

    testWidgets('7: canReportNoShow=true: CTA "Pasajero no se presentó" '
        'habilitado', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(
        canReportNoShow: true,
        remainingWaitingSeconds: 0,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Pasajero no se presentó'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(button.onPressed, isNotNull);
      expect(find.textContaining('Disponible en'), findsNothing);
    });

    testWidgets('8: tap "Pasajero no se presentó" abre confirmación', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(canReportNoShow: true);
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Pasajero no se presentó'));
      await tester.tap(find.text('Pasajero no se presentó'));
      await tester.pumpAndSettle();

      expect(
        find.text('¿Confirmar que el pasajero no se presentó?'),
        findsOneWidget,
      );
      expect(rides.reportPassengerNoShowCalls, 0);
    });

    testWidgets('9: "Volver" en la confirmación NO dispara '
        'reportPassengerNoShow', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(canReportNoShow: true);
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Pasajero no se presentó'));
      await tester.tap(find.text('Pasajero no se presentó'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();

      expect(rides.reportPassengerNoShowCalls, 0);
      expect(find.text('Esperando al pasajero'), findsOneWidget);
    });

    testWidgets(
      '10/11: confirmar publica ubicación fresca y hace POST no-show',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(canReportNoShow: true);
        final operations = _FakeOperationsRepository();
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting];

        final router = GoRouter(
          initialLocation: '/active-ride',
          routes: [
            GoRoute(
              path: '/active-ride',
              builder: (context, state) => const DriverActiveRideScreen(),
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
              driverRidesRepositoryProvider.overrideWithValue(rides),
              driverOperationsRepositoryProvider.overrideWithValue(operations),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump();

        await tester.ensureVisible(find.text('Pasajero no se presentó'));
        await tester.tap(find.text('Pasajero no se presentó'));
        await tester.pumpAndSettle();

        final updateLocationCallsBefore = operations.updateLocationCalls;

        await tester.tap(find.text('Sí, confirmar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(rides.reportPassengerNoShowCalls, 1);
        expect(
          operations.updateLocationCalls,
          greaterThan(updateLocationCallsBefore),
        );

        // 12: navega a Home sin mutar disponibilidad manualmente.
        expect(find.text('HOME_ROUTE'), findsOneWidget);
      },
    );

    testWidgets(
      '13: 409 early no-show: permanece en ARRIVED, refresca waiting y NO '
      'navega a Home',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(canReportNoShow: true);
        final resynced = _waitingFixture(
          canReportNoShow: false,
          remainingWaitingSeconds: 42,
        );
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting, resynced]
          ..reportPassengerNoShowResult = _dioError(
            statusCode: 409,
            data: const {
              'message': 'Aún debes esperar antes de reportarlo',
              'remainingSeconds': 42,
            },
          );

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        await tester.ensureVisible(find.text('Pasajero no se presentó'));
        await tester.tap(find.text('Pasajero no se presentó'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Sí, confirmar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Esperando al pasajero'), findsOneWidget);
        expect(
          find.text('Aún debes esperar antes de reportarlo'),
          findsOneWidget,
        );
      },
    );

    testWidgets('14: error de red permanece en pantalla y permite retry', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final waiting = _waitingFixture(canReportNoShow: true);
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [waiting]
        ..reportPassengerNoShowResult = _dioNetworkError();

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Pasajero no se presentó'));
      await tester.tap(find.text('Pasajero no se presentó'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sí, confirmar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Esperando al pasajero'), findsOneWidget);
      expect(
        find.text('No se pudo confirmar. Inténtalo nuevamente.'),
        findsOneWidget,
      );

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Pasajero no se presentó'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      '15: PIN válido durante waiting activo: pasa a IN_PROGRESS y detiene '
      'el polling de waiting',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(canReportNoShow: true);
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting]
          ..startRideQueue = [_rideFixture(status: 'IN_PROGRESS')];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(find.text('Esperando al pasajero'), findsOneWidget);

        await tester.enterText(find.byType(TextField), '1234');
        await tester.pump();

        await tester.ensureVisible(find.text('Iniciar viaje'));
        await tester.tap(find.text('Iniciar viaje'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Viaje en curso'), findsOneWidget);
        expect(find.text('Esperando al pasajero'), findsNothing);
        expect(find.text('Pasajero no se presentó'), findsNothing);
      },
    );

    testWidgets(
      '16: restore directo a ARRIVED con waiting existente recupera el '
      'remaining real de Backend (sin reiniciar el contador)',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(
          remainingWaitingSeconds: 55,
          canReportNoShow: false,
        );
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(find.text('00:55'), findsOneWidget);
        expect(rides.startRideWaitingCalls, 0);
      },
    );

    testWidgets(
      '17: restore directo a ARRIVED sin waiting muestra el estado inicial',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [null];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(find.text('Iniciar tiempo de espera'), findsOneWidget);
      },
    );

    testWidgets('18: app resume con Ride en ARRIVED resincroniza waiting de '
        'inmediato', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final before = _waitingFixture(
        canReportNoShow: false,
        remainingWaitingSeconds: 90,
      );
      final after = _waitingFixture(
        canReportNoShow: true,
        remainingWaitingSeconds: 0,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..getRideWaitingQueue = [before, after];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      expect(rides.getRideWaitingCalls, 1);

      final state = tester.state<State<DriverActiveRideScreen>>(
        find.byType(DriverActiveRideScreen),
      );

      (state as WidgetsBindingObserver).didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(rides.getRideWaitingCalls, 2);

      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Pasajero no se presentó'),
          matching: find.byType(OutlinedButton),
        ),
      );

      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      '19: el botón "Cancelar viaje" de G1 sigue disponible con waiting '
      'activo',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final waiting = _waitingFixture(canReportNoShow: true);
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..getRideWaitingQueue = [waiting];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsOneWidget);
      },
    );

    testWidgets('20: IN_PROGRESS no muestra ninguna tarjeta de waiting', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      expect(find.text('Iniciar tiempo de espera'), findsNothing);
      expect(find.text('Esperando al pasajero'), findsNothing);
      expect(find.text('Pasajero no se presentó'), findsNothing);
    });

    testWidgets('21: COMPLETED no muestra ninguna tarjeta de waiting', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..completeRideQueue = [_completionFixture()];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('¡Viaje completado!'), findsOneWidget);
      expect(find.text('Iniciar tiempo de espera'), findsNothing);
      expect(find.text('Esperando al pasajero'), findsNothing);
      expect(find.text('Pasajero no se presentó'), findsNothing);
    });
  });

  group('IN_PROGRESS', () {
    testWidgets('A: renderiza "Viaje en curso"', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Viaje en curso'), findsOneWidget);
    });

    testWidgets('B: muestra "Dirígete al destino del pasajero"', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Dirígete al destino del pasajero'), findsOneWidget);
    });

    testWidgets('C: muestra Passenger real', (tester) async {
      final ride = _rideFixture(
        status: 'IN_PROGRESS',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Rosa',
          ratingAverage: '4.85',
          ratingCount: 32,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Rosa'), findsOneWidget);
    });

    testWidgets('D: muestra rating real cuando hay historial', (tester) async {
      final withRating = _rideFixture(
        status: 'IN_PROGRESS',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Rosa',
          ratingAverage: '4.80',
          ratingCount: 32,
        ),
      );
      final rides = _FakeRidesRepository(activeRideQueue: [withRating]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('⭐ 4.8 · 32 calificaciones'), findsOneWidget);
    });

    testWidgets('D2: NO muestra rating sin historial (nunca "viajes")', (
      tester,
    ) async {
      final withoutRating = _rideFixture(
        status: 'IN_PROGRESS',
        passenger: const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'Rosa',
          ratingAverage: '0.00',
          ratingCount: 0,
        ),
      );
      final ridesWithout = _FakeRidesRepository(
        activeRideQueue: [withoutRating],
      );

      await _pumpActiveRide(tester, rides: ridesWithout);
      await tester.pump();

      expect(find.textContaining('⭐'), findsNothing);
      expect(find.textContaining('viajes'), findsNothing);
    });

    testWidgets('E: muestra TARIFA ACORDADA real', (tester) async {
      final ride = _rideFixture(
        status: 'IN_PROGRESS',
        agreedFare: '15.00',
        estimatedFare: '99.99',
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('TARIFA ACORDADA'), findsOneWidget);
      expect(find.text('S/ 15.00'), findsOneWidget);
      expect(find.text('S/ 99.99'), findsNothing);
    });

    testWidgets('F: muestra destinationAddress real', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text(ride.destinationAddress), findsOneWidget);
    });

    testWidgets('G: muestra progreso RECOJO → DESTINO', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('RECOJO'), findsOneWidget);
      expect(find.text('DESTINO'), findsOneWidget);
    });

    testWidgets('H/I/J: NO muestra ETA, minutos ni porcentaje', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      final texts = _visibleTexts(tester).join(' | ');

      expect(texts.toLowerCase(), isNot(contains('eta')));
      expect(
        RegExp(r'\d+\s*min\b', caseSensitive: false).hasMatch(texts),
        isFalse,
      );
      expect(RegExp(r'\d+\s*%').hasMatch(texts), isFalse);
    });

    testWidgets('K: NO muestra phone/chat', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.byIcon(Icons.call), findsNothing);
      expect(find.byIcon(Icons.chat), findsNothing);
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Chat'), findsNothing);
      expect(find.text('WhatsApp'), findsNothing);
    });

    testWidgets('L: CTA "Llegué al destino y finalizar viaje" visible', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Llegué al destino y finalizar viaje'), findsOneWidget);
    });

    testWidgets(
      'confirmación: tocar el CTA muestra el diálogo y NO llama completeRide',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();

        expect(find.text('¿Finalizar el viaje?'), findsOneWidget);
        expect(
          find.text('Confirma que llegaste al destino del pasajero.'),
          findsOneWidget,
        );
        expect(find.text('Volver'), findsOneWidget);
        expect(find.text('Sí, finalizar viaje'), findsOneWidget);
        expect(rides.completeRideCalls, 0);
      },
    );

    testWidgets(
      'cancelación: tocar "Volver" cierra el diálogo sin llamar complete',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();

        await tester.tap(find.text('Volver'));
        await tester.pump();

        expect(find.text('¿Finalizar el viaje?'), findsNothing);
        expect(rides.completeRideCalls, 0);
        expect(find.text('Viaje en curso'), findsOneWidget);
      },
    );

    testWidgets(
      'éxito: confirmar llama completeRide exactamente una vez y muestra la pantalla legacy COMPLETED',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..completeRideQueue = [_completionFixture()];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();

        await tester.tap(find.text('Sí, finalizar viaje'));
        await tester.pump();
        await tester.pump();

        expect(rides.completeRideCalls, 1);
        expect(find.text('¡Viaje completado!'), findsOneWidget);
      },
    );

    testWidgets('no cambia status local antes de la respuesta real (gate)', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..completeRideGate = Completer<DriverRideCompletion>();

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();

      expect(find.text('Viaje en curso'), findsOneWidget);
      expect(find.text('¡Viaje completado!'), findsNothing);

      rides.completeRideGate!.complete(_completionFixture());
      await tester.pump();
      await tester.pump();

      expect(find.text('¡Viaje completado!'), findsOneWidget);
    });

    testWidgets(
      'GPS distancia: 400 con distanceToDestinationMeters muestra mensaje real, sigue IN_PROGRESS',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..completeRideQueue = [
            _dioError(
              statusCode: 400,
              data: const {
                'message': 'Debes estar cerca del destino',
                'distanceToDestinationMeters': 310,
                'maximumCompletionDistanceMeters': 250,
              },
            ),
          ];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();
        await tester.tap(find.text('Sí, finalizar viaje'));
        await tester.pump();
        await tester.pump();

        expect(find.text('Aún estás lejos del destino'), findsOneWidget);
        expect(
          find.text('Estás a 310 m del destino (máximo 250 m).'),
          findsOneWidget,
        );
        expect(find.text('Viaje en curso'), findsOneWidget);
      },
    );

    testWidgets(
      'GPS calidad: 400 sin distance fields muestra mensaje de ubicación genérico',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..completeRideQueue = [
            _dioError(
              statusCode: 400,
              data: const {
                'message':
                    'La precisión GPS no es suficiente para finalizar el viaje',
              },
            ),
          ];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();
        await tester.tap(find.text('Sí, finalizar viaje'));
        await tester.pump();
        await tester.pump();

        expect(find.text('No pudimos validar tu ubicación'), findsOneWidget);
        expect(
          find.text('Verifica tu GPS e inténtalo nuevamente.'),
          findsOneWidget,
        );
        expect(find.text('Aún estás lejos del destino'), findsNothing);
      },
    );

    testWidgets('409: muestra actualización de estado y reconsulta el ride', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride, ride])
        ..completeRideQueue = [
          _dioError(
            statusCode: 409,
            data: const {
              'message': 'El viaje debe estar en IN_PROGRESS para finalizarse',
            },
          ),
        ];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('El viaje cambió de estado'), findsOneWidget);
      expect(rides.getActiveRideCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('network/5xx: muestra mensaje de retry, no pierde el ride', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..completeRideQueue = [_dioNetworkError()];

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos finalizar el viaje'), findsOneWidget);
      expect(find.text('Inténtalo nuevamente.'), findsOneWidget);
      expect(find.text('Viaje en curso'), findsOneWidget);
    });

    testWidgets(
      'restore: monta directo en IN_PROGRESS sin pasar por otros estados',
      (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Viaje en curso'), findsOneWidget);
        expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
        expect(find.text(ride.passenger!.firstName), findsOneWidget);
        expect(find.text(ride.destinationAddress), findsOneWidget);
        expect(rides.getActiveRideCalls, greaterThanOrEqualTo(1));
      },
    );

    group('Mapa', () {
      testWidgets('destination marker cuando hay coordenadas válidas', (
        tester,
      ) async {
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(resolved, isNotNull);
        expect(resolved!.markers, hasLength(2));
      });

      testWidgets(
        'ausencia segura de destination marker si la coordenada es inválida/null',
        (tester) async {
          DriverHomeMapResolved? resolved;

          driverHomeMapBuilderOverride = (context, config) {
            resolved = config;
            return const SizedBox.shrink();
          };

          final ride = _rideFixture(
            status: 'IN_PROGRESS',
            destinationLatitude: null,
            destinationLongitude: null,
          );
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();
          await tester.pump();

          expect(resolved, isNotNull);
          expect(resolved!.markers, hasLength(1));
        },
      );

      testWidgets('el encuadre Driver+destino se solicita una sola vez', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        final dynamic state = tester.state(find.byType(DriverActiveRideScreen));

        final firstRequest = state.debugCameraRequest;
        expect(firstRequest, isNotNull);
        expect(firstRequest.secondaryTarget, isNotNull);

        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 10));

        expect(state.debugCameraRequest, same(firstRequest));
      });
    });

    group('Responsive', () {
      testWidgets('360x640 sin overflow', (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpInProgressStressScenario(tester);
      });

      testWidgets('390x844 sin overflow', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpInProgressStressScenario(tester);
      });

      testWidgets('412x915 sin overflow', (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpInProgressStressScenario(tester);
      });
    });
  });

  group('COMPLETED', () {
    Future<void> pumpCompletion(
      WidgetTester tester, {
      required DriverRideCompletion completion,
      _FakeOperationsRepository? operations,
    }) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..completeRideQueue = [completion];

      await _pumpActiveRide(tester, rides: rides, operations: operations);
      await tester.pump();

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('A: renderiza "¡Viaje completado!"', (tester) async {
      await pumpCompletion(tester, completion: _completionFixture());

      expect(find.text('¡Viaje completado!'), findsOneWidget);
    });

    group('Checkpoint F1: presence heartbeat post-ride', () {
      testWidgets(
        'heartbeat arranca al completar y avanza cada ~30s (sin GPS)',
        (tester) async {
          final operations = _FakeOperationsRepository();

          await pumpCompletion(
            tester,
            completion: _completionFixture(),
            operations: operations,
          );

          // `_activityTimer` ya envió su heartbeat+location final
          // antes de `complete`. Contamos desde que la vista
          // COMPLETED ya está montada.
          final baseline = operations.heartbeatCalls;
          final locationBaseline = operations.updateLocationCalls;

          await tester.pump(const Duration(seconds: 30));

          expect(operations.heartbeatCalls, baseline + 1);
          // Ningún heartbeat post-ride publica ubicación.
          expect(operations.updateLocationCalls, locationBaseline);

          await tester.pump(const Duration(seconds: 30));
          expect(operations.heartbeatCalls, baseline + 2);
        },
      );

      testWidgets(
        'heartbeat 400 (Driver realmente OFFLINE) no rompe la vista COMPLETED',
        (tester) async {
          final ride = _rideFixture(status: 'IN_PROGRESS');
          final rides = _FakeRidesRepository(activeRideQueue: [ride])
            ..completeRideQueue = [_completionFixture()];
          final operations = _FakeOperationsRepository();

          await _pumpActiveRide(tester, rides: rides, operations: operations);
          await tester.pump();

          await tester.ensureVisible(
            find.text('Llegué al destino y finalizar viaje'),
          );
          await tester.tap(find.text('Llegué al destino y finalizar viaje'));
          await tester.pump();
          await tester.tap(find.text('Sí, finalizar viaje'));
          await tester.pump();
          await tester.pump();

          expect(find.text('¡Viaje completado!'), findsOneWidget);

          operations.heartbeatError = _dioError(statusCode: 400);

          expect(tester.takeException(), isNull);

          await tester.pump(const Duration(seconds: 30));

          expect(tester.takeException(), isNull);
          expect(find.text('¡Viaje completado!'), findsOneWidget);
        },
      );

      testWidgets(
        '"Cobrar efectivo" desmonta ActiveRideScreen y detiene el heartbeat '
        '(sin doble timer al llegar a Cash)',
        (tester) async {
          final completion = _completionFixture(rideId: 'ride-42');
          final operations = _FakeOperationsRepository();

          final router = GoRouter(
            initialLocation: '/active-ride',
            routes: [
              GoRoute(
                path: '/active-ride',
                builder: (context, state) => const DriverActiveRideScreen(),
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

          final ride = _rideFixture(status: 'IN_PROGRESS');
          final rides = _FakeRidesRepository(activeRideQueue: [ride])
            ..completeRideQueue = [completion];

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                driverRidesRepositoryProvider.overrideWithValue(rides),
                driverOperationsRepositoryProvider.overrideWithValue(
                  operations,
                ),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pump();

          await tester.ensureVisible(
            find.text('Llegué al destino y finalizar viaje'),
          );
          await tester.tap(find.text('Llegué al destino y finalizar viaje'));
          await tester.pump();
          await tester.tap(find.text('Sí, finalizar viaje'));
          await tester.pump();
          await tester.pump();

          expect(find.text('¡Viaje completado!'), findsOneWidget);
          expect(operations.heartbeatCalls, greaterThanOrEqualTo(1));

          await tester.ensureVisible(find.text('Cobrar efectivo'));
          await tester.tap(find.text('Cobrar efectivo'));
          await tester.pumpAndSettle();

          expect(find.text('CASH_PAYMENT_ROUTE ride-42'), findsOneWidget);

          final afterNavigation = operations.heartbeatCalls;

          await tester.pump(const Duration(seconds: 90));

          expect(operations.heartbeatCalls, afterNavigation);
        },
      );
    });

    testWidgets('B: muestra firstName real del Passenger', (tester) async {
      await pumpCompletion(tester, completion: _completionFixture());

      expect(find.text('María'), findsOneWidget);
    });

    testWidgets('C: TARIFA FINAL usa finalFare real (no passengerAmountDue)', (
      tester,
    ) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(
          finalFare: '12.30',
          passengerAmountDue: '99.99',
        ),
      );

      expect(find.text('TARIFA FINAL'), findsOneWidget);
      expect(find.text('S/ 12.30'), findsOneWidget);
      expect(find.text('S/ 99.99'), findsNothing);
    });

    testWidgets('D: CASH visible como "Efectivo"', (tester) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(paymentMethod: 'CASH'),
      );

      expect(find.text('Efectivo'), findsOneWidget);
    });

    testWidgets('E: PENDING visible como "Pendiente"', (tester) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(paymentStatus: 'PENDING'),
      );

      expect(find.text('Pendiente'), findsOneWidget);
    });

    testWidgets('F: actualDistanceMeters > 0 visible', (tester) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(actualDistanceMeters: 850),
      );

      expect(find.textContaining('850 m'), findsOneWidget);
    });

    testWidgets('G: actualDistanceMeters == 0 se omite (nunca "0.0 km")', (
      tester,
    ) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(
          actualDistanceMeters: 0,
          actualDurationSeconds: 0,
        ),
      );

      expect(find.textContaining(' m'), findsNothing);
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('H: actualDurationSeconds visible', (tester) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(actualDurationSeconds: 300),
      );

      expect(find.textContaining('5 min'), findsOneWidget);
    });

    testWidgets('I: CTA Cobrar efectivo visible solo con CASH+PENDING', (
      tester,
    ) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(
          paymentMethod: 'CASH',
          paymentStatus: 'PENDING',
        ),
      );

      expect(find.text('Cobrar efectivo'), findsOneWidget);
    });

    testWidgets('J: NO muestra CTA si method != CASH', (tester) async {
      await pumpCompletion(
        tester,
        completion: _completionFixture(
          paymentMethod: 'YAPE',
          paymentStatus: 'PENDING',
        ),
      );

      expect(find.text('Cobrar efectivo'), findsNothing);
    });

    testWidgets('CTA navega a /cash-payment/:rideId', (tester) async {
      final ride = _rideFixture(status: 'IN_PROGRESS');
      final rides = _FakeRidesRepository(activeRideQueue: [ride])
        ..completeRideQueue = [_completionFixture(rideId: 'ride-77')];

      final router = GoRouter(
        initialLocation: '/active-ride',
        routes: [
          GoRoute(
            path: '/active-ride',
            builder: (context, state) => const DriverActiveRideScreen(),
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

      await tester.ensureVisible(
        find.text('Llegué al destino y finalizar viaje'),
      );
      await tester.tap(find.text('Llegué al destino y finalizar viaje'));
      await tester.pump();
      await tester.tap(find.text('Sí, finalizar viaje'));
      await tester.pump();
      await tester.pump();

      await tester.ensureVisible(find.text('Cobrar efectivo'));
      await tester.tap(find.text('Cobrar efectivo'));
      await tester.pumpAndSettle();

      expect(find.text('CASH_PAYMENT_ROUTE ride-77'), findsOneWidget);
    });
  });

  group('Mapa — markers reales', () {
    testWidgets(
      'pickup y destino se agregan como markers cuando hay coordenadas',
      (tester) async {
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(resolved, isNotNull);
        expect(resolved!.markers, hasLength(2));
      },
    );

    testWidgets(
      'un marker se omite de forma segura si su coordenada es inválida',
      (tester) async {
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        final ride = _rideFixture(
          status: 'DRIVER_ASSIGNED',
          destinationLatitude: null,
          destinationLongitude: null,
        );
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        expect(resolved, isNotNull);
        expect(resolved!.markers, hasLength(1));
      },
    );

    testWidgets('sin ninguna coordenada válida, no se fabrica ningún marker', (
      tester,
    ) async {
      DriverHomeMapResolved? resolved;

      driverHomeMapBuilderOverride = (context, config) {
        resolved = config;
        return const SizedBox.shrink();
      };

      final ride = _rideFixture(
        status: 'DRIVER_ASSIGNED',
        originLatitude: null,
        originLongitude: null,
        destinationLatitude: null,
        destinationLongitude: null,
      );
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();
      await tester.pump();

      expect(resolved, isNotNull);
      expect(resolved!.markers, isEmpty);
    });

    testWidgets(
      'la cámara se encuadra una sola vez (Driver + pickup) sin reencuadrar en cada poll',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        final dynamic state = tester.state(find.byType(DriverActiveRideScreen));

        final firstRequest = state.debugCameraRequest;
        expect(firstRequest, isNotNull);
        expect(firstRequest.secondaryTarget, isNotNull);

        // Un tick más de poll (3s) y de heartbeat (10s): la posición
        // puede refrescarse, pero el pedido de cámara no debe cambiar.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 10));

        expect(state.debugCameraRequest, same(firstRequest));
      },
    );
  });

  group('Restore directo (sin pasar por Home/offer)', () {
    testWidgets('restaura DRIVER_ASSIGNED completo desde cero', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Pasajero asignado'), findsOneWidget);
      expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
      expect(find.text(ride.passenger!.firstName), findsOneWidget);
      expect(rides.getActiveRideCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('restaura DRIVER_ARRIVING completo desde cero', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVING');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('En camino al pasajero'), findsOneWidget);
      expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
      expect(find.text(ride.passenger!.firstName), findsOneWidget);
    });
  });

  group('Responsive', () {
    testWidgets('360x640 DRIVER_ASSIGNED sin overflow (datos largos)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpStressScenario(tester, status: 'DRIVER_ASSIGNED');
    });

    testWidgets('390x844 DRIVER_ARRIVING sin overflow (datos largos)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpStressScenario(tester, status: 'DRIVER_ARRIVING');
    });

    testWidgets('412x915 DRIVER_ASSIGNED con passenger null sin overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _pumpStressScenario(
        tester,
        status: 'DRIVER_ASSIGNED',
        passengerNull: true,
      );
    });
  });

  group('Cancelación del Driver (Checkpoint G1)', () {
    group('visibilidad del botón', () {
      testWidgets('DRIVER_ASSIGNED muestra "Cancelar viaje"', (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsOneWidget);
      });

      testWidgets('DRIVER_ARRIVING muestra "Cancelar viaje"', (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVING');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsOneWidget);
      });

      testWidgets('DRIVER_ARRIVED muestra "Cancelar viaje"', (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsOneWidget);
      });

      testWidgets('IN_PROGRESS NO muestra "Cancelar viaje"', (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        expect(find.text('Cancelar viaje'), findsNothing);
      });

      testWidgets('COMPLETED NO muestra "Cancelar viaje"', (tester) async {
        final ride = _rideFixture(status: 'IN_PROGRESS');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..completeRideQueue = [_completionFixture()];

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(
          find.text('Llegué al destino y finalizar viaje'),
        );
        await tester.tap(find.text('Llegué al destino y finalizar viaje'));
        await tester.pump();
        await tester.tap(find.text('Sí, finalizar viaje'));
        await tester.pump();
        await tester.pump();

        expect(find.text('¡Viaje completado!'), findsOneWidget);
        expect(find.text('Cancelar viaje'), findsNothing);
      });
    });

    group('selector de motivo', () {
      testWidgets(
        'muestra exactamente los 6 labels utilizables, sin PASSENGER_NOT_FOUND',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await tester.ensureVisible(find.text('Cancelar viaje'));
          await tester.tap(find.text('Cancelar viaje'));
          await tester.pumpAndSettle();

          expect(find.text('Selecciona un motivo'), findsOneWidget);

          for (final reason in DriverCancellationReason.values) {
            expect(find.text(reason.label), findsOneWidget);
          }

          expect(find.text('Pasajero no apareció'), findsNothing);
          expect(find.textContaining('PASSENGER_NOT_FOUND'), findsNothing);
          expect(find.textContaining('NOT_FOUND'), findsNothing);
        },
      );

      testWidgets('abrir el selector NO ejecuta cancelRide todavía', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(find.text('Cancelar viaje'));
        await tester.tap(find.text('Cancelar viaje'));
        await tester.pumpAndSettle();

        expect(rides.cancelRideCalls, 0);
      });
    });

    group('detalle opcional', () {
      testWidgets('vacío es válido: avanza a confirmación', (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(tester, reason: DriverCancellationReason.other);

        expect(find.text('¿Cancelar este viaje?'), findsOneWidget);
      });

      testWidgets(
        '1 a 4 caracteres: bloquea con error y NO abre confirmación',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await tester.ensureVisible(find.text('Cancelar viaje'));
          await tester.tap(find.text('Cancelar viaje'));
          await tester.pumpAndSettle();

          await tester.tap(find.text(DriverCancellationReason.other.label));
          await tester.pump();

          await tester.enterText(_cancelDetailFieldFinder, 'abc');
          await tester.tap(find.text('Continuar'));
          await tester.pump();

          expect(
            find.text('Escribe al menos 5 caracteres o deja el campo vacío.'),
            findsOneWidget,
          );
          expect(find.text('¿Cancelar este viaje?'), findsNothing);
        },
      );

      testWidgets('5 o más caracteres: válido, avanza a confirmación', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(
          tester,
          reason: DriverCancellationReason.other,
          detail: 'Motivo real explicado',
        );

        expect(find.text('¿Cancelar este viaje?'), findsOneWidget);
      });

      testWidgets('el campo respeta el máximo defensivo de 300 caracteres', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await tester.ensureVisible(find.text('Cancelar viaje'));
        await tester.tap(find.text('Cancelar viaje'));
        await tester.pumpAndSettle();

        final field = tester.widget<TextField>(_cancelDetailFieldFinder);

        expect(field.maxLength, 300);
      });
    });

    group('confirmación', () {
      testWidgets('Continuar abre confirmación sin llamar cancelRide todavía', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(tester, reason: DriverCancellationReason.other);

        expect(find.text('¿Cancelar este viaje?'), findsOneWidget);
        expect(find.textContaining('Motivo: Otro motivo'), findsOneWidget);
        expect(rides.cancelRideCalls, 0);
      });

      testWidgets('Volver cierra la confirmación sin llamar cancelRide', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(tester, reason: DriverCancellationReason.other);

        await tester.tap(find.text('Volver'));
        await tester.pumpAndSettle();

        expect(find.text('¿Cancelar este viaje?'), findsNothing);
        expect(rides.cancelRideCalls, 0);
        expect(find.text('Pasajero asignado'), findsOneWidget);
      });
    });

    group('éxito', () {
      testWidgets(
        'confirmar llama cancelRide exactamente una vez y navega a /home',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          final router = GoRouter(
            initialLocation: '/active-ride',
            routes: [
              GoRoute(
                path: '/active-ride',
                builder: (context, state) => const DriverActiveRideScreen(),
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
                driverRidesRepositoryProvider.overrideWithValue(rides),
                driverOperationsRepositoryProvider.overrideWithValue(
                  _FakeOperationsRepository(),
                ),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pump();

          await _openCancelFlow(
            tester,
            reason: DriverCancellationReason.vehicleProblem,
          );
          await _confirmCancel(tester);

          expect(rides.cancelRideCalls, 1);
          expect(
            rides.lastCancelReason,
            DriverCancellationReason.vehicleProblem,
          );
          expect(find.text('HOME_ROUTE'), findsOneWidget);
        },
      );

      testWidgets(
        'éxito: no dispara heartbeat/polling adicional tras llegar a Home '
        '(sin goOnline/goOffline manual)',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);
          final operations = _FakeOperationsRepository();

          final router = GoRouter(
            initialLocation: '/active-ride',
            routes: [
              GoRoute(
                path: '/active-ride',
                builder: (context, state) => const DriverActiveRideScreen(),
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
                driverRidesRepositoryProvider.overrideWithValue(rides),
                driverOperationsRepositoryProvider.overrideWithValue(
                  operations,
                ),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pump();

          await _openCancelFlow(
            tester,
            reason: DriverCancellationReason.vehicleProblem,
          );
          await _confirmCancel(tester);

          expect(find.text('HOME_ROUTE'), findsOneWidget);

          final activeRideCallsAfterCancel = rides.getActiveRideCalls;
          final heartbeatCallsAfterCancel = operations.heartbeatCalls;

          await tester.pump(const Duration(seconds: 30));

          expect(rides.getActiveRideCalls, activeRideCallsAfterCancel);
          expect(operations.heartbeatCalls, heartbeatCallsAfterCancel);
        },
      );

      testWidgets(
        'éxito: back stack no permite volver a la pantalla del viaje',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          final router = GoRouter(
            initialLocation: '/active-ride',
            routes: [
              GoRoute(
                path: '/active-ride',
                builder: (context, state) => const DriverActiveRideScreen(),
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
                driverRidesRepositoryProvider.overrideWithValue(rides),
                driverOperationsRepositoryProvider.overrideWithValue(
                  _FakeOperationsRepository(),
                ),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pump();

          await _openCancelFlow(
            tester,
            reason: DriverCancellationReason.vehicleProblem,
          );
          await _confirmCancel(tester);

          expect(find.text('HOME_ROUTE'), findsOneWidget);

          final canPop =
              router.routerDelegate.navigatorKey.currentState?.canPop() ??
              false;

          expect(canPop, isFalse);
        },
      );
    });

    group('loading / double tap', () {
      testWidgets(
        'mientras cancela, el CTA muestra "Cancelando..." y se deshabilita',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride])
            ..cancelRideGate = Completer<void>();

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await _openCancelFlow(tester, reason: DriverCancellationReason.other);

          await tester.tap(find.text('Sí, cancelar viaje'));
          await tester.pump();
          await tester.pump();

          expect(find.text('Cancelando...'), findsOneWidget);
          expect(find.text('Cancelar viaje'), findsNothing);

          final cancelButton = tester.widget<TextButton>(
            find.ancestor(
              of: find.text('Cancelando...'),
              matching: find.byType(TextButton),
            ),
          );

          expect(cancelButton.onPressed, isNull);

          rides.cancelRideGate!.complete();
          await tester.pump();
          await tester.pump();
        },
      );

      testWidgets('garantiza una sola llamada aunque el request tarde', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..cancelRideGate = Completer<void>();

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(tester, reason: DriverCancellationReason.other);

        await tester.tap(find.text('Sí, cancelar viaje'));
        await tester.pump();
        await tester.pump();

        expect(rides.cancelRideCalls, 1);

        rides.cancelRideGate!.complete();
        await tester.pump();
        await tester.pump();

        expect(rides.cancelRideCalls, 1);
      });
    });

    group('errores', () {
      testWidgets('network/5xx: la pantalla sigue activa y reanuda workers', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride])
          ..cancelRideResult = _dioNetworkError();

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();

        await _openCancelFlow(tester, reason: DriverCancellationReason.other);
        await _confirmCancel(tester);

        expect(find.text('Pasajero asignado'), findsOneWidget);
        expect(find.text('Cancelar viaje'), findsOneWidget);

        final activeRideCallsAfterFailure = rides.getActiveRideCalls;

        await tester.pump(const Duration(seconds: 3));

        expect(
          rides.getActiveRideCalls,
          greaterThan(activeRideCallsAfterFailure),
        );
      });

      testWidgets(
        '400: el estado ya no es cancelable, se reconcilia y oculta el botón',
        (tester) async {
          final assigned = _rideFixture(status: 'DRIVER_ASSIGNED');
          final inProgress = _rideFixture(status: 'IN_PROGRESS');
          final rides = _FakeRidesRepository(activeRideQueue: [assigned])
            ..cancelRideResult = _dioError(
              statusCode: 400,
              data: const {
                'message':
                    'El conductor ya no puede cancelar el viaje en su estado actual',
              },
            );

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await _openCancelFlow(tester, reason: DriverCancellationReason.other);

          rides.queueNextActiveRide(inProgress);

          await tester.tap(find.text('Sí, cancelar viaje'));
          await tester.pump();
          await tester.pump();
          await tester.pump();

          expect(find.text('Viaje en curso'), findsOneWidget);
          expect(find.text('Cancelar viaje'), findsNothing);
        },
      );

      testWidgets(
        '409: otra cancelación ganó la carrera, Ride ya es terminal -> Home',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride])
            ..cancelRideResult = _dioError(
              statusCode: 409,
              data: const {'message': 'El viaje ya fue cancelado'},
            );

          final router = GoRouter(
            initialLocation: '/active-ride',
            routes: [
              GoRoute(
                path: '/active-ride',
                builder: (context, state) => const DriverActiveRideScreen(),
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
                driverRidesRepositoryProvider.overrideWithValue(rides),
                driverOperationsRepositoryProvider.overrideWithValue(
                  _FakeOperationsRepository(),
                ),
              ],
              child: MaterialApp.router(routerConfig: router),
            ),
          );
          await tester.pump();

          await _openCancelFlow(tester, reason: DriverCancellationReason.other);

          rides.queueNextActiveRide(null);

          await tester.tap(find.text('Sí, cancelar viaje'));
          await tester.pump();
          await tester.pump();
          await tester.pump();

          expect(find.text('HOME_ROUTE'), findsOneWidget);
          expect(rides.cancelRideCalls, 1);
        },
      );
    });

    group('timers', () {
      testWidgets('éxito: no deja timers de la pantalla corriendo', (
        tester,
      ) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);
        final operations = _FakeOperationsRepository();

        final router = GoRouter(
          initialLocation: '/active-ride',
          routes: [
            GoRoute(
              path: '/active-ride',
              builder: (context, state) => const DriverActiveRideScreen(),
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
              driverRidesRepositoryProvider.overrideWithValue(rides),
              driverOperationsRepositoryProvider.overrideWithValue(operations),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();

        await _openCancelFlow(
          tester,
          reason: DriverCancellationReason.vehicleProblem,
        );
        await _confirmCancel(tester);

        expect(find.text('HOME_ROUTE'), findsOneWidget);

        final activeRideCallsAfterCancel = rides.getActiveRideCalls;
        final heartbeatCallsAfterCancel = operations.heartbeatCalls;

        await tester.pump(const Duration(seconds: 30));

        expect(rides.getActiveRideCalls, activeRideCallsAfterCancel);
        expect(operations.heartbeatCalls, heartbeatCallsAfterCancel);
      });

      testWidgets(
        'falla: reanuda el polling exactamente una vez (sin duplicar)',
        (tester) async {
          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride])
            ..cancelRideResult = _dioNetworkError();

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await _openCancelFlow(tester, reason: DriverCancellationReason.other);
          await _confirmCancel(tester);

          final callsBefore = rides.getActiveRideCalls;

          await tester.pump(const Duration(seconds: 3));

          // Un único timer de 3s activo tras la falla: exactamente una
          // llamada adicional, nunca dos (lo que delataría un timer
          // duplicado corriendo en paralelo).
          expect(rides.getActiveRideCalls, callsBefore + 1);
        },
      );
    });

    group('Responsive — flujo de cancelación', () {
      testWidgets(
        '360x640: selector de motivo con teclado abierto sin overflow',
        (tester) async {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
          final rides = _FakeRidesRepository(activeRideQueue: [ride]);

          await _pumpActiveRide(tester, rides: rides);
          await tester.pump();

          await tester.ensureVisible(find.text('Cancelar viaje'));
          await tester.tap(find.text('Cancelar viaje'));
          await tester.pumpAndSettle();

          await tester.tap(find.text(DriverCancellationReason.other.label));
          await tester.pump();

          await tester.enterText(
            _cancelDetailFieldFinder,
            'Motivo detallado bastante largo para probar overflow en '
            'pantallas pequeñas de verdad',
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('390x844: diálogo de confirmación sin overflow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ride = _rideFixture(status: 'DRIVER_ARRIVED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await _openCancelFlow(
          tester,
          reason: DriverCancellationReason.safetyConcern,
          detail:
              'Detalle largo para verificar que el diálogo no rompe '
              'el layout en una pantalla mediana',
        );

        expect(tester.takeException(), isNull);
        expect(find.text('¿Cancelar este viaje?'), findsOneWidget);
      });

      testWidgets(
        '412x915: botón secundario conviviendo con el CTA principal',
        (tester) async {
          tester.view.physicalSize = const Size(412, 915);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          await _pumpStressScenario(tester, status: 'DRIVER_ARRIVING');

          expect(find.text('Cancelar viaje'), findsOneWidget);
          expect(find.text('Llegué al punto de recojo'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    });
  });
}

Iterable<String> _visibleTexts(WidgetTester tester) {
  return tester.widgetList<Text>(find.byType(Text)).map((widget) {
    return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  });
}

Future<void> _pumpActiveRide(
  WidgetTester tester, {
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
      child: const MaterialApp(home: DriverActiveRideScreen()),
    ),
  );
}

/// El bottom sheet del selector puede convivir con el `TextField`
/// oculto del PIN (DRIVER_ARRIVED), así que nunca se usa
/// `find.byType(TextField)` a secas para el campo de detalle.
final Finder _cancelDetailFieldFinder = find.byKey(
  const Key('driver-cancel-detail-field'),
);

/// Abre el flujo de cancelación hasta el diálogo de confirmación:
/// tocar "Cancelar viaje" → elegir motivo → (opcional) escribir
/// detalle → tocar "Continuar". Nunca dispara el request real.
Future<void> _openCancelFlow(
  WidgetTester tester, {
  required DriverCancellationReason reason,
  String? detail,
}) async {
  await tester.ensureVisible(find.text('Cancelar viaje'));
  await tester.tap(find.text('Cancelar viaje'));
  await tester.pumpAndSettle();

  await tester.tap(find.text(reason.label));
  await tester.pump();

  if (detail != null) {
    await tester.enterText(_cancelDetailFieldFinder, detail);
    await tester.pump();
  }

  await tester.tap(find.text('Continuar'));
  await tester.pumpAndSettle();
}

/// Toca "Sí, cancelar viaje" en el diálogo de confirmación ya abierto
/// y deja pasar los pumps suficientes para que el request (no
/// gateado) resuelva.
Future<void> _confirmCancel(WidgetTester tester) async {
  await tester.tap(find.text('Sí, cancelar viaje'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpStressScenario(
  WidgetTester tester, {
  required String status,
  bool passengerNull = false,
}) async {
  final ride = _rideFixture(
    status: status,
    agreedFare: '125.50',
    originAddress:
        'Jirón Los Álamos Sur 1234, Urbanización Las Palmeras del Este, Tarapoto',
    destinationAddress:
        'Avenida Circunvalación Norte 5678, Sector Industrial La Molina, Morales',
    passenger: passengerNull
        ? null
        : const AssignedPassenger(
            profileId: 'passenger-1',
            firstName: 'Guillermina Alejandra del Rosario',
            ratingAverage: '4.90',
            ratingCount: 1874,
          ),
    distanceToOriginMeters: 12800,
  );

  final rides = _FakeRidesRepository(activeRideQueue: [ride]);

  await _pumpActiveRide(tester, rides: rides);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(tester.takeException(), isNull);
}

Future<void> _pumpArrivedStressScenario(WidgetTester tester) async {
  final ride = _rideFixture(
    status: 'DRIVER_ARRIVED',
    agreedFare: '125.50',
    originAddress:
        'Jirón Los Álamos Sur 1234, Urbanización Las Palmeras del Este, Tarapoto',
    destinationAddress:
        'Avenida Circunvalación Norte 5678, Sector Industrial La Molina, Morales',
    passenger: const AssignedPassenger(
      profileId: 'passenger-1',
      firstName: 'Guillermina Alejandra del Rosario',
      ratingAverage: '4.90',
      ratingCount: 1874,
    ),
  );

  final rides = _FakeRidesRepository(activeRideQueue: [ride])
    ..startRideQueue = [
      _dioError(
        statusCode: 400,
        data: const {
          'message': 'El código de inicio es incorrecto',
          'remainingAttempts': 3,
        },
      ),
    ];

  await _pumpActiveRide(tester, rides: rides);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(tester.takeException(), isNull);

  await tester.enterText(find.byType(TextField), '1234');
  await tester.pump();

  expect(tester.takeException(), isNull);

  await tester.ensureVisible(find.text('Iniciar viaje'));
  await tester.tap(find.text('Iniciar viaje'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(tester.takeException(), isNull);
}

Future<void> _pumpInProgressStressScenario(WidgetTester tester) async {
  final ride = _rideFixture(
    status: 'IN_PROGRESS',
    agreedFare: '125.50',
    destinationAddress:
        'Avenida Circunvalación Norte 5678, Sector Industrial La Molina, Morales',
    passenger: const AssignedPassenger(
      profileId: 'passenger-1',
      firstName: 'Guillermina Alejandra del Rosario',
      ratingAverage: '4.90',
      ratingCount: 1874,
    ),
  );

  final rides = _FakeRidesRepository(activeRideQueue: [ride])
    ..completeRideQueue = [
      _dioError(
        statusCode: 400,
        data: const {
          'message': 'Debes estar cerca del destino',
          'distanceToDestinationMeters': 340,
          'maximumCompletionDistanceMeters': 250,
        },
      ),
    ];

  await _pumpActiveRide(tester, rides: rides);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(tester.takeException(), isNull);

  await tester.ensureVisible(find.text('Llegué al destino y finalizar viaje'));
  await tester.tap(find.text('Llegué al destino y finalizar viaje'));
  await tester.pump();

  expect(tester.takeException(), isNull);

  await tester.tap(find.text('Sí, finalizar viaje'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  expect(tester.takeException(), isNull);
}

DriverRideCompletion _completionFixture({
  String rideId = 'ride-1',
  String finalFare = '8.00',
  String passengerAmountDue = '8.00',
  num actualDistanceMeters = 3200,
  num actualDurationSeconds = 780,
  String paymentMethod = 'CASH',
  String paymentStatus = 'PENDING',
}) {
  return DriverRideCompletion(
    rideId: rideId,
    status: 'COMPLETED',
    completedAt: DateTime.utc(2026, 8, 10, 12),
    actualDistanceMeters: actualDistanceMeters,
    actualDurationSeconds: actualDurationSeconds,
    estimatedFare: '8.00',
    finalFare: finalFare,
    discountAmount: '0.00',
    passengerAmountDue: passengerAmountDue,
    currency: 'PEN',
    fareWasCapped: false,
    paymentMethod: paymentMethod,
    paymentStatus: paymentStatus,
  );
}

Finder _pinBoxFinder(int index) => find.byKey(ValueKey('pin-box-$index'));

String _pinBoxDigit(WidgetTester tester, int index) {
  final textFinder = find.descendant(
    of: _pinBoxFinder(index),
    matching: find.byType(Text),
  );
  final text = tester.widget<Text>(textFinder);

  return text.data ?? '';
}

FilledButton _startButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton));
}

DioException _dioError({required int statusCode, Object? data}) {
  final requestOptions = RequestOptions(path: 'drivers/me/rides/ride-1/start');

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
    requestOptions: RequestOptions(path: 'drivers/me/rides/ride-1/start'),
    type: DioExceptionType.connectionError,
  );
}

Position _fakePosition({
  double lat = -6.4879,
  double lng = -76.3601,
  double accuracy = 8,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.utc(2026, 8, 10),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

class _DefaultPassenger {
  const _DefaultPassenger();
}

DriverActiveRide _rideFixture({
  String id = 'ride-1',
  required String status,
  String? agreedFare = '8.00',
  String estimatedFare = '7.50',
  num? distanceToOriginMeters = 650,
  Object? passenger = const _DefaultPassenger(),
  double? originLatitude = -6.4877,
  double? originLongitude = -76.3599,
  double? destinationLatitude = -6.4812,
  double? destinationLongitude = -76.3655,
  String originAddress = 'Jr. Lima 250, Tarapoto',
  String destinationAddress = 'Plaza de Armas de Morales',
}) {
  final resolvedPassenger = passenger is _DefaultPassenger
      ? const AssignedPassenger(
          profileId: 'passenger-1',
          firstName: 'María',
          ratingAverage: '4.85',
          ratingCount: 32,
        )
      : passenger as AssignedPassenger?;

  return DriverActiveRide(
    id: id,
    status: status,
    estimatedFare: estimatedFare,
    agreedFare: agreedFare,
    currency: 'PEN',
    originAddress: originAddress,
    destinationAddress: destinationAddress,
    originLatitude: originLatitude,
    originLongitude: originLongitude,
    destinationLatitude: destinationLatitude,
    destinationLongitude: destinationLongitude,
    distanceMeters: 3200,
    estimatedDurationSeconds: 720,
    distanceToOriginMeters: distanceToOriginMeters,
    passenger: resolvedPassenger,
  );
}

DriverRideWaiting _waitingFixture({
  String rideId = 'ride-1',
  DateTime? waitingStartedAt,
  DateTime? noShowAvailableAt,
  num requiredWaitingSeconds = 300,
  num elapsedWaitingSeconds = 60,
  num remainingWaitingSeconds = 240,
  bool canReportNoShow = false,
  num? startDistanceMeters = 40,
}) {
  return DriverRideWaiting(
    rideId: rideId,
    waitingStartedAt: waitingStartedAt ?? DateTime.utc(2026, 8, 10, 12),
    noShowAvailableAt: noShowAvailableAt ?? DateTime.utc(2026, 8, 10, 12, 5),
    requiredWaitingSeconds: requiredWaitingSeconds,
    elapsedWaitingSeconds: elapsedWaitingSeconds,
    remainingWaitingSeconds: remainingWaitingSeconds,
    canReportNoShow: canReportNoShow,
    startDistanceMeters: startDistanceMeters,
  );
}

class _FakeRidesRepository extends DriverRidesRepository {
  _FakeRidesRepository({List<Object?>? activeRideQueue})
    : _activeRideQueue = List.of(activeRideQueue ?? const [null]),
      super(Dio());

  final List<Object?> _activeRideQueue;

  int getActiveRideCalls = 0;
  int startArrivalCalls = 0;
  int arriveCalls = 0;
  int startRideCalls = 0;
  int completeRideCalls = 0;
  int cancelRideCalls = 0;

  Completer<DriverActiveRide>? startArrivalGate;
  Completer<DriverActiveRide>? arriveGate;
  Completer<DriverActiveRide>? startRideGate;
  Completer<DriverRideCompletion>? completeRideGate;
  Completer<void>? cancelRideGate;

  /// `null` => éxito. [DioException] => se relanza tal cual.
  Object? cancelRideResult;

  DriverCancellationReason? lastCancelReason;
  String? lastCancelReasonDetail;

  bool _hasNextActiveRideOverride = false;
  Object? _nextActiveRideOverride;

  /// Fuerza lo que devuelve la PRÓXIMA llamada a `getActiveRide()`
  /// (usado para simular la reconciliación tras 409: el Driver vuelve
  /// a consultar y Backend ya no tiene el Ride activo, o ya avanzó a
  /// otro estado). `value` puede ser `null` (sin ride activo),
  /// [DriverActiveRide] o [DioException].
  void queueNextActiveRide(Object? value) {
    _hasNextActiveRideOverride = true;
    _nextActiveRideOverride = value;
  }

  /// Elemento: [DriverRideCompletion] (éxito) o [DioException] (falla).
  /// Si tiene un solo elemento, se repite en cada llamada.
  List<Object>? completeRideQueue;

  DriverActiveRide? startArrivalResult;
  DriverActiveRide? arriveResult;

  /// Elemento: [DriverActiveRide] (éxito) o [DioException] (falla).
  /// Si tiene un solo elemento, se repite en cada llamada.
  List<Object>? startRideQueue;

  String? lastStartRideCode;

  @override
  Future<DriverActiveRide?> getActiveRide() async {
    getActiveRideCalls++;

    if (_hasNextActiveRideOverride) {
      _hasNextActiveRideOverride = false;

      final override = _nextActiveRideOverride;

      if (override is DioException) {
        throw override;
      }

      return override as DriverActiveRide?;
    }

    final next = _activeRideQueue.length > 1
        ? _activeRideQueue.removeAt(0)
        : _activeRideQueue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverActiveRide?;
  }

  @override
  Future<void> cancelRide({
    required String rideId,
    required DriverCancellationReason reason,
    String? reasonDetail,
  }) async {
    cancelRideCalls++;
    lastCancelReason = reason;
    lastCancelReasonDetail = reasonDetail;

    final gate = cancelRideGate;

    if (gate != null) {
      return gate.future;
    }

    final result = cancelRideResult;

    if (result is DioException) {
      throw result;
    }
  }

  @override
  Future<DriverActiveRide> startArrival(String rideId) async {
    startArrivalCalls++;

    final gate = startArrivalGate;

    if (gate != null) {
      return gate.future;
    }

    return startArrivalResult!;
  }

  @override
  Future<DriverActiveRide> arrive(String rideId) async {
    arriveCalls++;

    final gate = arriveGate;

    if (gate != null) {
      return gate.future;
    }

    return arriveResult!;
  }

  @override
  Future<DriverActiveRide> startRide({
    required String rideId,
    required String code,
  }) async {
    startRideCalls++;
    lastStartRideCode = code;

    final gate = startRideGate;

    if (gate != null) {
      return gate.future;
    }

    final queue = startRideQueue;

    if (queue == null || queue.isEmpty) {
      throw StateError('startRideQueue no configurado en el fake');
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverActiveRide;
  }

  @override
  Future<DriverRideCompletion> completeRide({required String rideId}) async {
    completeRideCalls++;

    final gate = completeRideGate;

    if (gate != null) {
      return gate.future;
    }

    final queue = completeRideQueue;

    if (queue == null || queue.isEmpty) {
      throw StateError('completeRideQueue no configurado en el fake');
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverRideCompletion;
  }

  // ---------------------------------------------------------------------
  // RideWaiting / Passenger No-show — Checkpoint G2
  // ---------------------------------------------------------------------

  int getRideWaitingCalls = 0;
  int startRideWaitingCalls = 0;
  int reportPassengerNoShowCalls = 0;

  Completer<DriverRideWaiting?>? getRideWaitingGate;
  Completer<DriverRideWaiting>? startRideWaitingGate;
  Completer<void>? reportPassengerNoShowGate;

  /// Elemento: [DriverRideWaiting] o `null` (sin espera activa) o
  /// [DioException] (falla). `null` como lista completa (no
  /// configurada) también equivale a "sin espera activa": la mayoría
  /// de los tests de DRIVER_ARRIVED no les interesa el flujo de
  /// espera y no deberían tener que configurarlo.
  List<Object?>? getRideWaitingQueue;

  /// Elemento: [DriverRideWaiting] (éxito) o [DioException] (falla).
  List<Object>? startRideWaitingQueue;

  /// `null` => éxito. [DioException] => se relanza tal cual.
  Object? reportPassengerNoShowResult;

  @override
  Future<DriverRideWaiting?> getRideWaiting(String rideId) async {
    getRideWaitingCalls++;

    final gate = getRideWaitingGate;

    if (gate != null) {
      return gate.future;
    }

    final queue = getRideWaitingQueue;

    if (queue == null || queue.isEmpty) {
      return null;
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverRideWaiting?;
  }

  @override
  Future<DriverRideWaiting> startRideWaiting(String rideId) async {
    startRideWaitingCalls++;

    final gate = startRideWaitingGate;

    if (gate != null) {
      return gate.future;
    }

    final queue = startRideWaitingQueue;

    if (queue == null || queue.isEmpty) {
      throw StateError('startRideWaitingQueue no configurado en el fake');
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverRideWaiting;
  }

  @override
  Future<void> reportPassengerNoShow(String rideId) async {
    reportPassengerNoShowCalls++;

    final gate = reportPassengerNoShowGate;

    if (gate != null) {
      return gate.future;
    }

    final result = reportPassengerNoShowResult;

    if (result is DioException) {
      throw result;
    }
  }
}

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository() : super(Dio());

  /// Mutable a propósito: algunos tests (Checkpoint F1) la asignan
  /// después de montar la pantalla, para simular un heartbeat que
  /// empieza a fallar recién en un ciclo posterior.
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

    return const DriverOperationalState(status: DriverOperationalStatus.busy);
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
