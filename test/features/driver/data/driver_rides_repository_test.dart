import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_rides_repository.dart';
import 'package:driver/features/driver/domain/driver_cancellation_reason.dart';

void main() {
  group('cancelRide', () {
    test('POST al endpoint real con el rideId en la URL', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.cancelRide(
        rideId: 'ride-42',
        reason: DriverCancellationReason.cannotReachPickup,
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, 'drivers/me/rides/ride-42/cancel');
    });

    test('envía el valor wire correcto del motivo seleccionado', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.safetyConcern,
      );

      expect(adapter.lastData?['reason'], 'SAFETY_CONCERN');
    });

    test('reasonDetail null: se omite del body', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
      );

      expect(adapter.lastData?.containsKey('reasonDetail'), isFalse);
    });

    test('reasonDetail vacío/solo espacios: se omite del body', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
        reasonDetail: '   ',
      );

      expect(adapter.lastData?.containsKey('reasonDetail'), isFalse);
    });

    test('reasonDetail válido: se envía trimeado', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
        reasonDetail: '  El pasajero canceló por teléfono  ',
      );

      expect(
        adapter.lastData?['reasonDetail'],
        'El pasajero canceló por teléfono',
      );
    });

    test('propaga DioException (p.ej. 400/409) sin envolverla', () async {
      final adapter = _CapturingAdapter()..statusCode = 400;
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      expect(
        () => repository.cancelRide(
          rideId: 'ride-1',
          reason: DriverCancellationReason.other,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('startRideWaiting', () {
    test('POST al endpoint real con el rideId en la URL, sin body', () async {
      final adapter = _CapturingAdapter()..responseData = _waitingJson();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.startRideWaiting('ride-42');

      expect(adapter.lastRequest?.method, 'POST');
      expect(
        adapter.lastRequest?.path,
        'drivers/me/rides/ride-42/waiting/start',
      );
      expect(adapter.lastRequest?.data, isNull);
    });

    test(
      'parsea el RideWaiting real de la respuesta (idempotente incluido)',
      () async {
        final adapter = _CapturingAdapter()
          ..responseData = _waitingJson(
            remainingWaitingSeconds: 120,
            canReportNoShow: true,
          );
        final repository = DriverRidesRepository(
          Dio()..httpClientAdapter = adapter,
        );

        final waiting = await repository.startRideWaiting('ride-1');

        expect(waiting.remainingWaitingSeconds, 120);
        expect(waiting.canReportNoShow, isTrue);
      },
    );

    test('propaga DioException sin envolverla', () async {
      final adapter = _CapturingAdapter()..statusCode = 409;
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      expect(
        () => repository.startRideWaiting('ride-1'),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('getRideWaiting', () {
    test('GET al endpoint real', () async {
      final adapter = _CapturingAdapter()..responseData = _waitingJson();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.getRideWaiting('ride-7');

      expect(adapter.lastRequest?.method, 'GET');
      expect(adapter.lastRequest?.path, 'drivers/me/rides/ride-7/waiting');
    });

    test('200: parsea el RideWaiting real', () async {
      final adapter = _CapturingAdapter()
        ..responseData = _waitingJson(remainingWaitingSeconds: 90);
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      final waiting = await repository.getRideWaiting('ride-1');

      expect(waiting, isNotNull);
      expect(waiting!.remainingWaitingSeconds, 90);
    });

    test('404: devuelve null (no existe espera activa)', () async {
      final adapter = _CapturingAdapter()..statusCode = 404;
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      final waiting = await repository.getRideWaiting('ride-1');

      expect(waiting, isNull);
    });

    test(
      '500: relanza DioException (nunca se confunde con "no existe espera")',
      () async {
        final adapter = _CapturingAdapter()..statusCode = 500;
        final repository = DriverRidesRepository(
          Dio()..httpClientAdapter = adapter,
        );

        expect(
          () => repository.getRideWaiting('ride-1'),
          throwsA(isA<DioException>()),
        );
      },
    );
  });

  group('reportPassengerNoShow', () {
    test('POST al endpoint real con el rideId en la URL, sin body', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.reportPassengerNoShow('ride-9');

      expect(adapter.lastRequest?.method, 'POST');
      expect(
        adapter.lastRequest?.path,
        'drivers/me/rides/ride-9/no-show/passenger',
      );
      expect(adapter.lastRequest?.data, isNull);
    });

    test('409 (early no-show): propaga DioException sin envolverla', () async {
      final adapter = _CapturingAdapter()
        ..statusCode = 409
        ..responseData = const {
          'message': 'Aún debes esperar',
          'remainingSeconds': 118,
        };
      final repository = DriverRidesRepository(
        Dio()..httpClientAdapter = adapter,
      );

      expect(
        () => repository.reportPassengerNoShow('ride-1'),
        throwsA(isA<DioException>()),
      );
    });
  });
}

Map<String, dynamic> _waitingJson({
  String rideId = 'ride-1',
  num remainingWaitingSeconds = 240,
  bool canReportNoShow = false,
}) {
  return {
    'rideId': rideId,
    'waitingStartedAt': '2026-08-10T12:00:00.000Z',
    'noShowAvailableAt': '2026-08-10T12:05:00.000Z',
    'requiredWaitingSeconds': 300,
    'elapsedWaitingSeconds': 300 - remainingWaitingSeconds,
    'remainingWaitingSeconds': remainingWaitingSeconds,
    'canReportNoShow': canReportNoShow,
    'startDistanceMeters': 35,
  };
}

/// Adapter mínimo sin dependencias externas: captura la request real
/// que construye el repositorio (path/método/body) y responde con un
/// JSON sintético, sin tocar la red.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastData;
  int statusCode = 200;
  Object? responseData = const <String, dynamic>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    lastData = options.data is Map<String, dynamic>
        ? options.data as Map<String, dynamic>
        : null;

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(responseData)));

    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
