import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_document_repository.dart';

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final Map<String, (int, Object?)> responses;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    final scripted = responses[options.path];

    if (scripted == null) {
      throw StateError('Sin respuesta configurada para ${options.path}');
    }

    final (statusCode, data) = scripted;

    return ResponseBody.fromString(
      data == null ? '' : jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _documentJson({
  String id = 'document-1',
  String type = 'DRIVER_LICENSE',
  String status = 'DRAFT',
  String? documentNumber = 'ABC123',
  String? issuedAt = '2024-01-01',
  String? expiresAt = '2030-01-01',
}) {
  return {
    'id': id,
    'driverProfileId': 'profile-1',
    'type': type,
    'status': status,
    'fileUrl': null,
    'fileObjectKey': 'drivers/profile-1/documents/license.jpg',
    'documentNumber': documentNumber,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'rejectionReason': null,
  };
}

void main() {
  group('DriverDocumentRepository.updateDocumentMetadata', () {
    test('PATCH drivers/me/documents/:id con documentNumber/issuedAt/expiresAt '
        'y parsea la respuesta', () async {
      final adapter = _ScriptedAdapter({
        'drivers/me/documents/document-1': (200, _documentJson()),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverDocumentRepository(dio);

      final result = await repository.updateDocumentMetadata(
        documentId: 'document-1',
        documentNumber: 'ABC123',
        issuedAt: '2024-01-01',
        expiresAt: '2030-01-01',
      );

      final request = adapter.lastRequest!;
      final body = request.data as Map<String, dynamic>;

      expect(request.method, 'PATCH');
      expect(request.path, 'drivers/me/documents/document-1');
      expect(body['documentNumber'], 'ABC123');
      expect(body['issuedAt'], '2024-01-01');
      expect(body['expiresAt'], '2030-01-01');
      expect(result.id, 'document-1');
      expect(result.documentNumber, 'ABC123');
    });

    test(
      'sin expiresAt (VEHICLE_REGISTRATION) NO envía la clave expiresAt',
      () async {
        final adapter = _ScriptedAdapter({
          'drivers/me/documents/document-2': (
            200,
            _documentJson(
              id: 'document-2',
              type: 'VEHICLE_REGISTRATION',
              expiresAt: null,
            ),
          ),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = DriverDocumentRepository(dio);

        await repository.updateDocumentMetadata(
          documentId: 'document-2',
          documentNumber: 'XYZ999',
          issuedAt: '2024-01-01',
        );

        final body = adapter.lastRequest!.data as Map<String, dynamic>;

        expect(body.containsKey('expiresAt'), isFalse);
        expect(body['documentNumber'], 'XYZ999');
        expect(body['issuedAt'], '2024-01-01');
      },
    );

    test(
      'propaga 400 (documentNumber/fecha inválida) sin envolverlo',
      () async {
        final adapter = _ScriptedAdapter({
          'drivers/me/documents/document-1': (400, {'message': 'inválido'}),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = DriverDocumentRepository(dio);

        await expectLater(
          repository.updateDocumentMetadata(
            documentId: 'document-1',
            documentNumber: 'ABC123',
            issuedAt: '2024-01-01',
          ),
          throwsA(isA<DioException>()),
        );
      },
    );

    test(
      'propaga 404 (documento inexistente) sin convertirlo en null',
      () async {
        final adapter = _ScriptedAdapter({
          'drivers/me/documents/document-404': (404, {'message': 'No existe'}),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = DriverDocumentRepository(dio);

        await expectLater(
          repository.updateDocumentMetadata(
            documentId: 'document-404',
            documentNumber: 'ABC123',
            issuedAt: '2024-01-01',
          ),
          throwsA(isA<DioException>()),
        );
      },
    );
  });
}
