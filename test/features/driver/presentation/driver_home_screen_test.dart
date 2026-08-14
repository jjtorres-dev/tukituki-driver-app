import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show GoogleMap;

import 'package:driver/core/storage/secure_storage.dart';
import 'package:driver/core/theme/driver_palette.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/data/driver_offers_repository.dart';
import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_active_ride.dart';
import 'package:driver/features/driver/domain/driver_daily_stats.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
import 'package:driver/features/driver/domain/driver_pending_payment.dart';
import 'package:driver/features/driver/domain/driver_pending_proposal.dart';
import 'package:driver/features/driver/domain/driver_ride_offer.dart';
import 'package:driver/features/driver/domain/driver_ride_payment.dart';
import 'package:driver/features/driver/presentation/driver_home_map.dart';
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
    driverHomeMapBuilderOverride = null;
    driverHomeLocationAccuracyFetcherOverride = null;
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

  group('Restore CASH PENDING (Checkpoint D)', () {
    testWidgets(
      'restaura /completed-payment/:rideId cuando no hay active ride y existe CASH PENDING',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: [
            [_pendingPaymentFixture(rideId: 'ride-7', method: 'CASH', status: 'PENDING')],
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

        expect(find.text('COMPLETED_PAYMENT_ROUTE ride-7'), findsOneWidget);
        expect(operations.getStatusCalls, 0);
      },
    );

    testWidgets(
      'prioridad: active ride IN_PROGRESS gana sobre un CASH PENDING previo',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [_activeRide(status: 'IN_PROGRESS')],
          pendingPaymentsQueue: [
            [_pendingPaymentFixture(rideId: 'ride-old', method: 'CASH', status: 'PENDING')],
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

        expect(find.text('ACTIVE_RIDE_ROUTE'), findsOneWidget);
        expect(rides.getPendingPaymentsCalls, 0);
      },
    );

    testWidgets(
      'múltiples CASH PENDING: elige el primero de la lista sin descartar los demás',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: [
            [
              _pendingPaymentFixture(
                rideId: 'ride-recent',
                method: 'CASH',
                status: 'PENDING',
              ),
              _pendingPaymentFixture(
                rideId: 'ride-old',
                method: 'CASH',
                status: 'PENDING',
              ),
            ],
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

        expect(
          find.text('COMPLETED_PAYMENT_ROUTE ride-recent'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ignora pendientes no-CASH y elige el CASH real de la lista',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: [
            [
              _pendingPaymentFixture(
                rideId: 'ride-yape',
                method: 'YAPE',
                status: 'PENDING',
              ),
              _pendingPaymentFixture(
                rideId: 'ride-cash',
                method: 'CASH',
                status: 'PENDING',
              ),
            ],
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

        expect(
          find.text('COMPLETED_PAYMENT_ROUTE ride-cash'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'sin active ride ni CASH PENDING: Home muestra su flujo normal',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: const [[]],
        );
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

        expect(find.text('Estás desconectado'), findsWidgets);
        expect(find.text('COMPLETED_PAYMENT_ROUTE'), findsNothing);
      },
    );

    testWidgets(
      'error de red al consultar pending-payments no bloquea Home (fallback seguro)',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: [
            DioException(
              requestOptions: RequestOptions(
                path: 'drivers/me/rides/pending-payments',
              ),
              type: DioExceptionType.connectionError,
            ),
          ],
        );
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

        expect(find.text('Estás desconectado'), findsWidgets);
        expect(operations.getStatusCalls, 1);
      },
    );
  });

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

      // "Estás desconectado" aparece dos veces por diseño: en la
      // tarjeta flotante de disponibilidad y en el título del sheet.
      expect(find.text('Estás desconectado'), findsWidgets);

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

      expect(find.text('Disponible'), findsOneWidget);

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

    // "Estás desconectado" aparece dos veces por diseño: en la
    // tarjeta flotante de disponibilidad y en el título del sheet.
    expect(find.text('Estás desconectado'), findsWidgets);
    // Un fallo de stats se muestra como "—", no como texto de error.
    expect(find.text('—'), findsWidgets);
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

    expect(find.text('Disponible'), findsOneWidget);

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
      await _openSolicitudesTab(tester);

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
    await _openSolicitudesTab(tester);

    expect(find.text('Propuestas pendientes (2)'), findsOneWidget);

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

      expect(find.text('Disponible'), findsOneWidget);

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

    await _openSolicitudesTab(tester);

    final dynamic state = tester.state(find.byType(DriverHomeScreen));
    // G4B-R2: sin tap explícito no hay selección automática; lo que
    // separa OFFERED de PROPOSED es que `_offers` esté poblado.
    expect(state.debugOffers, isNotEmpty);
    expect(state.debugSelectedOfferId, isNull);
    expect(state.debugPendingProposals, isEmpty);
  });

  group('G4B1: lista compacta de múltiples solicitudes + selección local', () {
    testWidgets(
      'A: 1 Offer se conserva en la lista pero permanece compacta/cerrada por defecto (G4B-R2: sin auto-selección)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, hasLength(1));
        // G4B-R2: ninguna Offer se abre sola, ni siquiera siendo la única.
        expect(state.debugSelectedOfferId, isNull);
        expect(
          find.byKey(const ValueKey('driver-offer-card-offer-1')),
          findsOneWidget,
        );
        // Compacta: sin acciones visibles hasta un tap explícito.
        expect(find.text('Hacer contraoferta'), findsNothing);
      },
    );

    testWidgets(
      'B: 5 Offers quedan todas en state, ninguna seleccionada por defecto, todas alcanzables por scroll',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        final fiveOffers = List.generate(
          5,
          (index) => _offerFixture(
            id: 'offer-${index + 1}',
            distanceToOriginMeters: (index + 1) * 200,
          ),
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [fiveOffers],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, hasLength(5));
        expect(state.debugSelectedOfferId, isNull);

        // Lista lazy real (Fase 12): no todas las 5 tarjetas están
        // necesariamente construidas sin scroll. Scrolleamos hasta
        // cada una para confirmar que la lista completa es alcanzable
        // (Fase 24), no que estén todas pre-construidas de una.
        for (var i = 1; i <= 5; i++) {
          await _scrollToOfferCard(tester, 'offer-$i');
          expect(
            find.byKey(ValueKey('driver-offer-card-offer-$i')),
            findsOneWidget,
          );
        }

        // Ninguna quedó expandida por defecto.
        expect(find.text('Hacer contraoferta'), findsNothing);
      },
    );

    testWidgets(
      'C: una nueva Offer entra a la lista sin robar la selección ya elegida por el Driver',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              _offerFixture(id: 'offer-1'),
              _offerFixture(id: 'offer-2', distanceToOriginMeters: 800),
            ],
            [
              _offerFixture(id: 'offer-1'),
              _offerFixture(id: 'offer-2', distanceToOriginMeters: 800),
              _offerFixture(id: 'offer-3', distanceToOriginMeters: 300),
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
        await _openSolicitudesTab(tester);

        await _scrollToOfferCard(tester, 'offer-2');
        await tester.tap(
          find.byKey(const ValueKey('driver-offer-card-toggle-offer-2')),
        );
        await tester.pump();

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugSelectedOfferId, 'offer-2');

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(state.debugOffers, hasLength(3));
        expect(state.debugSelectedOfferId, 'offer-2');
      },
    );

    testWidgets(
      'D: la Offer seleccionada desaparece del próximo poll -> selectedOfferId queda null (NO autoabre otra)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              _offerFixture(id: 'offer-1'),
              _offerFixture(id: 'offer-2'),
              _offerFixture(id: 'offer-3'),
            ],
            [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-3')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        await _scrollToOfferCard(tester, 'offer-2');
        await tester.tap(
          find.byKey(const ValueKey('driver-offer-card-toggle-offer-2')),
        );
        await tester.pump();

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugSelectedOfferId, 'offer-2');

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(
          state.debugOffers.map((o) => o.id).toList(),
          ['offer-1', 'offer-3'],
        );
        // G4B-R2: la lista sigue teniendo Offers, pero al desaparecer
        // la seleccionada la selección queda en null — NO se autoabre
        // ni offer-1 ni offer-3.
        expect(state.debugSelectedOfferId, isNull);
      },
    );

    testWidgets(
      'E: la Offer seleccionada explícitamente desaparece siendo la única -> selectedOfferId queda null (NO autoabre otra)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
            const <DriverRideOffer>[],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        // Primero: sin tap, no hay selección (G4B-R2).
        expect(state.debugSelectedOfferId, isNull);

        await _selectOfferCard(tester, 'offer-1');
        expect(state.debugSelectedOfferId, 'offer-1');

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(state.debugOffers, isEmpty);
        expect(state.debugSelectedOfferId, isNull);
        expect(find.text('Sin solicitudes por ahora'), findsOneWidget);
      },
    );

    group('G4B-R4: cerrar solicitud expandida (toggle)', () {
      DriverRideOffer offerWithCoords(String id) {
        final base = _offerFixture(id: id);

        return DriverRideOffer(
          id: base.id,
          rideId: base.rideId,
          status: base.status,
          distanceToOriginMeters: base.distanceToOriginMeters,
          estimatedFare: base.estimatedFare,
          passengerOfferFare: base.passengerOfferFare,
          proposedFare: base.proposedFare,
          proposedAt: base.proposedAt,
          currency: base.currency,
          originAddress: base.originAddress,
          destinationAddress: base.destinationAddress,
          expiresAt: base.expiresAt,
          originLatitude: -6.48,
          originLongitude: -76.36,
          destinationLatitude: -6.50,
          destinationLongitude: -76.40,
        );
      }

      testWidgets(
        'tocar la tarjeta ya expandida la cierra: selectedOfferId vuelve a null y todas quedan compactas',
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
            pendingProposalsQueue: [const <DriverPendingProposal>[]],
            activeOffersQueue: [
              [offerWithCoords('offer-1'), _offerFixture(id: 'offer-2')],
            ],
          );

          await _pumpHome(
            tester,
            rides: rides,
            operations: operations,
            offers: offers,
          );
          await tester.pump();
          await _openSolicitudesTab(tester);

          final dynamic state = tester.state(find.byType(DriverHomeScreen));

          await _selectOfferCard(tester, 'offer-1');
          expect(state.debugSelectedOfferId, 'offer-1');
          expect(find.text('Aceptar S/ 7.00'), findsOneWidget);

          final maps = tester.widgetList<DriverHomeMap>(
            find.byType(DriverHomeMap),
          );
          expect(maps.first.markers, hasLength(2));
          expect(state.debugOffersCameraRequest, isNotNull);

          // Tocar la MISMA tarjeta, ya expandida, la cierra.
          await _selectOfferCard(tester, 'offer-1');

          expect(state.debugSelectedOfferId, isNull);
          // Todas compactas: sin acciones visibles.
          expect(find.text('Aceptar S/ 7.00'), findsNothing);
          expect(find.text('Hacer contraoferta'), findsNothing);
          expect(find.text('Rechazar solicitud'), findsNothing);

          // Mapa vuelve a solo-Driver: markers A/B desaparecen.
          final mapsAfterClose = tester.widgetList<DriverHomeMap>(
            find.byType(DriverHomeMap),
          );
          expect(mapsAfterClose.first.markers, isEmpty);
          // El cameraRequest A/B deja de estar activo.
          expect(state.debugOffersCameraRequest, isNull);

          // Cerrar es puramente local: ninguna llamada a Backend.
          expect(offers.acceptOfferCalls, 0);
          expect(offers.counterOfferCalls, 0);
          expect(offers.rejectOfferCalls, 0);
          // La Offer sigue en la lista: no fue rechazada ni eliminada.
          expect(state.debugOffers.map((o) => o.id).toList(), [
            'offer-1',
            'offer-2',
          ]);
        },
      );

      testWidgets(
        'A cerrada explícitamente + llega B en el siguiente poll: ninguna se autoabre',
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
            pendingProposalsQueue: [const <DriverPendingProposal>[]],
            activeOffersQueue: [
              [_offerFixture(id: 'offer-1')],
              [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-2')],
            ],
          );

          await _pumpHome(
            tester,
            rides: rides,
            operations: operations,
            offers: offers,
          );
          await tester.pump();
          await _openSolicitudesTab(tester);

          await _selectOfferCard(tester, 'offer-1');

          final dynamic state = tester.state(find.byType(DriverHomeScreen));
          expect(state.debugSelectedOfferId, 'offer-1');

          // Cierre manual.
          await _selectOfferCard(tester, 'offer-1');
          expect(state.debugSelectedOfferId, isNull);

          // Llega offer-2 en el siguiente poll.
          await tester.pump(const Duration(seconds: 3));
          await tester.pump();

          expect(
            state.debugOffers.map((o) => o.id).toList(),
            containsAll(['offer-1', 'offer-2']),
          );
          // Ninguna se autoabre tras el cierre manual.
          expect(state.debugSelectedOfferId, isNull);
        },
      );

      testWidgets(
        'tocar Aceptar en la tarjeta expandida NO colapsa la tarjeta antes de ejecutar la acción',
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
            pendingProposalsQueue: [const <DriverPendingProposal>[]],
            activeOffersQueue: [
              [_offerFixture(id: 'offer-1')],
            ],
            acceptOfferResult: _offerFixture(id: 'offer-1'),
          );

          await _pumpHome(
            tester,
            rides: rides,
            operations: operations,
            offers: offers,
          );
          await tester.pump();
          await _openSolicitudesTab(tester);

          await _selectOfferCard(tester, 'offer-1');

          final dynamic state = tester.state(find.byType(DriverHomeScreen));
          expect(state.debugSelectedOfferId, 'offer-1');

          // El botón real usa la Offer seleccionada -> el tap debe
          // llegar al botón, NO al toggle del header.
          await tester.tap(find.text('Aceptar S/ 7.00'));
          await tester.pump();

          expect(offers.acceptOfferCalls, 1);
        },
      );

      testWidgets(
        '20 Offers: expandir/cerrar cualquiera no rompe la lista lazy ni el scroll',
        (tester) async {
          final rides = _FakeRidesRepository();
          final operations = _FakeOperationsRepository(
            statusQueue: [
              const DriverOperationalState(
                status: DriverOperationalStatus.available,
              ),
            ],
          );
          final manyOffers = List.generate(
            20,
            (index) => _offerFixture(
              id: 'offer-${index + 1}',
              distanceToOriginMeters: (index + 1) * 100,
            ),
          );
          final offers = _FakeOffersRepository(
            pendingProposalsQueue: [const <DriverPendingProposal>[]],
            activeOffersQueue: [manyOffers],
          );

          await _pumpHome(
            tester,
            rides: rides,
            operations: operations,
            offers: offers,
          );
          await tester.pump();
          await _openSolicitudesTab(tester);

          final dynamic state = tester.state(find.byType(DriverHomeScreen));

          await _selectOfferCard(tester, 'offer-3');
          expect(state.debugSelectedOfferId, 'offer-3');
          expect(tester.takeException(), isNull);

          await _selectOfferCard(tester, 'offer-3');
          expect(state.debugSelectedOfferId, isNull);
          expect(tester.takeException(), isNull);

          // La lista lazy sigue siendo alcanzable por scroll tras el
          // ciclo expandir/cerrar (no quedó en un estado roto).
          await _scrollToOfferCard(tester, 'offer-20');
          expect(
            find.byKey(const ValueKey('driver-offer-card-offer-20')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    });

    testWidgets(
      'F: Aceptar opera sobre la Offer seleccionada, no sobre la primera de la lista',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              _offerFixture(id: 'offer-1', passengerOfferFare: '5.00'),
              _offerFixture(id: 'offer-2', passengerOfferFare: '9.00'),
            ],
          ],
          acceptOfferResult: _offerFixture(
            id: 'offer-2',
            passengerOfferFare: '9.00',
          ),
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        await _scrollToOfferCard(tester, 'offer-2');
        await tester.tap(
          find.byKey(const ValueKey('driver-offer-card-toggle-offer-2')),
        );
        await tester.pump();

        await tester.ensureVisible(find.text('Aceptar S/ 9.00'));
        await tester.tap(find.text('Aceptar S/ 9.00'));
        await tester.pump();
        await tester.pump();

        expect(offers.lastAcceptOfferId, 'offer-2');

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugPendingProposals, hasLength(1));
        expect(state.debugPendingProposals.first.offerId, 'offer-2');
      },
    );

    testWidgets(
      'G: Contraofertar opera sobre la Offer seleccionada, no sobre la primera de la lista',
      (tester) async {
        // Viewport alto: evita la complejidad de scrollear dentro de
        // la lista lazy hasta un botón que recién aparece al expandir
        // la tarjeta (el foco del test es la lógica de negocio, no el
        // comportamiento de scroll, ya cubierto en otros tests).
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              _offerFixture(id: 'offer-1', passengerOfferFare: '5.00'),
              _offerFixture(id: 'offer-2', passengerOfferFare: '9.00'),
            ],
          ],
          counterOfferResult: _offerFixture(
            id: 'offer-2',
            passengerOfferFare: '9.00',
          ),
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        await _scrollToOfferCard(tester, 'offer-2');
        await tester.tap(
          find.byKey(const ValueKey('driver-offer-card-toggle-offer-2')),
        );
        await tester.pump();

        await tester.ensureVisible(find.text('Hacer contraoferta'));
        await tester.tap(find.text('Hacer contraoferta'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.enterText(find.byType(TextField), '8.00');
        await tester.tap(find.text('Enviar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(offers.lastCounterOfferId, 'offer-2');
      },
    );

    testWidgets(
      'H: Rechazar opera sobre la Offer seleccionada y remueve solo esa tarjeta, sin afectar las demás',
      (tester) async {
        // Ver comentario en el test G: viewport alto para no depender
        // de scroll dentro de la lista lazy al expandir la tarjeta.
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-2')],
            [_offerFixture(id: 'offer-1')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        await _scrollToOfferCard(tester, 'offer-2');
        await tester.tap(
          find.byKey(const ValueKey('driver-offer-card-toggle-offer-2')),
        );
        await tester.pump();

        await tester.ensureVisible(find.text('Rechazar solicitud'));
        await tester.tap(find.text('Rechazar solicitud'));
        await tester.pump();
        await tester.pump();

        expect(offers.lastRejectOfferId, 'offer-2');

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers.map((o) => o.id).toList(), ['offer-1']);
      },
    );

    testWidgets(
      'I: Rechazar con 409 igual refresca el mailbox (corrige asimetría detectada en G4A-AUDIT)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
            const <DriverRideOffer>[],
          ],
          rejectOfferError: _dioError(
            statusCode: 409,
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
        await _openSolicitudesTab(tester);
        await _selectOfferCard(tester, 'offer-1');

        await tester.ensureVisible(find.text('Rechazar solicitud'));
        await tester.tap(find.text('Rechazar solicitud'));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('La solicitud ya venció o dejó de estar disponible.'),
          findsOneWidget,
        );
        expect(offers.activeOffersCalls, 2);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, isEmpty);
      },
    );

    testWidgets(
      'J: un active ride detectado durante el polling de ofertas tiene prioridad y navega a /active-ride',
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
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-2')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        expect(
          find.byKey(const ValueKey('driver-offer-card-offer-1')),
          findsOneWidget,
        );

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        // El guard de active ride en `_loadOffers` (Fase 19) gana
        // sobre la lista de ofertas ya visible: navega antes de que
        // el próximo poll pueda seguir mostrando el mailbox.
        expect(find.text('ACTIVE_RIDE_ROUTE'), findsOneWidget);
      },
    );
  });

  group('G4B2: robustez multi-offer, bottom nav y mapa A/B', () {
    testWidgets(
      'A: timeout en GET active después de [A,B] preserva la lista (no la vacía)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-2')],
            _dioError(
              statusCode: null,
              type: DioExceptionType.connectionError,
              path: 'drivers/me/ride-offers/active',
            ),
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, hasLength(2));

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        // El timeout NO debe convertirse en lista vacía: se preserva
        // la última respuesta 200 válida.
        expect(state.debugOffers, hasLength(2));
        expect(
          state.debugOffers.map((o) => o.id).toList(),
          ['offer-1', 'offer-2'],
        );
      },
    );

    testWidgets(
      'B: 500 después de [A,B] preserva la lista, y el siguiente 200 exitoso [A,B,C] se aplica normalmente',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1'), _offerFixture(id: 'offer-2')],
            _dioError(
              statusCode: 500,
              path: 'drivers/me/ride-offers/active',
            ),
            [
              _offerFixture(id: 'offer-1'),
              _offerFixture(id: 'offer-2'),
              _offerFixture(id: 'offer-3'),
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, hasLength(2));

        // Poll con 500: la lista se mantiene igual.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(state.debugOffers, hasLength(2));

        // Siguiente poll exitoso: se aplica con normalidad.
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
        expect(state.debugOffers, hasLength(3));
        expect(
          state.debugOffers.map((o) => o.id).toList(),
          ['offer-1', 'offer-2', 'offer-3'],
        );
      },
    );

    testWidgets(
      'C: ids duplicados en la respuesta de Backend se deduplican (primera ocurrencia gana, orden preservado)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              _offerFixture(id: 'offer-1', passengerOfferFare: '7.00'),
              _offerFixture(id: 'offer-1', passengerOfferFare: '99.00'),
              _offerFixture(id: 'offer-2'),
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(
          state.debugOffers.map((o) => o.id).toList(),
          ['offer-1', 'offer-2'],
        );
        expect(state.debugOffers.first.passengerOfferFare, '7.00');
      },
    );

    testWidgets(
      'D: Aceptar con error también refresca el mailbox (mismo fix de Fase 16 ya aplicado en reject/counterOffer)',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
            const <DriverRideOffer>[],
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
        await _openSolicitudesTab(tester);
        await _selectOfferCard(tester, 'offer-1');

        await tester.ensureVisible(find.text('Aceptar S/ 7.00'));
        await tester.tap(find.text('Aceptar S/ 7.00'));
        await tester.pump();
        await tester.pump();

        expect(
          find.text('La oferta ya venció o fue asignada.'),
          findsOneWidget,
        );
        expect(offers.activeOffersCalls, 2);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, isEmpty);
      },
    );

    testWidgets(
      'E: bottom nav — Inicio nunca muestra contenido de Offers, Ingresos/Perfil son placeholders honestos sin datos falsos',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();

        // Inicio (default): sin tarjetas de Offer.
        expect(
          find.byKey(const ValueKey('driver-offer-card-offer-1')),
          findsNothing,
        );
        expect(find.text('Disponible'), findsOneWidget);

        await tester.tap(find.text('Ingresos'));
        await tester.pump();
        expect(find.byKey(const ValueKey('driver-tab-ingresos')), findsOneWidget);
        expect(
          find.text('Esta sección estará disponible próximamente.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Perfil'));
        await tester.pump();
        expect(find.byKey(const ValueKey('driver-tab-perfil')), findsOneWidget);

        await tester.tap(find.text('Inicio'));
        await tester.pump();
        expect(find.text('Disponible'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('driver-offer-card-offer-1')),
          findsNothing,
        );
      },
    );

    testWidgets('F: el badge de Solicitudes muestra _offers.length real, no inventado', (
      tester,
    ) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
      );
      final offers = _FakeOffersRepository(
        pendingProposalsQueue: [const <DriverPendingProposal>[]],
        activeOffersQueue: [
          [
            _offerFixture(id: 'offer-1'),
            _offerFixture(id: 'offer-2'),
            _offerFixture(id: 'offer-3'),
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

      expect(find.text('3'), findsOneWidget);

      final dynamic state = tester.state(find.byType(DriverHomeScreen));
      expect(state.debugOffers, hasLength(3));
    });

    testWidgets(
      'G: selectedOffer con coordenadas válidas produce markers A/B en el mapa de Solicitudes',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        final offer = _offerFixture(id: 'offer-1');
        final offerWithCoords = DriverRideOffer(
          id: offer.id,
          rideId: offer.rideId,
          status: offer.status,
          distanceToOriginMeters: offer.distanceToOriginMeters,
          estimatedFare: offer.estimatedFare,
          passengerOfferFare: offer.passengerOfferFare,
          proposedFare: offer.proposedFare,
          proposedAt: offer.proposedAt,
          currency: offer.currency,
          originAddress: offer.originAddress,
          destinationAddress: offer.destinationAddress,
          expiresAt: offer.expiresAt,
          originLatitude: -6.48,
          originLongitude: -76.36,
          destinationLatitude: -6.50,
          destinationLongitude: -76.40,
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [offerWithCoords],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        final mapsBeforeSelection = tester.widgetList<DriverHomeMap>(
          find.byType(DriverHomeMap),
        );
        // G4B-R2: sin tap explícito, sin selección -> sin markers A/B.
        expect(mapsBeforeSelection.first.markers, isEmpty);

        await _selectOfferCard(tester, 'offer-1');

        final maps = tester.widgetList<DriverHomeMap>(
          find.byType(DriverHomeMap),
        );
        expect(maps, hasLength(1));
        expect(maps.first.markers, hasLength(2));

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffersCameraRequest, isNotNull);
      },
    );

    testWidgets(
      'H: selectedOffer SIN coordenadas válidas no dibuja markers y no crashea',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);
        // Selección explícita de una Offer SIN coordenadas: ejercita
        // el branch real de `hasValidRouteCoordinates == false`, no
        // solo el caso trivial de "nada seleccionado".
        await _selectOfferCard(tester, 'offer-1');

        expect(tester.takeException(), isNull);

        final maps = tester.widgetList<DriverHomeMap>(
          find.byType(DriverHomeMap),
        );
        expect(maps, hasLength(1));
        expect(maps.first.markers, isEmpty);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffersCameraRequest, isNull);
      },
    );

    testWidgets(
      'I: un poll que NO cambia la Offer seleccionada no emite un cameraRequest nuevo (sin thrashing)',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        DriverRideOffer withCoords(String id) {
          final base = _offerFixture(id: id);
          return DriverRideOffer(
            id: base.id,
            rideId: base.rideId,
            status: base.status,
            distanceToOriginMeters: base.distanceToOriginMeters,
            estimatedFare: base.estimatedFare,
            passengerOfferFare: base.passengerOfferFare,
            proposedFare: base.proposedFare,
            proposedAt: base.proposedAt,
            currency: base.currency,
            originAddress: base.originAddress,
            destinationAddress: base.destinationAddress,
            expiresAt: base.expiresAt,
            originLatitude: -6.48,
            originLongitude: -76.36,
            destinationLatitude: -6.50,
            destinationLongitude: -76.40,
          );
        }

        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [withCoords('offer-1'), withCoords('offer-2')],
            [withCoords('offer-1'), withCoords('offer-2')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);
        await _selectOfferCard(tester, 'offer-1');

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        final firstRequestId = state.debugOffersCameraRequest?.id;
        expect(firstRequestId, isNotNull);

        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        // Misma Offer seleccionada, mismas coordenadas: NO debe haber
        // un pedido de cámara nuevo por este poll.
        expect(state.debugOffersCameraRequest?.id, firstRequestId);
      },
    );

    testWidgets(
      'J: solo la tarjeta tocada se expande, el mapa refleja SU offer (no la primera), y re-seleccionar otra después funciona con normalidad',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        DriverRideOffer withCoords(
          String id, {
          required double originLat,
          required double destLat,
        }) {
          final base = _offerFixture(id: id);
          return DriverRideOffer(
            id: base.id,
            rideId: base.rideId,
            status: base.status,
            distanceToOriginMeters: base.distanceToOriginMeters,
            estimatedFare: base.estimatedFare,
            passengerOfferFare: base.passengerOfferFare,
            proposedFare: base.proposedFare,
            proposedAt: base.proposedAt,
            currency: base.currency,
            originAddress: base.originAddress,
            destinationAddress: base.destinationAddress,
            expiresAt: base.expiresAt,
            originLatitude: originLat,
            originLongitude: -76.36,
            destinationLatitude: destLat,
            destinationLongitude: -76.40,
          );
        }

        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [
              withCoords('offer-1', originLat: -6.10, destLat: -6.20),
              withCoords('offer-2', originLat: -6.48, destLat: -6.50),
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
        await _openSolicitudesTab(tester);

        // Nadie expandida por defecto.
        expect(find.text('Hacer contraoferta'), findsNothing);

        await _selectOfferCard(tester, 'offer-2');

        // Solo offer-2 expandida: sus acciones son visibles.
        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugSelectedOfferId, 'offer-2');
        expect(find.text('Hacer contraoferta'), findsOneWidget);

        // El mapa refleja las coordenadas de offer-2, no offer-1.
        final maps = tester.widgetList<DriverHomeMap>(
          find.byType(DriverHomeMap),
        );
        final originMarker = maps.first.markers.firstWhere(
          (m) => m.markerId.value == 'solicitud-origin',
        );
        expect(originMarker.position.latitude, -6.48);

        // Re-seleccionar otra tarjeta después funciona con normalidad.
        await _selectOfferCard(tester, 'offer-1');
        expect(state.debugSelectedOfferId, 'offer-1');

        final mapsAfter = tester.widgetList<DriverHomeMap>(
          find.byType(DriverHomeMap),
        );
        final originMarkerAfter = mapsAfter.first.markers.firstWhere(
          (m) => m.markerId.value == 'solicitud-origin',
        );
        expect(originMarkerAfter.position.latitude, -6.10);
      },
    );

    testWidgets(
      'K: la tarjeta muestra el firstName real del Passenger cuando Backend lo entrega',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1', passengerFirstName: 'Carlos')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        expect(find.text('Carlos'), findsOneWidget);
      },
    );

    testWidgets(
      'L: sin firstName (Backend no lo entregó), la tarjeta NO inventa un placeholder tipo "Pasajero"',
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
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [
            [_offerFixture(id: 'offer-1')],
          ],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        expect(
          find.byKey(const ValueKey('driver-offer-card-offer-1')),
          findsOneWidget,
        );
        expect(find.text('Pasajero'), findsNothing);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers.first.passengerFirstName, isNull);
      },
    );

    testWidgets(
      'M: firstName en 50 Offers no rompe la lista lazy ni el estado',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.available,
            ),
          ],
        );
        final fiftyOffers = List.generate(
          50,
          (index) => _offerFixture(
            id: 'offer-$index',
            distanceToOriginMeters: (index + 1) * 50,
            passengerFirstName: 'Passenger $index',
          ),
        );
        final offers = _FakeOffersRepository(
          pendingProposalsQueue: [const <DriverPendingProposal>[]],
          activeOffersQueue: [fiftyOffers],
        );

        await _pumpHome(
          tester,
          rides: rides,
          operations: operations,
          offers: offers,
        );
        await tester.pump();
        await _openSolicitudesTab(tester);

        expect(tester.takeException(), isNull);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugOffers, hasLength(50));
        expect(state.debugOffers.first.passengerFirstName, 'Passenger 0');
        expect(state.debugOffers.last.passengerFirstName, 'Passenger 49');
      },
    );
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

      // "Estás desconectado" aparece dos veces por diseño: en la
      // tarjeta flotante de disponibilidad y en el título del sheet.
      expect(find.text('Estás desconectado'), findsWidgets);

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

    await tester.tap(find.byKey(const ValueKey('driver-home-logout-button')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('driver-home-logout-button')),
      warnIfMissed: false,
    );
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

      expect(find.text('Disponible'), findsOneWidget);
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

    await _openSolicitudesTab(tester);
    await _selectOfferCard(tester, 'offer-1');

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

    await _openSolicitudesTab(tester);
    await _selectOfferCard(tester, 'offer-1');

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

    await _openSolicitudesTab(tester);
    await _selectOfferCard(tester, 'offer-1');

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

      await _openSolicitudesTab(tester);
      await _selectOfferCard(tester, 'offer-1');

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

      await _openSolicitudesTab(tester);
      await _selectOfferCard(tester, 'offer-1');

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

      await _openSolicitudesTab(tester);
      await _selectOfferCard(tester, 'offer-1');

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

      await _openSolicitudesTab(tester);
      await _selectOfferCard(tester, 'offer-1');

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
      await _openSolicitudesTab(tester);
      await _selectOfferCard(tester, 'offer-1');

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

  group('Sin tarjeta superior de disponibilidad (cierre visual)', () {
    testWidgets(
      'A/B/C/D: AVAILABLE no tiene tarjeta "Estás en línea" ni Switch; '
      'sí tiene "Disponible" y el CTA "Desconectarme"',
      (tester) async {
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

        expect(find.text('Estás en línea'), findsNothing);
        expect(find.byType(Switch), findsNothing);

        expect(find.text('Disponible'), findsOneWidget);
        expect(find.text('Desconectarme'), findsOneWidget);
      },
    );

    testWidgets('E/F/G: OFFLINE no tiene tarjeta superior redundante; "Estás '
        'desconectado" aparece UNA sola vez (en el sheet) junto al CTA '
        '"Conectarme"', (tester) async {
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

      expect(find.byType(Switch), findsNothing);
      // Ya no hay 2 apariciones (tarjeta + sheet): solo la del sheet.
      expect(find.text('Estás desconectado'), findsOneWidget);
      expect(find.text('Conectarme'), findsOneWidget);
    });

    testWidgets(
      'Conectarme/Desconectarme siguen cambiando el estado operativo sin '
      'el switch (mismos goOnline/goOffline de siempre)',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        await tester.ensureVisible(find.text('Conectarme'));
        await tester.tap(find.text('Conectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugStatus, DriverHomeStatus.available);
        expect(operations.goOnlineCalls, 1);

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(state.debugStatus, DriverHomeStatus.offline);
        expect(operations.goOfflineCalls, 1);
      },
    );
  });

  group('Duración "en línea"', () {
    testWidgets(
      'AVAILABLE con connectedAt muestra la tarjeta EN LÍNEA sin "—"',
      (tester) async {
        final connectedAt = DateTime.utc(2026, 8, 10, 9);

        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            DriverOperationalState(
              status: DriverOperationalStatus.available,
              connectedAt: connectedAt,
            ),
          ],
          heartbeatQueue: [
            DriverOperationalState(
              status: DriverOperationalStatus.available,
              connectedAt: connectedAt,
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

        expect(find.text('EN LÍNEA'), findsOneWidget);
        // El valor exacto depende del reloj real; solo garantizamos
        // que no se muestra "—" cuando sí hay connectedAt.
        expect(find.text('—'), findsNothing);
      },
    );

    testWidgets('AVAILABLE sin connectedAt muestra "—" y nunca "0m"', (
      tester,
    ) async {
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

      expect(find.text('EN LÍNEA'), findsOneWidget);
      expect(find.text('0m'), findsNothing);
      expect(find.text('—'), findsOneWidget);
    });
  });

  group('Stats reales en el sheet', () {
    testWidgets('muestra grossAmount y completedRides exactos de Backend', (
      tester,
    ) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        dailyStatsResult: DriverDailyStats.fromJson(const {
          'businessDate': '2026-08-10',
          'timezone': 'America/Lima',
          'completedRides': 5,
          'grossAmount': '18.50',
          'currency': 'PEN',
          'asOf': '2026-08-10T15:00:00.000Z',
        }),
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('S/ 18.50'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('GANADO HOY'), findsOneWidget);
      expect(find.text('VIAJES HOY'), findsOneWidget);
    });

    testWidgets('G: OFFLINE también conserva las stats reales', (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(status: DriverOperationalStatus.offline),
        ],
        dailyStatsResult: DriverDailyStats.fromJson(const {
          'businessDate': '2026-08-10',
          'timezone': 'America/Lima',
          'completedRides': 1,
          'grossAmount': '4.50',
          'currency': 'PEN',
          'asOf': '2026-08-10T15:00:00.000Z',
        }),
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('S/ 4.50'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('GANADO HOY'), findsOneWidget);
      expect(find.text('VIAJES HOY'), findsOneWidget);
      // OFFLINE nunca muestra la tarjeta EN LÍNEA.
      expect(find.text('EN LÍNEA'), findsNothing);
    });

    testWidgets('F: AVAILABLE conserva las stats reales', (tester) async {
      final rides = _FakeRidesRepository();
      final operations = _FakeOperationsRepository(
        statusQueue: [
          const DriverOperationalState(
            status: DriverOperationalStatus.available,
          ),
        ],
        dailyStatsResult: DriverDailyStats.fromJson(const {
          'businessDate': '2026-08-10',
          'timezone': 'America/Lima',
          'completedRides': 1,
          'grossAmount': '4.50',
          'currency': 'PEN',
          'asOf': '2026-08-10T15:00:00.000Z',
        }),
      );
      final offers = _FakeOffersRepository();

      await _pumpHome(
        tester,
        rides: rides,
        operations: operations,
        offers: offers,
      );
      await tester.pump();

      expect(find.text('S/ 4.50'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('EN LÍNEA'), findsOneWidget);
    });
  });

  group('Fallback OFFLINE y recenter de mapa', () {
    testWidgets(
      'A: OFFLINE sin adquisición de GPS muestra copy veraz, no "Obteniendo tu ubicación..."',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(
          find.text('Conéctate para activar tu ubicación'),
          findsOneWidget,
        );
        expect(find.text('Obteniendo tu ubicación...'), findsNothing);
      },
    );

    testWidgets(
      'B: al pulsar Conectarme y quedar adquiriendo GPS, sí muestra "Obteniendo tu ubicación..."',
      (tester) async {
        // GPS que nunca resuelve: el flujo queda "adquiriendo" de verdad.
        driverHomeGpsFetcherOverride = ({required requestPermission}) {
          return Completer<Position>().future;
        };

        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(
          find.text('Conéctate para activar tu ubicación'),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Conectarme'));
        await tester.tap(find.text('Conectarme'));
        await tester.pump();

        expect(find.text('Obteniendo tu ubicación...'), findsOneWidget);
        expect(find.text('Conéctate para activar tu ubicación'), findsNothing);
      },
    );

    testWidgets('C: el botón custom de recentrar existe con Position válida', (
      tester,
    ) async {
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

      expect(find.byIcon(Icons.my_location), findsOneWidget);
    });

    testWidgets(
      'E: tap en recentrar obtiene una Position NUEVA (no la cacheada) y actualiza el estado',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugLastPosition.latitude, -12.05);

        // Position C: distinta de la Position B ya cacheada en
        // _lastPosition. El recenter NUNCA debe reutilizar B.
        driverHomeGpsFetcherOverride = ({required requestPermission}) async {
          return _fakePosition(lat: -13.9, lng: -76.1, accuracy: 6);
        };

        await tester.tap(
          find.byKey(const ValueKey('driver-home-recenter-button')),
        );
        await tester.pump();

        expect(state.debugLastPosition.latitude, -13.9);
        expect(state.debugLastPosition.longitude, -76.1);
      },
    );

    testWidgets(
      'F: un error de GPS durante el recenter no altera la Position/cámara vigente',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        final latBefore = state.debugLastPosition.latitude;

        driverHomeGpsFetcherOverride = ({required requestPermission}) async {
          throw Exception('gps timeout');
        };

        await tester.tap(
          find.byKey(const ValueKey('driver-home-recenter-button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(state.debugLastPosition.latitude, latBefore);
        expect(
          find.text('No se pudo obtener tu ubicación GPS.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'G: doble tap en recentrar no dispara dos fetches concurrentes',
      (tester) async {
        var fetchCalls = 0;
        final completer = Completer<Position>();

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

        driverHomeGpsFetcherOverride = ({required requestPermission}) {
          fetchCalls++;
          return completer.future;
        };

        final button = find.byKey(
          const ValueKey('driver-home-recenter-button'),
        );

        await tester.tap(button);
        await tester.pump();
        await tester.tap(button, warnIfMissed: false);
        await tester.pump();

        expect(fetchCalls, 1);

        completer.complete(_fakePosition(lat: -10, lng: -70));
        await tester.pump();
      },
    );

    testWidgets(
      'I: LocationAccuracy precise no muestra el aviso de precisión',
      (tester) async {
        driverHomeLocationAccuracyFetcherOverride = () async {
          return LocationAccuracyStatus.precise;
        };

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
        await tester.pump();

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(
          state.debugLocationAccuracyStatus,
          LocationAccuracyStatus.precise,
        );
        expect(
          find.text('Activa la ubicación precisa para mejorar tu posición'),
          findsNothing,
        );
      },
    );

    testWidgets('J: LocationAccuracy reduced muestra el diagnóstico correcto', (
      tester,
    ) async {
      driverHomeLocationAccuracyFetcherOverride = () async {
        return LocationAccuracyStatus.reduced;
      };

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
      await tester.pump();

      final dynamic state = tester.state(find.byType(DriverHomeScreen));
      expect(state.debugLocationAccuracyStatus, LocationAccuracyStatus.reduced);
      expect(
        find.text('Activa la ubicación precisa para mejorar tu posición'),
        findsOneWidget,
      );
    });

    testWidgets(
      'K: G4B2 eliminó el pill "Ubicación GPS activa" del tab Inicio; el texto ya no aparece en ningún estado',
      (tester) async {
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

        expect(find.text('Ubicación GPS activa'), findsNothing);
      },
    );

    testWidgets(
      'C: permissionDenied → myLocationEnabled queda en false (punto azul apagado)',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugLastPosition, isNotNull);
        expect(state.debugMyLocationSafe, isTrue);

        state.debugSetGpsStatus(DriverGpsStatus.permissionDenied);
        await tester.pump();

        // La Position vieja sigue cacheada, pero ya no es seguro
        // activar el punto azul nativo.
        expect(state.debugLastPosition, isNotNull);
        expect(state.debugMyLocationSafe, isFalse);

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.myLocationEnabled, isFalse);
      },
    );

    testWidgets(
      'D: permissionDeniedForever → myLocationEnabled queda en false',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));

        state.debugSetGpsStatus(DriverGpsStatus.permissionDeniedForever);
        await tester.pump();

        expect(state.debugMyLocationSafe, isFalse);
      },
    );

    testWidgets('serviceDisabled → myLocationEnabled queda en false', (
      tester,
    ) async {
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

      final dynamic state = tester.state(find.byType(DriverHomeScreen));

      state.debugSetGpsStatus(DriverGpsStatus.serviceDisabled);
      await tester.pump();

      expect(state.debugMyLocationSafe, isFalse);
    });

    testWidgets(
      'J: el bottom sheet OFFLINE ya no contiene el icono power redundante',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        // Antes había 3 apariciones de este icono en OFFLINE: el
        // fallback del mapa + el círculo redundante sobre el título
        // del sheet + el del botón "Conectarme". El círculo del
        // sheet ya no debe estar: solo quedan mapa + botón.
        expect(find.byIcon(Icons.power_settings_new), findsNWidgets(2));
      },
    );

    testWidgets(
      'K: "Estás desconectado" sigue presente tras quitar el icono redundante',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(find.text('Estás desconectado'), findsWidgets);
        expect(
          find.text('Conéctate para comenzar a recibir solicitudes'),
          findsOneWidget,
        );
        expect(find.text('Conectarme'), findsOneWidget);
      },
    );
  });

  group('Viewport del mapa (geometría física, sin padding dinámico)', () {
    testWidgets(
      'K/L/M: el mapa ocupa una región física acotada — no Positioned.fill '
      'detrás de todo el bottom sheet — y GoogleMap.padding es zero',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

        final mapSize = tester.getSize(find.byType(GoogleMap));

        // El mapa ya NO llena el alto disponible: ocupa una franja
        // física acotada (L), no un Positioned.fill detrás de todo
        // el bottom sheet.
        expect(mapSize.height, lessThan(844 * 0.6));
        expect(mapSize.height, greaterThanOrEqualTo(200));

        // M: sin padding dinámico dependiente del alto del sheet.
        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.padding, EdgeInsets.zero);
      },
    );

    testWidgets(
      'O/Q: auto-center usa exactamente position.latitude/longitude, sin '
      'offset geográfico — vía el cameraRequest declarativo',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        final request = state.debugCameraRequest as DriverMapCameraRequest?;

        // Mismos valores exactos que _fakePosition() por defecto
        // (-12.05 / -77.05): ni swap, ni rounding, ni offset.
        expect(request, isNotNull);
        expect(request!.target.latitude, -12.05);
        expect(request.target.longitude, -77.05);

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.initialCameraPosition.target.latitude, -12.05);
        expect(map.initialCameraPosition.target.longitude, -77.05);
      },
    );

    testWidgets(
      'P/Q: recenter con Position fresca emite un cameraRequest nuevo con '
      'esas mismas coordenadas exactas, sin offset geográfico',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        final idBeforeRecenter =
            (state.debugCameraRequest as DriverMapCameraRequest?)?.id;

        driverHomeGpsFetcherOverride = ({required requestPermission}) async {
          return _fakePosition(lat: -8.5, lng: -74.9);
        };

        await tester.tap(
          find.byKey(const ValueKey('driver-home-recenter-button')),
        );
        await tester.pump();
        await tester.pump();

        final request = state.debugCameraRequest as DriverMapCameraRequest?;

        expect(request, isNotNull);
        expect(request!.id, isNot(idBeforeRecenter));
        expect(request.target.latitude, -8.5);
        expect(request.target.longitude, -74.9);

        final map = tester.widget<GoogleMap>(find.byType(GoogleMap));
        expect(map.initialCameraPosition.target.latitude, -8.5);
        expect(map.initialCameraPosition.target.longitude, -74.9);
      },
    );
  });

  group('Lifecycle: controller nunca sale de DriverHomeMap', () {
    testWidgets(
      'H: AVAILABLE → OFFLINE mantiene el GoogleMap montado (con la última '
      'Position conocida), en vez de destruirlo y perder el controller',
      (tester) async {
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

        expect(find.byType(GoogleMap), findsOneWidget);

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugStatus, DriverHomeStatus.offline);

        // El mapa sigue vivo: Home ya no destruye DriverHomeMap solo
        // por pasar a OFFLINE (ni conserva ni pierde un controller,
        // porque nunca lo tuvo). Ahora queda oculto detrás del overlay
        // opaco, pero el widget real sigue montado.
        expect(find.byType(GoogleMap), findsOneWidget);
        expect(find.text('Estás desconectado'), findsOneWidget);
      },
    );

    testWidgets(
      'I: OFFLINE → AVAILABLE de nuevo emite un cameraRequest nuevo y sigue '
      'usando el mismo GoogleMap (nunca se recreó)',
      (tester) async {
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

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        final firstRequestId =
            (state.debugCameraRequest as DriverMapCameraRequest?)?.id;

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.ensureVisible(find.text('Conectarme'));
        await tester.tap(find.text('Conectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(state.debugStatus, DriverHomeStatus.available);
        expect(find.byType(GoogleMap), findsOneWidget);

        final secondRequestId =
            (state.debugCameraRequest as DriverMapCameraRequest?)?.id;

        expect(secondRequestId, isNot(firstRequestId));
      },
    );

    testWidgets(
      'J: 3 ciclos Conectarme→Desconectarme→Conectarme consecutivos no '
      'producen ninguna excepción (ni Bad state, ni ninguna otra)',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(find.text('Estás desconectado'), findsOneWidget);
        // Todavía sin Position: el fallback preservado, sin mapa real.
        expect(find.byType(GoogleMap), findsNothing);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));

        for (var cycle = 0; cycle < 3; cycle++) {
          await tester.ensureVisible(find.text('Conectarme'));
          await tester.tap(find.text('Conectarme')); // Conectarme.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            tester.takeException(),
            isNull,
            reason: 'ciclo $cycle: connect',
          );
          expect(state.debugStatus, DriverHomeStatus.available);
          expect(find.byType(GoogleMap), findsOneWidget);

          await tester.ensureVisible(find.text('Desconectarme'));
          await tester.tap(find.text('Desconectarme')); // Desconectarme.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(
            tester.takeException(),
            isNull,
            reason: 'ciclo $cycle: disconnect',
          );
          expect(state.debugStatus, DriverHomeStatus.offline);

          // A partir del primer connect, el mapa nunca se vuelve a
          // destruir: sigue montado con la última Position conocida.
          expect(find.byType(GoogleMap), findsOneWidget);
        }
      },
    );
  });

  group('Overlay OFFLINE sobre el mapa vivo', () {
    testWidgets(
      'H: OFFLINE inicial (sin Position previa) muestra el fallback de '
      'DriverHomeMap sin overlay duplicado encima',
      (tester) async {
        final rides = _FakeRidesRepository();
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(find.byType(GoogleMap), findsNothing);
        // Una sola aparición: el propio fallback de DriverHomeMap. Si
        // el overlay de Home también se dibujara acá, habría 2.
        expect(
          find.text('Conéctate para activar tu ubicación'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'I/J: OFFLINE después de una Position previa oculta visualmente el '
      'GoogleMap (overlay opaco con el mismo copy) y esconde el botón '
      'de recentrar, sin destruir el mapa',
      (tester) async {
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

        // K/L: AVAILABLE — mapa y botón de recentrar visibles.
        expect(find.byType(GoogleMap), findsOneWidget);
        expect(
          find.byKey(const ValueKey('driver-home-recenter-button')),
          findsOneWidget,
        );

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // El GoogleMap real SIGUE montado (no se destruyó)...
        expect(find.byType(GoogleMap), findsOneWidget);
        // ...pero el overlay opaco con el mismo copy de fallback lo
        // cubre visualmente...
        expect(
          find.text('Conéctate para activar tu ubicación'),
          findsOneWidget,
        );
        // ...y el botón de recentrar queda oculto: no hay forma de
        // interactuar con un mapa que no se percibe.
        expect(
          find.byKey(const ValueKey('driver-home-recenter-button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'tocar sobre el área del overlay OFFLINE no lanza ninguna excepción '
      '(el overlay absorbe el gesto en vez de dejarlo pasar al mapa)',
      (tester) async {
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

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(
          find.text('Conéctate para activar tu ubicación'),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(tester.takeException(), isNull);

        final dynamic state = tester.state(find.byType(DriverHomeScreen));
        expect(state.debugStatus, DriverHomeStatus.offline);
      },
    );

    testWidgets(
      'M: AVAILABLE → OFFLINE conserva el MISMO State de DriverHomeMap '
      '(no se destruye/recrea)',
      (tester) async {
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

        final stateBefore = tester.state(find.byType(DriverHomeMap));

        await tester.ensureVisible(find.text('Desconectarme'));
        await tester.tap(find.text('Desconectarme'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final stateAfter = tester.state(find.byType(DriverHomeMap));

        expect(identical(stateBefore, stateAfter), isTrue);
      },
    );
  });

  group('Color crema único / sin franja residual', () {
    testWidgets(
      'P: Scaffold.backgroundColor y el fondo del bottom sheet usan la '
      'MISMA constante DriverPalette.cream',
      (tester) async {
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

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(scaffold.backgroundColor, DriverPalette.cream);

        // El Container inmediato dentro de la SafeArea del sheet es
        // el que pinta el fondo cream del sheet (borde redondeado +
        // sombra). Se ubica por su BoxDecoration con ese color.
        final sheetContainers = find.byWidgetPredicate((widget) {
          if (widget is! Container) {
            return false;
          }

          final decoration = widget.decoration;

          return decoration is BoxDecoration &&
              decoration.color == DriverPalette.cream &&
              decoration.borderRadius != null;
        });

        expect(sheetContainers, findsWidgets);
      },
    );

    testWidgets('Q: el código fuente ya no usa Matrix4.translationValues para '
        'desplazar el bottom sheet', (tester) async {
      final source = File(
        'lib/features/driver/presentation/driver_home_screen.dart',
      ).readAsStringSync();

      expect(source.contains('Matrix4.translationValues'), isFalse);
      expect(source.contains('transform:'), isFalse);
    });
  });

  group('Checkpoint E: retorno post-PAID (Backend es autoridad)', () {
    testWidgets(
      'sin active ride ni pending payments y status AVAILABLE: '
      'Home muestra "Disponible"',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: const [[]],
        );
        final connectedAt = DateTime.utc(2026, 8, 10, 9);
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
              lastSeenAt: connectedAt,
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

        expect(find.text('Disponible'), findsOneWidget);
        expect(find.text('Estás desconectado'), findsNothing);
      },
    );

    testWidgets(
      'sin active ride ni pending payments y status OFFLINE: '
      'Home muestra "Estás desconectado" (no se fuerza AVAILABLE)',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: const [[]],
        );
        final operations = _FakeOperationsRepository(
          statusQueue: [
            const DriverOperationalState(
              status: DriverOperationalStatus.offline,
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

        expect(find.text('Estás desconectado'), findsWidgets);
        expect(find.text('Disponible'), findsNothing);
      },
    );

    testWidgets(
      'múltiples CASH PENDING previos: un pago resuelto no oculta el '
      'restante (no se limpia la lista completa localmente)',
      (tester) async {
        final rides = _FakeRidesRepository(
          activeRideQueue: [null],
          pendingPaymentsQueue: [
            [
              _pendingPaymentFixture(
                rideId: 'ride-b-pending',
                method: 'CASH',
                status: 'PENDING',
              ),
            ],
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

        expect(
          find.text('COMPLETED_PAYMENT_ROUTE ride-b-pending'),
          findsOneWidget,
        );
        expect(operations.getStatusCalls, 0);
      },
    );
  });

  group('Responsive', () {
    testWidgets('390x844 sin overflow en los estados principales', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _runResponsiveScenarios(tester);
    });

    testWidgets('360x640 sin overflow en los estados principales', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _runResponsiveScenarios(tester);
    });

    testWidgets('412x915 sin overflow en los estados principales', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await _runResponsiveScenarios(tester);
    });
  });
}

Future<void> _runResponsiveScenarios(WidgetTester tester) async {
  // RESTORING: se queda pendiente indefinidamente (gate sin completar).
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository()..gate = Completer<DriverActiveRide?>(),
    operations: _FakeOperationsRepository(),
    offers: _FakeOffersRepository(),
  );

  // OFFLINE: el bug real era que el texto del fallback quedaba
  // cubierto por el bottom sheet sin producir overflow, por eso acá
  // se verifica explícitamente que el texto sea visible, no solo
  // que no haya overflow.
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(),
    operations: _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.offline),
      ],
    ),
    offers: _FakeOffersRepository(),
    extraChecks: () {
      expect(find.text('Conéctate para activar tu ubicación'), findsOneWidget);
    },
  );

  // AVAILABLE con stats, GPS y connectedAt (la vista más cargada).
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(),
    operations: _FakeOperationsRepository(
      statusQueue: [
        DriverOperationalState(
          status: DriverOperationalStatus.available,
          connectedAt: DateTime.utc(2026, 8, 10, 9),
        ),
      ],
      dailyStatsResult: DriverDailyStats.fromJson(const {
        'businessDate': '2026-08-10',
        'timezone': 'America/Lima',
        'completedRides': 12,
        'grossAmount': '145.90',
        'currency': 'PEN',
        'asOf': '2026-08-10T15:00:00.000Z',
      }),
    ),
    offers: _FakeOffersRepository(),
    extraChecks: () {
      // Sin tarjeta superior ni switch: el botón custom de recentrar
      // se sigue mostrando solo, sin solaparse ni desbordar en
      // ninguno de los tamaños de pantalla probados.
      expect(find.text('Estás en línea'), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(
        find.byKey(const ValueKey('driver-home-recenter-button')),
        findsOneWidget,
      );
    },
  );

  // OFFERED (G4B2: la lista vive en la tab Solicitudes).
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(),
    operations: _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    ),
    offers: _FakeOffersRepository(
      activeOffersQueue: [
        [_offer()],
      ],
    ),
    beforeCheck: _openSolicitudesTab,
  );

  // PROPOSED múltiples (también en la tab Solicitudes).
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(),
    operations: _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    ),
    offers: _FakeOffersRepository(
      pendingProposalsQueue: [
        [
          _pendingProposal(offerId: 'offer-1'),
          _pendingProposal(offerId: 'offer-2'),
          _pendingProposal(offerId: 'offer-3'),
        ],
      ],
    ),
    beforeCheck: _openSolicitudesTab,
  );

  // Solicitudes con 50 Offers: la lista debe seguir siendo lazy y sin
  // overflow con el volumen máximo esperado (Fase 24).
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(),
    operations: _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.available),
      ],
    ),
    offers: _FakeOffersRepository(
      activeOffersQueue: [
        List.generate(
          50,
          (index) => _offerFixture(
            id: 'offer-$index',
            distanceToOriginMeters: (index + 1) * 100,
          ),
        ),
      ],
    ),
    beforeCheck: _openSolicitudesTab,
  );

  // BUSY recovery.
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(activeRideQueue: [null, null]),
    operations: _FakeOperationsRepository(
      statusQueue: [
        const DriverOperationalState(status: DriverOperationalStatus.busy),
      ],
    ),
    offers: _FakeOffersRepository(),
  );

  // ERROR.
  await _pumpAndExpectNoOverflow(
    tester,
    rides: _FakeRidesRepository(
      activeRideQueue: [
        DioException(
          requestOptions: RequestOptions(path: 'drivers/me/rides/active'),
          type: DioExceptionType.connectionError,
        ),
      ],
    ),
    operations: _FakeOperationsRepository(),
    offers: _FakeOffersRepository(),
  );
}

