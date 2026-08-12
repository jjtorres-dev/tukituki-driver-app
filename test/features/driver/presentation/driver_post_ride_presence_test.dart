import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_operations_repository.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';
import 'package:driver/features/driver/presentation/driver_post_ride_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NOTA: `presence.dispose()` se llama explícitamente al final de
  // cada test (no vía `addTearDown`). `addTearDown` corre DESPUÉS de
  // que `AutomatedTestWidgetsFlutterBinding` ya verificó que no
  // queden Timers pendientes, así que un dispose diferido llega
  // tarde para ese chequeo con un objeto que vive fuera del árbol
  // de widgets (no se auto-destruye como sí ocurre con
  // `tester.pumpWidget` al terminar el test).

  testWidgets('heartbeat inmediato al construir', (tester) async {
    final operations = _FakeOperationsRepository();
    final presence = DriverPostRidePresence(repository: operations);

    expect(operations.heartbeatCalls, 1);

    presence.dispose();
  });

  testWidgets('periodic ~30s: un heartbeat por intervalo, sin loop rápido', (
    tester,
  ) async {
    final operations = _FakeOperationsRepository();
    final presence = DriverPostRidePresence(repository: operations);

    final baseline = operations.heartbeatCalls;

    await tester.pump(const Duration(seconds: 30));
    expect(operations.heartbeatCalls, baseline + 1);

    await tester.pump(const Duration(seconds: 30));
    expect(operations.heartbeatCalls, baseline + 2);

    presence.dispose();
  });

  testWidgets('dispose cancela el timer: sin heartbeats residuales', (
    tester,
  ) async {
    final operations = _FakeOperationsRepository();
    final presence = DriverPostRidePresence(repository: operations);

    final baseline = operations.heartbeatCalls;

    presence.dispose();

    await tester.pump(const Duration(seconds: 90));

    expect(operations.heartbeatCalls, baseline);
  });

  testWidgets('dispose es idempotente (no lanza si se llama dos veces)', (
    tester,
  ) async {
    final operations = _FakeOperationsRepository();
    final presence = DriverPostRidePresence(repository: operations);

    presence.dispose();

    expect(presence.dispose, returnsNormally);
  });

  testWidgets('nunca llama updateLocation ni pide GPS (presence-only)', (
    tester,
  ) async {
    final operations = _FakeOperationsRepository();
    final presence = DriverPostRidePresence(repository: operations);

    await tester.pump(const Duration(seconds: 90));

    expect(operations.updateLocationCalls, 0);

    presence.dispose();
  });

  testWidgets(
    'nunca muta availability: sin goOnline/goOffline, incluso tras errores',
    (tester) async {
      final operations = _FakeOperationsRepository(
        heartbeatError: _dioError(400),
      );
      final presence = DriverPostRidePresence(repository: operations);

      await tester.pump(const Duration(seconds: 90));

      expect(operations.goOnlineCalls, 0);
      expect(operations.goOfflineCalls, 0);

      presence.dispose();
    },
  );

  group('Best-effort ante errores', () {
    testWidgets(
      '400 (Driver realmente OFFLINE): no rompe, sigue en el próximo ciclo',
      (tester) async {
        final operations = _FakeOperationsRepository(
          heartbeatError: _dioError(400),
        );
        final presence = DriverPostRidePresence(repository: operations);

        expect(operations.heartbeatCalls, 1);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(seconds: 30));

        expect(operations.heartbeatCalls, 2);
        expect(tester.takeException(), isNull);

        presence.dispose();
      },
    );

    testWidgets(
      'network/timeout: best-effort, espera el siguiente ciclo normal',
      (tester) async {
        final operations = _FakeOperationsRepository(
          heartbeatError: DioException(
            requestOptions: RequestOptions(
              path: 'drivers/me/operational-status/heartbeat',
            ),
            type: DioExceptionType.connectionError,
          ),
        );
        final presence = DriverPostRidePresence(repository: operations);

        final baseline = operations.heartbeatCalls;

        // Sin loop rápido: a mitad de intervalo todavía no hay un
        // segundo intento.
        await tester.pump(const Duration(seconds: 15));
        expect(operations.heartbeatCalls, baseline);

        await tester.pump(const Duration(seconds: 15));
        expect(operations.heartbeatCalls, baseline + 1);
        expect(tester.takeException(), isNull);

        presence.dispose();
      },
    );

    testWidgets('5xx: mismo criterio best-effort', (tester) async {
      final operations = _FakeOperationsRepository(
        heartbeatError: _dioError(503),
      );
      final presence = DriverPostRidePresence(repository: operations);

      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 30));

      expect(operations.heartbeatCalls, 2);
      expect(tester.takeException(), isNull);

      presence.dispose();
    });
  });

  group('Foreground / background', () {
    testWidgets(
      'paused detiene el timer; resumed reanuda con heartbeat inmediato '
      'sin duplicar timers',
      (tester) async {
        final operations = _FakeOperationsRepository();
        final presence = DriverPostRidePresence(repository: operations);

        final afterConstruct = operations.heartbeatCalls;
        expect(presence.debugIsActive, isTrue);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        expect(presence.debugIsActive, isFalse);

        await tester.pump(const Duration(seconds: 90));
        expect(operations.heartbeatCalls, afterConstruct);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();

        expect(operations.heartbeatCalls, afterConstruct + 1);
        expect(presence.debugIsActive, isTrue);

        // Un único timer reanudado: +1 por intervalo, no +2.
        await tester.pump(const Duration(seconds: 30));
        expect(operations.heartbeatCalls, afterConstruct + 2);

        presence.dispose();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );

    testWidgets('inactive también detiene el timer', (tester) async {
      final operations = _FakeOperationsRepository();
      final presence = DriverPostRidePresence(repository: operations);

      final baseline = operations.heartbeatCalls;

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );

      await tester.pump(const Duration(seconds: 90));

      expect(operations.heartbeatCalls, baseline);

      presence.dispose();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets(
      'dispose durante background no reanuda nada al volver resumed global',
      (tester) async {
        final operations = _FakeOperationsRepository();
        final presence = DriverPostRidePresence(repository: operations);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );

        presence.dispose();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        await tester.pump(const Duration(seconds: 90));

        expect(operations.heartbeatCalls, 1);
      },
    );
  });
}

DioException _dioError(int statusCode) {
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

class _FakeOperationsRepository extends DriverOperationsRepository {
  _FakeOperationsRepository({this.heartbeatError}) : super(Dio());

  /// Fija a propósito (no cola): todos los heartbeats de un mismo
  /// test comparten el mismo resultado, suficiente para probar el
  /// ciclo best-effort.
  DioException? heartbeatError;

  int heartbeatCalls = 0;
  int updateLocationCalls = 0;
  int goOnlineCalls = 0;
  int goOfflineCalls = 0;

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
}
