import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:driver/features/driver/presentation/driver_home_map.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    driverHomeMapBuilderOverride = null;
  });

  Position position({double lat = -12.046, double lng = -77.042}) {
    return Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.utc(2026, 8, 10),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  group('Sin Position válida', () {
    testWidgets('acquiring muestra "Obteniendo tu ubicación..."', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverHomeMap(
            position: null,
            myLocationEnabled: false,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      expect(find.text('Obteniendo tu ubicación...'), findsOneWidget);
    });

    testWidgets(
      'offline (sin adquisición en curso) NO dice "Obteniendo tu ubicación..."',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: DriverHomeMap(
              position: null,
              myLocationEnabled: false,
              fallback: DriverHomeMapFallback.offline,
            ),
          ),
        );

        expect(
          find.text('Conéctate para activar tu ubicación'),
          findsOneWidget,
        );
        expect(find.text('Obteniendo tu ubicación...'), findsNothing);
      },
    );

    testWidgets('serviceDisabled invita a activar la ubicación', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverHomeMap(
            position: null,
            myLocationEnabled: false,
            fallback: DriverHomeMapFallback.serviceDisabled,
          ),
        ),
      );

      expect(
        find.text('Activa la ubicación de tu dispositivo'),
        findsOneWidget,
      );
    });

    testWidgets('permissionDenied pide el permiso', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverHomeMap(
            position: null,
            myLocationEnabled: false,
            fallback: DriverHomeMapFallback.permissionDenied,
          ),
        ),
      );

      expect(find.text('Permite el acceso a tu ubicación'), findsOneWidget);
    });

    testWidgets('permissionDeniedForever remite a Ajustes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DriverHomeMap(
            position: null,
            myLocationEnabled: false,
            fallback: DriverHomeMapFallback.permissionDeniedForever,
          ),
        ),
      );

      expect(
        find.text('Habilita la ubicación desde Ajustes del dispositivo'),
        findsOneWidget,
      );
    });

    testWidgets('nunca construye un marker ni el mapa real sin Position', (
      tester,
    ) async {
      var builderCalls = 0;

      driverHomeMapBuilderOverride = (context, resolved) {
        builderCalls++;
        return const SizedBox.shrink();
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: DriverHomeMap(
            position: null,
            myLocationEnabled: false,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      // El fallback nunca invoca el builder del mapa: no hay
      // marker ni coordenada ficticia en juego.
      expect(builderCalls, 0);
    });

    testWidgets(
      'A: sin Position no se construye GoogleMap (ni su punto azul)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: DriverHomeMap(
              position: null,
              // Aunque Home diga que sería "seguro", sin Position no
              // hay mapa real que pueda mostrar el punto azul.
              myLocationEnabled: true,
              fallback: DriverHomeMapFallback.offline,
            ),
          ),
        );

        expect(find.byType(GoogleMap), findsNothing);
      },
    );
  });

  group('Con Position válida', () {
    testWidgets('resuelve el target con las coordenadas reales', (
      tester,
    ) async {
      DriverHomeMapResolved? resolved;

      driverHomeMapBuilderOverride = (context, config) {
        resolved = config;
        return const SizedBox.shrink();
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeMap(
            position: position(lat: -12.111, lng: -77.222),
            myLocationEnabled: true,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      expect(resolved, isNotNull);
      expect(resolved!.target.latitude, -12.111);
      expect(resolved!.target.longitude, -77.222);
    });

    testWidgets('actualizar la Position actualiza el target', (tester) async {
      final resolvedHistory = <DriverHomeMapResolved>[];

      driverHomeMapBuilderOverride = (context, config) {
        resolvedHistory.add(config);
        return const SizedBox.shrink();
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeMap(
            position: position(lat: -12.0, lng: -77.0),
            myLocationEnabled: true,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeMap(
            position: position(lat: -13.5, lng: -76.5),
            myLocationEnabled: true,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      expect(resolvedHistory, hasLength(2));
      expect(resolvedHistory.first.target.latitude, -12.0);
      expect(resolvedHistory.last.target.latitude, -13.5);
    });

    testWidgets('F: ya NO existe un marker naranja propio para el Driver', (
      tester,
    ) async {
      DriverHomeMapResolved? resolved;

      driverHomeMapBuilderOverride = (context, config) {
        resolved = config;
        return const SizedBox.shrink();
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeMap(
            position: position(lat: -8.383, lng: -74.567),
            myLocationEnabled: true,
            fallback: DriverHomeMapFallback.acquiring,
          ),
        ),
      );

      // Sin self-marker: la ubicación propia se representa con el
      // punto azul nativo (myLocationEnabled), no con un Marker.
      expect(resolved!.markers, isEmpty);
    });

    testWidgets(
      'los markers reales (pickup/destino) provistos por el padre se exponen tal cual',
      (tester) async {
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        final rideMarkers = <Marker>{
          const Marker(
            markerId: MarkerId('active-ride-origin'),
            position: LatLng(-6.4877, -76.3599),
          ),
          const Marker(
            markerId: MarkerId('active-ride-destination'),
            position: LatLng(-6.4812, -76.3655),
          ),
        };

        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              markers: rideMarkers,
            ),
          ),
        );

        expect(resolved!.markers, rideMarkers);
        expect(resolved!.markers, hasLength(2));
      },
    );

    testWidgets(
      'G: el campo markers sigue existiendo para pins reales futuros (pickup/destino)',
      (tester) async {
        // No se agrega todavía ningún caller que lo llene (fuera de
        // alcance de este checkpoint), pero el tipo Set<Marker> y su
        // cableado hacia GoogleMap(markers: ...) se conservan: no se
        // eliminó la infraestructura general de markers.
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: false,
              fallback: DriverHomeMapFallback.acquiring,
            ),
          ),
        );

        expect(resolved!.markers, isA<Set<Marker>>());
      },
    );

    testWidgets(
      'B: con Position y myLocationEnabled=true, el GoogleMap real lo recibe activado',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              fallback: DriverHomeMapFallback.acquiring,
            ),
          ),
        );

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.myLocationEnabled, isTrue);
        // Igual que Passenger: sin botón nativo. El recenter es un
        // botón custom propio de Home, no el de Google Maps.
        expect(map.myLocationButtonEnabled, isFalse);
      },
    );

    testWidgets(
      'A: con Position pero myLocationEnabled=false, el GoogleMap real lo recibe desactivado',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: false,
              fallback: DriverHomeMapFallback.acquiring,
            ),
          ),
        );

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.myLocationEnabled, isFalse);
        expect(map.myLocationButtonEnabled, isFalse);
      },
    );
  });

  group('DriverMapCameraRequest (value equality)', () {
    test('mismo id/target/zoom son == entre sí', () {
      const a = DriverMapCameraRequest(
        id: 1,
        target: LatLng(-12.05, -77.05),
        zoom: 16.5,
      );
      const b = DriverMapCameraRequest(
        id: 1,
        target: LatLng(-12.05, -77.05),
        zoom: 16.5,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('distinto id (mismo target) NO son ==', () {
      const a = DriverMapCameraRequest(id: 1, target: LatLng(-12.05, -77.05));
      const b = DriverMapCameraRequest(id: 2, target: LatLng(-12.05, -77.05));

      expect(a, isNot(b));
    });

    test('secondaryTarget distinto (mismo id/target) NO son ==', () {
      const a = DriverMapCameraRequest(
        id: 1,
        target: LatLng(-12.05, -77.05),
        secondaryTarget: LatLng(-12.06, -77.06),
      );
      const b = DriverMapCameraRequest(id: 1, target: LatLng(-12.05, -77.05));

      expect(a, isNot(b));
    });

    test('mismo secondaryTarget también entra en la igualdad', () {
      const a = DriverMapCameraRequest(
        id: 1,
        target: LatLng(-12.05, -77.05),
        secondaryTarget: LatLng(-12.06, -77.06),
      );
      const b = DriverMapCameraRequest(
        id: 1,
        target: LatLng(-12.05, -77.05),
        secondaryTarget: LatLng(-12.06, -77.06),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('Camera request declarativo (sin GoogleMapController propio)', () {
    testWidgets('sin cameraRequest, el resolved lo expone en null', (
      tester,
    ) async {
      DriverHomeMapResolved? resolved;

      driverHomeMapBuilderOverride = (context, config) {
        resolved = config;
        return const SizedBox.shrink();
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DriverHomeMap(position: position(), myLocationEnabled: true),
        ),
      );

      expect(resolved!.cameraRequest, isNull);
    });

    testWidgets(
      'el cameraRequest recibido se expone tal cual en DriverHomeMapResolved',
      (tester) async {
        const request = DriverMapCameraRequest(
          id: 1,
          target: LatLng(-8.5, -74.9),
        );
        DriverHomeMapResolved? resolved;

        driverHomeMapBuilderOverride = (context, config) {
          resolved = config;
          return const SizedBox.shrink();
        };

        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              cameraRequest: request,
            ),
          ),
        );

        expect(resolved!.cameraRequest, request);
      },
    );

    testWidgets(
      'O/P/Q: cambiar solo el cameraRequest (misma Position) NO altera el '
      'target resuelto — ni offset ni transformación geográfica',
      (tester) async {
        final resolvedHistory = <DriverHomeMapResolved>[];

        driverHomeMapBuilderOverride = (context, config) {
          resolvedHistory.add(config);
          return const SizedBox.shrink();
        };

        final fixedPosition = position(lat: -12.3, lng: -77.6);

        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: fixedPosition,
              myLocationEnabled: true,
              cameraRequest: const DriverMapCameraRequest(
                id: 1,
                target: LatLng(-12.3, -77.6),
              ),
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: fixedPosition,
              myLocationEnabled: true,
              cameraRequest: const DriverMapCameraRequest(
                id: 2,
                target: LatLng(-12.3, -77.6),
              ),
            ),
          ),
        );

        expect(resolvedHistory, hasLength(2));
        expect(
          resolvedHistory.last.target.latitude,
          resolvedHistory.first.target.latitude,
        );
        expect(
          resolvedHistory.last.target.longitude,
          resolvedHistory.first.target.longitude,
        );
        expect(
          resolvedHistory.last.cameraRequest,
          isNot(resolvedHistory.first.cameraRequest),
        );
      },
    );

    testWidgets(
      'F/G: sin controller nativo disponible (como en este entorno de test), '
      'recibir un cameraRequest nuevo nunca lanza una excepción',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              cameraRequest: const DriverMapCameraRequest(
                id: 1,
                target: LatLng(-12.05, -77.05),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        // Un segundo pedido (id nuevo) sin controller: sigue sin
        // lanzar. Cubre el caso "pedido pendiente" — DriverHomeMap
        // nunca asume que ya existe un GoogleMapController vivo.
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              cameraRequest: const DriverMapCameraRequest(
                id: 2,
                target: LatLng(-8.1, -79.0),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'un cameraRequest con secondaryTarget (bounds Driver+pickup) tampoco lanza excepción',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(
              position: position(),
              myLocationEnabled: true,
              cameraRequest: const DriverMapCameraRequest(
                id: 1,
                target: LatLng(-12.05, -77.05),
                secondaryTarget: LatLng(-12.06, -77.06),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'J: 3 ciclos Position→null→Position (equivalente a connect/disconnect/'
      'reconnect) no producen ninguna excepción',
      (tester) async {
        Future<void> pumpWith(Position? value) => tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(position: value, myLocationEnabled: true),
          ),
        );

        for (var cycle = 0; cycle < 3; cycle++) {
          await pumpWith(position(lat: -12.0 - cycle, lng: -77.0 - cycle));
          expect(tester.takeException(), isNull);

          await pumpWith(null);
          expect(tester.takeException(), isNull);
        }

        await pumpWith(position());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'desmontar DriverHomeMap por completo (logout) no lanza excepción',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DriverHomeMap(position: position(), myLocationEnabled: true),
          ),
        );

        await tester.pumpWidget(const SizedBox.shrink());

        expect(tester.takeException(), isNull);
      },
    );
  });
}
