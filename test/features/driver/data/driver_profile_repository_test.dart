import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_profile_repository.dart';
import 'package:driver/features/driver/domain/driver_application.dart';

/// Adapter con guion, mismo patrón que el resto del repo: registra
/// el último request enviado para poder afirmar exactamente qué
/// body/headers viajaron, sin red real ni paquetes de mocking.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.statusCode, this.responseBody);

  final int statusCode;
  final Object? responseBody;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    return ResponseBody.fromString(
      responseBody == null ? '' : jsonEncode(responseBody),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _profileJson() {
  return {
    'id': 'profile-1',
    'userId': 'user-1',
    'firstName': 'Juan',
    'lastName': 'Torres',
    'status': 'DRAFT',
    'documentType': 'DNI',
    'documentNumber': '12345678',
    'birthDate': '1995-06-15',
    'email': null,
    'photoUrl': null,
  };
}

void main() {
  group('DriverProfileRepository.createProfile', () {
    test(
      'envía exactamente los campos del Paso 2, sin address/photoUrl',
      () async {
        final adapter = _RecordingAdapter(201, _profileJson());
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = DriverProfileRepository(dio);

        final application = await repository.createProfile(
          firstName: 'Juan',
          lastName: 'Torres',
          documentType: IdentityDocumentType.dni,
          documentNumber: '12345678',
          birthDate: '1995-06-15',
        );

        final body = adapter.lastRequest!.data as Map<String, dynamic>;

        expect(adapter.lastRequest!.path, 'drivers/me');
        expect(body['firstName'], 'Juan');
        expect(body['lastName'], 'Torres');
        expect(body['documentType'], 'DNI');
        expect(body['documentNumber'], '12345678');
        expect(body['birthDate'], '1995-06-15');
        expect(body.containsKey('address'), isFalse);
        expect(body.containsKey('photoUrl'), isFalse);
        expect(body.containsKey('email'), isFalse);
        expect(application.status, DriverApplicationStatus.draft);
      },
    );

    test('envía FOREIGNER_CARD (CE) tal cual', () async {
      final adapter = _RecordingAdapter(201, _profileJson());
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverProfileRepository(dio);

      await repository.createProfile(
        firstName: 'Juan',
        lastName: 'Torres',
        documentType: IdentityDocumentType.foreignerCard,
        documentNumber: 'AB1234567',
        birthDate: '1995-06-15',
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(body['documentType'], 'FOREIGNER_CARD');
    });

    test('incluye email solo cuando viene informado', () async {
      final adapter = _RecordingAdapter(201, _profileJson());
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverProfileRepository(dio);

      await repository.createProfile(
        firstName: 'Juan',
        lastName: 'Torres',
        documentType: IdentityDocumentType.dni,
        documentNumber: '12345678',
        birthDate: '1995-06-15',
        email: 'juan@example.com',
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(body['email'], 'juan@example.com');
    });

    test('propaga 409 sin envolverlo', () async {
      final adapter = _RecordingAdapter(409, {'message': 'Ya existe'});
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverProfileRepository(dio);

      await expectLater(
        repository.createProfile(
          firstName: 'Juan',
          lastName: 'Torres',
          documentType: IdentityDocumentType.dni,
          documentNumber: '12345678',
          birthDate: '1995-06-15',
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}
