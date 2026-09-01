import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/notifications/data/push_registration_repository.dart';

/// Adapter que captura el `RequestOptions` de la única llamada y
/// responde `201` fijo — sin red real ni paquetes de mocking, igual
/// que `_FixedResponseAdapter` en `driver_offers_repository_test.dart`.
class _CapturingAdapter implements HttpClientAdapter {
  RequestOptions? captured;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured = options;

    return ResponseBody.fromString(
      '{}',
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Adapter que siempre falla con un `DioException` de respuesta.
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(requestOptions: options, statusCode: 500),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('PushRegistrationRepository.registerDevice', () {
    test('emite POST me/devices con platform/pushToken/deviceId y SIN appVersion cuando es null', () async {
      final adapter = _CapturingAdapter();
      final repository = PushRegistrationRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.registerDevice(
        pushToken: 'token-abc',
        deviceId: 'device-1',
      );

      expect(adapter.captured, isNotNull);
      expect(adapter.captured!.method, 'POST');
      expect(adapter.captured!.path, 'me/devices');
      expect(adapter.captured!.data, {
        'platform': 'ANDROID',
        'pushToken': 'token-abc',
        'deviceId': 'device-1',
      });
      expect(
        (adapter.captured!.data as Map).containsKey('appVersion'),
        isFalse,
      );
    });

    test('incluye appVersion cuando se pasa un valor no vacío', () async {
      final adapter = _CapturingAdapter();
      final repository = PushRegistrationRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.registerDevice(
        pushToken: 'token-abc',
        deviceId: 'device-1',
        appVersion: '1.0.0+1',
      );

      expect(adapter.captured!.data, {
        'platform': 'ANDROID',
        'pushToken': 'token-abc',
        'deviceId': 'device-1',
        'appVersion': '1.0.0+1',
      });
    });

    test('un appVersion vacío no agrega la clave', () async {
      final adapter = _CapturingAdapter();
      final repository = PushRegistrationRepository(
        Dio()..httpClientAdapter = adapter,
      );

      await repository.registerDevice(
        pushToken: 'token-abc',
        deviceId: 'device-1',
        appVersion: '',
      );

      expect(
        (adapter.captured!.data as Map).containsKey('appVersion'),
        isFalse,
      );
    });

    test('deja propagar el DioException (no lo traga)', () async {
      final repository = PushRegistrationRepository(
        Dio()..httpClientAdapter = _FailingAdapter(),
      );

      expect(
        () => repository.registerDevice(
          pushToken: 'token-abc',
          deviceId: 'device-1',
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
