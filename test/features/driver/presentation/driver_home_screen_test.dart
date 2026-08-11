import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/core/storage/secure_storage.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/data/driver_offers_repository.dart';
import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_active_ride.dart';
import 'package:driver/features/driver/domain/driver_daily_stats.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
import 'package:driver/features/driver/domain/driver_pending_proposal.dart';
import 'package:driver/features/driver/domain/driver_ride_offer.dart';
import 'package:driver/features/driver/presentation/driver_home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> secureStorageData;

  setUp(() {
    driverHomeGpsFetcherOverride = ({required requestPermission}) async {
      return _fakePosition();
    };

    // Por defecto simulamos una sesión válida: el accessToken sigue
    // presente. Los tests de 401 definitivo lo eliminan explícitamente
    // para simular que AuthInterceptor ya lo borró.
    secureStorageData = {StorageKeys.accessToken: 'valid-access-token'};
    FlutterSecureStorage.setMockInitialValues(secureStorageData);
  });

  tearDown(() {
    driverHomeGpsFetcherOverride = null;
  });

  testWidgets(
    'A: restore con active ride navega a /active-ride sin consultar operational status',
    (tester) async {
      final rides = _FakeRidesRepository(activeRideQueue: [_activeRide()]);
      final operations = _FakeOperationsRepository();
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('ACTIVE_RIDE_ROUTE'), findsOneWidget);
      expect(operations.getStatusCalls, 0);
    },
  );

  testWidgets(
    'B: restore OFFLINE muestra Home desconectado y no arranca workers',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(status: DriverOperationalStatus.offline),
        ],
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Estás desconectado'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 3));

      expect(operations.heartbeatCalls, 0);
      expect(offers.pendingProposalsCalls, 0);
      expect(offers.activeOffersCalls, 0);
    },
  );

  testWidgets(
    'C: restore AVAILABLE recupera presencia, guarda connectedAt/lastSeenAt y publica GPS',
    (tester) async {
      final connectedAt = DateTime.utc(2026, 8, 10, 9);

      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          DriverOperationalState(
            status: DriverOperationalStatus.available,
            connectedAt: connectedAt,
            lastSeenAt: connectedAt,
          ),
        ],
        heartbeatQueue: [
          DriverOperationalState(
            status: DriverOperationalStatus.available,
            connectedAt: connectedAt,
            lastSeenAt: DateTime.utc(2026, 8, 10, 9, 5),
          ),
        ],
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Estás disponible'), findsOneWidget);

      final dynamic state = tester.state(find.byType(DriverHomeScreen));
      expect(state.debugOperationalState.connectedAt, connectedAt);
      expect(
        state.debugOperationalState.status,
        DriverOperationalStatus.available,
      );
      expect(state.debugLastPosition, isNotNull);
      expect(operations.updateLocationCalls, 1);
      expect(operations.heartbeatCalls, 1);
    },
  );

  testWidgets('D: restore BUSY con active ride navega a /active-ride', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(activeRideQueue: [null, _activeRide()]);
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.busy),
      ],
    );
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('ACTIVE_RIDE_ROUTE'), findsOneWidget);
    expect(rides.getActiveRideCalls, 2);
  });

  testWidgets('E: BUSY sin active ride (404) no se disfraza de desconectado', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(activeRideQueue: [null, null]);
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.busy),
      ],
    );
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('Recuperando tu viaje...'), findsOneWidget);
    expect(find.text('Estás desconectado'), findsNothing);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugStatus, DriverHomeStatus.busyRecovery);
  });

  testWidgets('F: error de red durante restore muestra ERROR, no OFFLINE', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      activeRideQueue: [
        DioException(
          requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
          type: DioExceptionType.connectionError,
        ),
      ],
    );
    final operations = _FakeOperationsRepository();
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('No pudimos recuperar tu estado'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Estás desconectado'), findsNothing);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugStatus, DriverHomeStatus.error);
  });

  testWidgets('J: un fallo de daily stats no bloquea ni rompe Home', (
    tester,
  ) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.offline),
      ],
      dailyStatsResult: Exception('network'),
    );
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('Estás desconectado'), findsOneWidget);
    expect(
      find.text('No se pudieron cargar tus estadísticas de hoy.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('K: pending proposals vacío no fuerza la vista de propuesta', (
    tester,
  ) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      pendingProposalsQueue: [const <DriverPendingProposal>[]],
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('Estás disponible'), findsOneWidget);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugPendingProposals, isEmpty);
  });

  testWidgets(
    'L / N: una propuesta PROPOSED se recupera del servidor sin id local previo (restart conceptual)',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        pendingProposalsQueue: [
          [_pendingProposal(offerId: 'offer-1')],
        ],
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Propuesta enviada'), findsOneWidget);

      final dynamic state = tester.state(find.byType(DriverHomeScreen));
      expect(state.debugPendingProposals, hasLength(1));
      expect(state.debugPendingProposals.first.offerId, 'offer-1');
      expect(state.debugOffer, isNull);
    },
  );

  testWidgets('M: múltiples propuestas PROPOSED se conservan todas', (
    tester,
  ) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      pendingProposalsQueue: [
        [
          _pendingProposal(offerId: 'offer-1'),
          _pendingProposal(offerId: 'offer-2'),
        ],
      ],
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('2 propuestas enviadas'), findsOneWidget);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugPendingProposals, hasLength(2));
  });

  testWidgets(
    'O: un active ride detectado durante el polling tiene prioridad sobre proposals',
    (tester) async {
      final rides = _FakeRidesRepository(
        activeRideQueue: [null, null, _activeRide()],
      );
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        heartbeatQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        pendingProposalsQueue: [const <DriverPendingProposal>[]],
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Estás disponible'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('ACTIVE_RIDE_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('P: OFFERED y PROPOSED se mantienen como estados separados', (
    tester,
  ) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      pendingProposalsQueue: [const <DriverPendingProposal>[]],
      activeOffersQueue: [
        [_offer()],
      ],
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    expect(find.text('¡Nuevo viaje!'), findsOneWidget);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugOffer, isNotNull);
    expect(state.debugPendingProposals, isEmpty);
  });

  testWidgets('Q: la Position válida obtenida se conserva en el Home', (
    tester,
  ) async {
    final position = _fakePosition(lat: -12.111, lng: -77.222);
    driverHomeGpsFetcherOverride = ({required requestPermission}) async {
      return position;
    };

    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    expect(state.debugLastPosition.latitude, -12.111);
    expect(state.debugLastPosition.longitude, -77.222);
    expect(state.debugGpsStatus, DriverGpsStatus.active);
  });

  testWidgets(
    'R: un fallo de GPS al conectar no marca la ubicación como activa ni pone al conductor en línea',
    (tester) async {
      driverHomeGpsFetcherOverride = ({required requestPermission}) async {
        throw Exception('permiso denegado');
      };

      final rides = _FakeRidesRepository(activeRideQueue: [null, null]);
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(status: DriverOperationalStatus.offline),
        ],
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Estás desconectado'), findsOneWidget);

      await tester.tap(find.text('Conectarme'));
      await tester.pump();

      final dynamic state = tester.state(find.byType(DriverHomeScreen));
      expect(state.debugGpsStatus, isNot(DriverGpsStatus.active));
      expect(state.debugLastPosition, isNull);
      expect(operations.goOnlineCalls, 0);
    },
  );

  testWidgets('S: heartbeat y ofertas no se duplican en cada tick', (
    tester,
  ) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
      heartbeatQueue: List.generate(
        5,
        (_) => const DriverOperationalState(
          status: DriverOperationalStatus.available,
        ),
      ),
    );
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();

    final heartbeatBaseline = operations.heartbeatCalls;
    final offersBaseline = offers.pendingProposalsCalls;

    await tester.pump(const Duration(seconds: 10));
    expect(operations.heartbeatCalls, heartbeatBaseline + 1);

    await tester.pump(const Duration(seconds: 10));
    expect(operations.heartbeatCalls, heartbeatBaseline + 2);

    expect(offers.pendingProposalsCalls, greaterThan(offersBaseline));
  });

  testWidgets('T: logout evita doble submit', (tester) async {
    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.offline),
      ],
    );
    final offers = _FakeOffersRepository();
    final auth = _FakeAuthRepository()..logoutGate = Completer<void>();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
      auth: auth,
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.logout), warnIfMissed: false);
    await tester.pump();

    auth.logoutGate!.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(auth.logoutCalls, 1);
  });

  testWidgets(
    'U: dispose con request pendiente no ejecuta setState tras desmontar',
    (tester) async {
      final gate = Completer<DriverActiveRide?>();
      final rides = _FakeRidesRepository()..gate = gate;
      final operations = _FakeOperationsRepository();
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      gate.complete(null);
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '401-A: error de red durante restore deja ERROR y NO navega a login',
    (tester) async {
      final rides = _FakeRidesRepository(
        activeRideQueue: [
          DioException(
            requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
            type: DioExceptionType.connectionError,
          ),
        ],
      );
      final operations = _FakeOperationsRepository();
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('No pudimos recuperar tu estado'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
      // El error de red nunca toca los tokens: la sesión sigue viva.
      expect(secureStorageData[StorageKeys.accessToken], isNotNull);
    },
  );

  testWidgets('401-B: un 5xx durante restore deja ERROR y NO navega a login', (
    tester,
  ) async {
    final rides = _FakeRidesRepository(
      activeRideQueue: [
        DioException(
          requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
            statusCode: 503,
          ),
        ),
      ],
    );
    final operations = _FakeOperationsRepository();
    final offers = _FakeOffersRepository();

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No pudimos recuperar tu estado'), findsOneWidget);
    expect(find.text('LOGIN_ROUTE'), findsNothing);
  });

  testWidgets(
    '401-C: un 401 resuelto por ApiClient (refresh transparente) no fuerza logout desde Home',
    (tester) async {
      // Cuando ApiClient logra refrescar, el 401 nunca llega a Home:
      // el request original se resuelve como si nunca hubiera fallado.
      // Desde la perspectiva de Home esto es indistinguible de un
      // restore exitoso normal.
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('Estás disponible'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
      // Home nunca necesitó leer/borrar tokens para completar el flujo.
      expect(secureStorageData[StorageKeys.accessToken], 'valid-access-token');
    },
  );

  testWidgets(
    '401-D: sesión definitivamente invalidada (tokens eliminados) navega a login',
    (tester) async {
      // Simula que AuthInterceptor ya intentó refrescar, falló y
      // eliminó los tokens ANTES de que el DioException llegue a Home.
      secureStorageData.remove(StorageKeys.accessToken);

      final rides = _FakeRidesRepository(
        activeRideQueue: [
          DioException(
            requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
              statusCode: 401,
            ),
          ),
        ],
      );
      final operations = _FakeOperationsRepository();
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
      expect(find.text('No pudimos recuperar tu estado'), findsNothing);
    },
  );

  testWidgets(
    '401-E: no hay navegación duplicada si varios requests fallan a la vez con sesión inválida',
    (tester) async {
      var loginBuilds = 0;

      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        heartbeatQueue: [
          DioException(
            requestOptions: RequestOptions(
              path: 'drivers/me/operational-status/heartbeat',
            ),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                path: 'drivers/me/operational-status/heartbeat',
              ),
              statusCode: 401,
            ),
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        pendingProposalsQueue: [
          DioException(
            requestOptions: RequestOptions(
              path: 'drivers/me/ride-offers/proposals/pending',
            ),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                path: 'drivers/me/ride-offers/proposals/pending',
              ),
              statusCode: 401,
            ),
          ),
        ],
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
        onLoginBuilt: () => loginBuilds++,
      );
      await tester.pump();

      // La sesión se invalida recién en el primer tick del worker:
      // heartbeat (10s) y ofertas (3s) fallan casi al mismo tiempo.
      secureStorageData.remove(StorageKeys.accessToken);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
      expect(loginBuilds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '401-F: los workers se detienen al abandonar Home por sesión inválida',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        heartbeatQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
          DioException(
            requestOptions: RequestOptions(
              path: 'drivers/me/operational-status/heartbeat',
            ),
            type: DioExceptionType.badResponse,
            response: Response<dynamic>(
              requestOptions: RequestOptions(
                path: 'drivers/me/operational-status/heartbeat',
              ),
              statusCode: 401,
            ),
          ),
        ],
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      final heartbeatCallsBeforeInvalidation = operations.heartbeatCalls;

      secureStorageData.remove(StorageKeys.accessToken);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);

      final heartbeatCallsAfterInvalidation = operations.heartbeatCalls;

      // Avanzamos mucho más tiempo: si los workers siguieran vivos,
      // el heartbeat count seguiría creciendo.
      await tester.pump(const Duration(seconds: 30));

      expect(operations.heartbeatCalls, heartbeatCallsAfterInvalidation);
      expect(
        heartbeatCallsAfterInvalidation,
        greaterThan(heartbeatCallsBeforeInvalidation),
      );
    },
  );

  testWidgets('A: acceptOffer + 401 definitivo navega a login una sola vez', (
    tester,
  ) async {
    var loginBuilds = 0;

    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      activeOffersQueue: [
        [_offer()],
      ],
      acceptOfferResult: _dioError(
        statusCode: 401,
        path: 'drivers/me/ride-offers/offer-1/accept',
      ),
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
      onLoginBuilt: () => loginBuilds++,
    );
    await tester.pump();

    expect(find.text('¡Nuevo viaje!'), findsOneWidget);

    secureStorageData.remove(StorageKeys.accessToken);

    await tester.ensureVisible(find.text('Aceptar S/ 7.00'));
    await tester.tap(find.text('Aceptar S/ 7.00'));
    await tester.pump();
    await tester.pump();

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(loginBuilds, 1);
    expect(offers.acceptOfferCalls, 1);
    // El 401 definitivo no debe mostrar además un snackbar genérico.
    expect(find.text('No se pudo enviar la propuesta.'), findsNothing);
    expect(find.text('La oferta ya venció o fue asignada.'), findsNothing);
  });

  testWidgets('B: counterOffer + 401 definitivo navega a login una sola vez', (
    tester,
  ) async {
    var loginBuilds = 0;

    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      activeOffersQueue: [
        [_offer()],
      ],
      counterOfferResult: _dioError(
        statusCode: 401,
        path: 'drivers/me/ride-offers/offer-1/counter-offer',
      ),
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
      onLoginBuilt: () => loginBuilds++,
    );
    await tester.pump();

    expect(find.text('¡Nuevo viaje!'), findsOneWidget);

    secureStorageData.remove(StorageKeys.accessToken);

    await tester.ensureVisible(find.text('Hacer contraoferta'));
    await tester.tap(find.text('Hacer contraoferta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), '6.00');
    await tester.tap(find.text('Enviar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(loginBuilds, 1);
    expect(offers.counterOfferCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('C: rejectOffer + 401 definitivo navega a login una sola vez', (
    tester,
  ) async {
    var loginBuilds = 0;

    final rides = _FakeRidesRepository();
    final operations = _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    );
    final offers = _FakeOffersRepository(
      activeOffersQueue: [
        [_offer()],
      ],
      rejectOfferError: _dioError(
        statusCode: 401,
        path: 'drivers/me/ride-offers/offer-1/reject',
      ),
    );

    await _pumpHome(
      tester,
      rides: rides,
      operations: operations,
      offers: offers,
      onLoginBuilt: () => loginBuilds++,
    );
    await tester.pump();

    expect(find.text('¡Nuevo viaje!'), findsOneWidget);

    secureStorageData.remove(StorageKeys.accessToken);

    await tester.ensureVisible(find.text('Rechazar solicitud'));
    await tester.tap(find.text('Rechazar solicitud'));
    await tester.pump();
    await tester.pump();

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(loginBuilds, 1);
    expect(offers.rejectOfferCalls, 1);
  });

  testWidgets(
    'D: acceptOffer con 409 conserva el mensaje actual y NO navega a login',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        activeOffersQueue: [
          [_offer()],
        ],
        acceptOfferResult: _dioError(
          statusCode: 409,
          path: 'drivers/me/ride-offers/offer-1/accept',
        ),
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('¡Nuevo viaje!'), findsOneWidget);

      await tester.ensureVisible(find.text('Aceptar S/ 7.00'));
      await tester.tap(find.text('Aceptar S/ 7.00'));
      await tester.pump();
      await tester.pump();

      expect(find.text('La oferta ya venció o fue asignada.'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
      expect(secureStorageData[StorageKeys.accessToken], isNotNull);
    },
  );

  testWidgets(
    'E: counterOffer con error de red conserva el mensaje actual y NO navega a login',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        activeOffersQueue: [
          [_offer()],
        ],
        counterOfferResult: _dioError(
          statusCode: null,
          type: DioExceptionType.connectionError,
          path: 'drivers/me/ride-offers/offer-1/counter-offer',
        ),
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('¡Nuevo viaje!'), findsOneWidget);

      await tester.ensureVisible(find.text('Hacer contraoferta'));
      await tester.tap(find.text('Hacer contraoferta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), '6.00');
      await tester.tap(find.text('Enviar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
      expect(secureStorageData[StorageKeys.accessToken], isNotNull);
    },
  );

  testWidgets(
    'F: rejectOffer con 404 conserva el mensaje actual y NO navega a login',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        activeOffersQueue: [
          [_offer()],
        ],
        rejectOfferError: _dioError(
          statusCode: 404,
          path: 'drivers/me/ride-offers/offer-1/reject',
        ),
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('¡Nuevo viaje!'), findsOneWidget);

      await tester.ensureVisible(find.text('Rechazar solicitud'));
      await tester.tap(find.text('Rechazar solicitud'));
      await tester.pump();
      await tester.pump();

      expect(find.text('La solicitud ya no está disponible.'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
    },
  );

  testWidgets(
    'G: una acción de oferta y un tick de worker fallando casi al mismo tiempo navegan a login una sola vez',
    (tester) async {
      var loginBuilds = 0;

      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        heartbeatQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
          _dioError(
            statusCode: 401,
            path: 'drivers/me/operational-status/heartbeat',
          ),
        ],
      );
      final offers =
          _FakeOffersRepository(
              activeOffersQueue: [
                [_offer()],
              ],
              rejectOfferError: _dioError(
                statusCode: 401,
                path: 'drivers/me/ride-offers/offer-1/reject',
              ),
            )
            // Alineamos la falla de reject con el próximo tick del
            // heartbeat (10s) para forzar que ambos caminos intenten
            // invalidar la sesión casi al mismo tiempo.
            ..rejectOfferDelay = const Duration(seconds: 10);

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
        onLoginBuilt: () => loginBuilds++,
      );
      await tester.pump();

      expect(find.text('¡Nuevo viaje!'), findsOneWidget);

      secureStorageData.remove(StorageKeys.accessToken);

      await tester.ensureVisible(find.text('Rechazar solicitud'));
      await tester.tap(find.text('Rechazar solicitud'));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await tester.pump();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
      expect(loginBuilds, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'H: tras invalidar sesión desde una acción de oferta, los workers dejan de crecer',
    (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        activeOffersQueue: [
          [_offer()],
        ],
        acceptOfferResult: _dioError(
          statusCode: 401,
          path: 'drivers/me/ride-offers/offer-1/accept',
        ),
      );

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      secureStorageData.remove(StorageKeys.accessToken);

      await tester.ensureVisible(find.text('Aceptar S/ 7.00'));
      await tester.tap(find.text('Aceptar S/ 7.00'));
      await tester.pump();
      await tester.pump();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);

      final heartbeatCallsAfterInvalidation = operations.heartbeatCalls;

      await tester.pump(const Duration(seconds: 30));

      expect(operations.heartbeatCalls, heartbeatCallsAfterInvalidation);
    },
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required _FakeRidesRepository rides,
  required _FakeOperationsRepository operations,
  required _FakeOffersRepository offers,
  _FakeAuthRepository? auth,
  VoidCallback? onLoginBuilt,
}) async {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: '/active-ride',
        builder: (context, state) =>
            const Scaffold(body: Text('ACTIVE_RIDE_ROUTE')),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          onLoginBuilt?.call();
          return const Scaffold(body: Text('LOGIN_ROUTE'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        driverRidesRepositoryProvider.overrideWithValue(rides),
        driverOperationsRepositoryProvider.overrideWithValue(operations),
        driverOffersRepositoryProvider.overrideWithValue(offers),
        authRepositoryProvider.overrideWithValue(auth ?? _FakeAuthRepository()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
}

DioException _dioError({
  required int? statusCode,
  DioExceptionType type = DioExceptionType.badResponse,
  required String path,
}) {
  final requestOptions = RequestOptions(path: path);

  return DioException(
    requestOptions: requestOptions,
    type: type,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: requestOptions,
            statusCode: statusCode,
          ),
  );
}

Position _fakePosition({double lat = -12.05, double lng = -77.05}) {
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

DriverActiveRide _activeRide({
  String id = 'ride-1',
  String status = 'ACCEPTED',
}) {
  return DriverActiveRide(
    id: id,
    status: status,
    estimatedFare: '10.00',
    currency: 'PEN',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    distanceMeters: 1000,
    estimatedDurationSeconds: 600,
  );
}

DriverPendingProposal _pendingProposal({required String offerId}) {
  return DriverPendingProposal(
    offerId: offerId,
    rideId: 'ride-$offerId',
    status: 'PROPOSED',
    proposedFare: '7.50',
    passengerOfferFare: '7.00',
    estimatedFare: '7.20',
    currency: 'PEN',
    expiresAt: DateTime.utc(2026, 8, 10, 10, 5),
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    distanceToOriginMeters: 300,
  );
}

DriverRideOffer _offer() {
  return DriverRideOffer(
    id: 'offer-1',
    rideId: 'ride-1',
    status: 'OFFERED',
    distanceToOriginMeters: 500,
    estimatedFare: '7.00',
    passengerOfferFare: '7.00',
    proposedFare: null,
    proposedAt: null,
    currency: 'PEN',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    expiresAt: DateTime.utc(2030),
  );
}

class _FakeRidesRepository extends DriverRidesRepository {
  _FakeRidesRepository({List<Object?>? activeRideQueue})
    : _queue = List.of(activeRideQueue ?? const [null]),
      super(Dio());

  final List<Object?> _queue;
  int getActiveRideCalls = 0;

  /// Cuando se define, `getActiveRide` queda pendiente indefinidamente
  /// hasta que el test complete este gate (usado para probar dispose).
  Completer<DriverActiveRide?>? gate;

  @override
  Future<DriverActiveRide?> getActiveRide() async {
    getActiveRideCalls++;

    final pendingGate = gate;

    if (pendingGate != null) {
      return pendingGate.future;
    }

    final next = _queue.length > 1 ? _queue.removeAt(0) : _queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as DriverActiveRide?;
  }
}

/// Extrae el siguiente elemento de una cola de fake-repository.
///
/// Cada elemento puede ser el valor de éxito esperado o un
/// [DioException] (para simular una falla puntual en ese ciclo,
/// p.ej. un 401 definitivo). Si la cola tiene un solo elemento,
/// se repite en cada llamada.
Object? _popNext(List<Object>? queue) {
  if (queue == null || queue.isEmpty) {
    return null;
  }

  return queue.length > 1 ? queue.removeAt(0) : queue.first;
}

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository({
    this.statusQueue,
    this.heartbeatQueue,
    this.dailyStatsResult,
  }) : super(Dio());

  /// Elementos: [DriverOperationalState] o [DioException].
  List<Object>? statusQueue;

  /// Elementos: [DriverOperationalState] o [DioException].
  List<Object>? heartbeatQueue;
  Object? dailyStatsResult;

  int getStatusCalls = 0;
  int goOnlineCalls = 0;
  int goOfflineCalls = 0;
  int heartbeatCalls = 0;
  int updateLocationCalls = 0;
  int getDailyStatsCalls = 0;

  @override
  Future<DriverOperationalState> getStatus() async {
    getStatusCalls++;

    final next = _popNext(statusQueue);

    if (next is DioException) {
      throw next;
    }

    return (next as DriverOperationalState?) ??
        const DriverOperationalState(status: DriverOperationalStatus.offline);
  }

  @override
  Future<DriverOperationalState> goOnline() async {
    goOnlineCalls++;
    return const DriverOperationalState(
      status: DriverOperationalStatus.available,
    );
  }

  @override
  Future<DriverOperationalState> goOffline() async {
    goOfflineCalls++;
    return const DriverOperationalState(
      status: DriverOperationalStatus.offline,
    );
  }

  @override
  Future<DriverOperationalState> heartbeat() async {
    heartbeatCalls++;

    final next = _popNext(heartbeatQueue);

    if (next is DioException) {
      throw next;
    }

    return (next as DriverOperationalState?) ??
        const DriverOperationalState(status: DriverOperationalStatus.available);
  }

  @override
  Future<DriverDailyStats> getDailyStats() async {
    getDailyStatsCalls++;

    final result = dailyStatsResult;

    if (result is Exception) {
      throw result;
    }

    if (result == null) {
      return DriverDailyStats.fromJson(const {
        'businessDate': '2026-08-10',
        'timezone': 'America/Lima',
        'completedRides': 0,
        'grossAmount': '0.00',
        'currency': 'PEN',
      });
    }

    return result as DriverDailyStats;
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

class _FakeOffersRepository extends DriverOffersRepository {
  _FakeOffersRepository({
    this.pendingProposalsQueue,
    this.activeOffersQueue,
    this.acceptOfferResult,
    this.counterOfferResult,
    this.rejectOfferError,
  }) : super(Dio());

  /// Elementos: [List<DriverPendingProposal>] o [DioException].
  List<Object>? pendingProposalsQueue;

  /// Elementos: [List<DriverRideOffer>] o [DioException].
  List<Object>? activeOffersQueue;

  /// [DriverRideOffer] a devolver, o [DioException] a lanzar.
  Object? acceptOfferResult;

  /// [DriverRideOffer] a devolver, o [DioException] a lanzar.
  Object? counterOfferResult;

  /// [DioException] a lanzar, o `null` para completar sin error.
  DioException? rejectOfferError;

  /// Retardo simulado (vía fake clock) antes de resolver `rejectOffer`.
  /// Permite alinear su falla con un tick de timer específico en tests
  /// de concurrencia.
  Duration rejectOfferDelay = Duration.zero;

  int pendingProposalsCalls = 0;
  int activeOffersCalls = 0;
  int acceptOfferCalls = 0;
  int counterOfferCalls = 0;
  int rejectOfferCalls = 0;

  @override
  Future<List<DriverPendingProposal>> getPendingProposals() async {
    pendingProposalsCalls++;

    final next = _popNext(pendingProposalsQueue);

    if (next is DioException) {
      throw next;
    }

    return (next as List<DriverPendingProposal>?) ?? const [];
  }

  @override
  Future<List<DriverRideOffer>> getActiveOffers() async {
    activeOffersCalls++;

    final next = _popNext(activeOffersQueue);

    if (next is DioException) {
      throw next;
    }

    return (next as List<DriverRideOffer>?) ?? const [];
  }

  @override
  Future<DriverRideOffer> acceptOffer(String offerId) async {
    acceptOfferCalls++;

    final result = acceptOfferResult;

    if (result is DioException) {
      throw result;
    }

    return result as DriverRideOffer;
  }

  @override
  Future<DriverRideOffer> counterOffer(
    String offerId,
    String proposedFare,
  ) async {
    counterOfferCalls++;

    final result = counterOfferResult;

    if (result is DioException) {
      throw result;
    }

    return result as DriverRideOffer;
  }

  @override
  Future<void> rejectOffer(String offerId) async {
    rejectOfferCalls++;

    if (rejectOfferDelay > Duration.zero) {
      await Future<void>.delayed(rejectOfferDelay);
    }

    final error = rejectOfferError;

    if (error != null) {
      throw error;
    }
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio(), const FlutterSecureStorage());

  int logoutCalls = 0;
  Completer<void>? logoutGate;

  @override
  Future<void> logout() async {
    logoutCalls++;

    final gate = logoutGate;

    if (gate != null) {
      await gate.future;
    }
  }
}
