import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_active_ride.dart';
import 'package:driver/features/driver/domain/driver_assigned_passenger.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
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

    testWidgets('D: muestra agreedFare real (no estimatedFare)', (tester) async {
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
      expect(RegExp(r'\d+\s*min\b', caseSensitive: false).hasMatch(texts), isFalse);
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

    testWidgets('J: NO muestra Cancelar viaje', (tester) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Cancelar viaje'), findsNothing);
      expect(find.textContaining('Cancelar'), findsNothing);
    });

    testWidgets('K: CTA llama startArrival exactamente una vez', (tester) async {
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

    testWidgets(
      'L: no cambia status localmente antes de la respuesta real',
      (tester) async {
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
      },
    );
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
      expect(RegExp(r'\d+\s*min\b', caseSensitive: false).hasMatch(texts), isFalse);
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

      expect(
        find.text('Pide el código de 4 dígitos a Maycol'),
        findsOneWidget,
      );
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
      expect(find.textContaining('Pide el código de 4 dígitos a'), findsNothing);
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
      expect(
        find.text('Llegué al destino y finalizar viaje'),
        findsOneWidget,
      );
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

    testWidgets(
      'último intento: singular "1 intento restante", nunca plural',
      (tester) async {
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
      },
    );

    testWidgets('410: código vencido, no navega a IN_PROGRESS', (
      tester,
    ) async {
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

    testWidgets(
      '423: código bloqueado, deja el submit deshabilitado',
      (tester) async {
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
      },
    );

    testWidgets(
      '400 de GPS/distancia NO se muestra como "Código incorrecto"',
      (tester) async {
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
      },
    );

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
      expect(
        find.text('Llegué al destino y finalizar viaje'),
        findsOneWidget,
      );
    });

    testWidgets('restore: monta directo en DRIVER_ARRIVED sin pasar por otros estados', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ARRIVED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('¡Llegaste!'), findsOneWidget);
      expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
      expect(find.text(ride.passenger!.firstName), findsOneWidget);
      expect(rides.getActiveRideCalls, greaterThanOrEqualTo(1));
    });

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

    testWidgets(
      'sin ninguna coordenada válida, no se fabrica ningún marker',
      (tester) async {
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
      },
    );

    testWidgets(
      'la cámara se encuadra una sola vez (Driver + pickup) sin reencuadrar en cada poll',
      (tester) async {
        final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
        final rides = _FakeRidesRepository(activeRideQueue: [ride]);

        await _pumpActiveRide(tester, rides: rides);
        await tester.pump();
        await tester.pump();

        final dynamic state = tester.state(
          find.byType(DriverActiveRideScreen),
        );

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
    testWidgets('restaura DRIVER_ASSIGNED completo desde cero', (
      tester,
    ) async {
      final ride = _rideFixture(status: 'DRIVER_ASSIGNED');
      final rides = _FakeRidesRepository(activeRideQueue: [ride]);

      await _pumpActiveRide(tester, rides: rides);
      await tester.pump();

      expect(find.text('Pasajero asignado'), findsOneWidget);
      expect(find.text('S/ ${ride.displayFare}'), findsOneWidget);
      expect(find.text(ride.passenger!.firstName), findsOneWidget);
      expect(rides.getActiveRideCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('restaura DRIVER_ARRIVING completo desde cero', (
      tester,
    ) async {
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

    testWidgets(
      '412x915 DRIVER_ASSIGNED con passenger null sin overflow',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await _pumpStressScenario(
          tester,
          status: 'DRIVER_ASSIGNED',
          passengerNull: true,
        );
      },
    );
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
  final requestOptions = RequestOptions(
    path: 'drivers/me/rides/ride-1/start',
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

class _FakeRidesRepository extends DriverRidesRepository {
  _FakeRidesRepository({List<Object?>? activeRideQueue})
    : _activeRideQueue = List.of(activeRideQueue ?? const [null]),
      super(Dio());

  final List<Object?> _activeRideQueue;

  int getActiveRideCalls = 0;
  int startArrivalCalls = 0;
  int arriveCalls = 0;
  int startRideCalls = 0;

  Completer<DriverActiveRide>? startArrivalGate;
  Completer<DriverActiveRide>? arriveGate;
  Completer<DriverActiveRide>? startRideGate;

  DriverActiveRide? startArrivalResult;
  DriverActiveRide? arriveResult;

  /// Elemento: [DriverActiveRide] (éxito) o [DioException] (falla).
  /// Si tiene un solo elemento, se repite en cada llamada.
  List<Object>? startRideQueue;

  String? lastStartRideCode;

  @override
  Future<DriverActiveRide?> getActiveRide() async {
    getActiveRideCalls++;

    final next = _activeRideQueue.length > 1
        ? _activeRideQueue.removeAt(0)
        : _activeRideQueue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverActiveRide?;
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
}

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository() : super(Dio());

  int heartbeatCalls = 0;
  int updateLocationCalls = 0;

  @override
  Future<DriverOperationalState> heartbeat() async {
    heartbeatCalls++;

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