Future<void> _pumpAndExpectNoOverflow(
  WidgetTester tester, {
  required _FakeRidesRepository rides,
  required _FakeOperationsRepository operations,
  required _FakeOffersRepository offers,
  void Function()? extraChecks,
  Future<void> Function(WidgetTester tester)? beforeCheck,
}) async {
  await _pumpHome(tester, rides: rides, operations: operations, offers: offers);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));

  await beforeCheck?.call(tester);

  expect(tester.takeException(), isNull);
  extraChecks?.call();

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// G4B2: el mailbox de Offers/proposals vive exclusivamente en la
/// tab "Solicitudes" (Inicio nunca las muestra). Los tests que
/// necesiten ver esa UI deben cambiar de tab explícitamente primero,
/// igual que lo haría el Driver real tocando el bottom nav.
Future<void> _openSolicitudesTab(WidgetTester tester) async {
  await tester.tap(find.text('Solicitudes'));
  await tester.pump();
}

/// G4B2 (Fase 12): la lista de Solicitudes es un `ListView.builder`
/// lazy real, sin `shrinkWrap`: los items fuera del viewport (+cache
/// extent) simplemente no existen en el árbol todavía, así que
/// `ensureVisible` no sirve para revelarlos (solo funciona sobre
/// widgets ya construidos). Hay que scrollear de verdad.
Future<void> _scrollToOfferCard(WidgetTester tester, String offerId) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey('driver-offer-card-$offerId')),
    250,
    scrollable: find.byType(Scrollable),
  );
}

