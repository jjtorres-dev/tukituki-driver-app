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
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      await repository.cancelRide(
        rideId: 'ride-42',
        reason: DriverCancellationReason.cannotReachPickup,
      );

      expect(adapter.lastRequest?.method, 'POST');
      expect(adapter.lastRequest?.path, 'drivers/me/rides/ride-42/cancel');
    });

    test('envía el valor wire correcto del motivo seleccionado', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.safetyConcern,
      );

      expect(adapter.lastData?['reason'], 'SAFETY_CONCERN');
    });

    test('reasonDetail null: se omite del body', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
      );

      expect(adapter.lastData?.containsKey('reasonDetail'), isFalse);
    });

    test('reasonDetail vacío/solo espacios: se omite del body', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
        reasonDetail: '   ',
      );

      expect(adapter.lastData?.containsKey('reasonDetail'), isFalse);
    });

    test('reasonDetail válido: se envía trimeado', () async {
      final adapter = _CapturingAdapter();
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      await repository.cancelRide(
        rideId: 'ride-1',
        reason: DriverCancellationReason.other,
        reasonDetail: '  El pasajero canceló por teléfono  ',
      );

      expect(adapter.lastData?['reasonDetail'], 'El pasajero canceló por teléfono');
    });

    test('propaga DioException (p.ej. 400/409) sin envolverla', () async {
      final adapter = _CapturingAdapter()..statusCode = 400;
      final repository = DriverRidesRepository(Dio()..httpClientAdapter = adapter);

      expect(
        () => repository.cancelRide(
          rideId: 'ride-1',
          reason: DriverCancellationReason.other,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}

/// Adapter mínimo sin dependencias externas: captura la request real
/// que construye el repositorio (path/método/body) y responde con un
/// JSON sintético, sin tocar la red.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Map<String, dynamic>? lastData;
  int statusCode = 200;

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

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(const {})));

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