/// G4B-R2: ninguna Offer se abre sola. Los tests que necesiten ver
/// acciones/expansión deben tocar la tarjeta explícitamente primero,
/// igual que lo haría el Driver real.
///
/// G4B-R4: el toggle vive en el header, siempre en la misma posición
/// relativa (arriba de la tarjeta) tanto compacta como expandida.
/// Se scrollea directo a esa key (no a la tarjeta completa): una
/// tarjeta ya expandida es mucho más alta y `scrollUntilVisible`
/// sobre la key exterior puede converger a una posición donde el
/// header queda tapado por el bottom nav.
///
/// `scrollUntilVisible` solo garantiza visibilidad PARCIAL (se
/// detiene apenas detecta cualquier intersección con el viewport),
/// lo que puede dejar el header justo detrás del bottom nav. Por
/// eso se completa con `ensureVisible`, que sí calcula el offset
/// exacto para traerlo completamente a la vista una vez construido.
Future<void> _selectOfferCard(WidgetTester tester, String offerId) async {
  final toggle = find.byKey(ValueKey('driver-offer-card-toggle-$offerId'));

  await tester.scrollUntilVisible(toggle, 250, scrollable: find.byType(Scrollable));
  await tester.ensureVisible(toggle);
  await tester.pump();

  await tester.tap(toggle);
  await tester.pump();
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
        path: '/completed-payment/:rideId',
        builder: (context, state) => Scaffold(
          body: Text(
            'COMPLETED_PAYMENT_ROUTE ${state.pathParameters['rideId']}',
          ),
        ),
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

Position _fakePosition({
  double lat = -12.05,
  double lng = -77.05,
  double accuracy = 8,
  DateTime? timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp ?? DateTime.utc(2026, 8, 10),
    accuracy: accuracy,
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

DriverPendingPayment _pendingPaymentFixture({
  required String rideId,
  String method = 'CASH',
  String status = 'PENDING',
}) {
  return DriverPendingPayment(
    rideId: rideId,
    rideStatus: 'COMPLETED',
    originAddress: 'Origen',
    destinationAddress: 'Destino',
    completedAt: DateTime.utc(2026, 8, 10, 12),
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

/// Variante parametrizable de [_offer] para escenarios G4B1 con
/// varias Offers simultáneas (distintos ids/distancias/tarifas).
DriverRideOffer _offerFixture({
  required String id,
  num distanceToOriginMeters = 500,
  String passengerOfferFare = '7.00',
  String estimatedFare = '7.00',
  String originAddress = 'Origen',
  String destinationAddress = 'Destino',
  String? passengerFirstName,
}) {
  return DriverRideOffer(
    id: id,
    rideId: 'ride-$id',
    status: 'OFFERED',
    distanceToOriginMeters: distanceToOriginMeters,
    estimatedFare: estimatedFare,
    passengerOfferFare: passengerOfferFare,
    proposedFare: null,
    proposedAt: null,
    currency: 'PEN',
    originAddress: originAddress,
    destinationAddress: destinationAddress,
    expiresAt: DateTime.utc(2030),
    passengerFirstName: passengerFirstName,
  );
}

class _FakeRidesRepository extends DriverRidesRepository {
  _FakeRidesRepository({List<Object?>? activeRideQueue, this.pendingPaymentsQueue})
    : _queue = List.of(activeRideQueue ?? const [null]),
      super(Dio());

  final List<Object?> _queue;
  int getActiveRideCalls = 0;

  /// Cuando se define, `getActiveRide` queda pendiente indefinidamente
  /// hasta que el test complete este gate (usado para probar dispose).
  Completer<DriverActiveRide?>? gate;

  /// Cola de resultados para `getPendingPayments`. `null`/vacía se
  /// comporta como "sin pendientes" (default seguro para todos los
  /// tests que no auditan Checkpoint D explícitamente): así ningún
  /// test existente necesita conocer este método nuevo.
  final List<Object>? pendingPaymentsQueue;
  int getPendingPaymentsCalls = 0;

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

  @override
  Future<List<DriverPendingPayment>> getPendingPayments() async {
    getPendingPaymentsCalls++;

    final queue = pendingPaymentsQueue;

    if (queue == null || queue.isEmpty) {
      return const [];
    }

    final next = queue.length > 1 ? queue.removeAt(0) : queue.first;

    if (next is DioException) {
      throw next;
    }

    return next as List<DriverPendingPayment>;
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

  /// Último `offerId` recibido por cada acción: permite comprobar en
  /// tests G4B1 que accept/counterOffer/reject operan sobre la Offer
  /// realmente seleccionada, no sobre la primera de la lista.
  String? lastAcceptOfferId;
  String? lastCounterOfferId;
  String? lastRejectOfferId;

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
    lastAcceptOfferId = offerId;

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
    lastCounterOfferId = offerId;

    final result = counterOfferResult;

    if (result is DioException) {
      throw result;
    }

    return result as DriverRideOffer;
  }

  @override
  Future<void> rejectOffer(String offerId) async {
    rejectOfferCalls++;
    lastRejectOfferId = offerId;

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
