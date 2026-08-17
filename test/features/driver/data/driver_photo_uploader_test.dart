import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_photo_uploader.dart';

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;
  Uint8List? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;

    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      lastBody = Uint8List.fromList(chunks);
    }

    return ResponseBody.fromString('', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DriverPhotoUploader.upload', () {
    test(
      'hace PUT a la uploadUrl con Content-Type exacto, SIN Authorization',
      () async {
        final adapter = _RecordingAdapter();
        final uploader = DriverPhotoUploader(
          dioFactory: () => Dio()..httpClientAdapter = adapter,
        );

        final bytes = Uint8List.fromList([1, 2, 3, 4]);

        await uploader.upload(
          uploadUrl: 'https://bucket.example.com/objectKey?X-Signature=abc',
          contentType: 'image/jpeg',
          bytes: bytes,
        );

        final request = adapter.lastRequest!;

        expect(request.method, 'PUT');
        expect(
          request.uri.toString(),
          'https://bucket.example.com/objectKey?X-Signature=abc',
        );
        expect(request.headers['Content-Type'], 'image/jpeg');
        expect(request.headers.containsKey('Authorization'), isFalse);
        expect(lastBodyBytesEqual(adapter.lastBody, bytes), isTrue);
      },
    );

    test('cada llamada usa un Dio nuevo del factory (aislado)', () async {
      var factoryCalls = 0;
      final adapter = _RecordingAdapter();

      final uploader = DriverPhotoUploader(
        dioFactory: () {
          factoryCalls += 1;
          return Dio()..httpClientAdapter = adapter;
        },
      );

      await uploader.upload(
        uploadUrl: 'https://bucket.example.com/a',
        contentType: 'image/png',
        bytes: Uint8List.fromList([1]),
      );
      await uploader.upload(
        uploadUrl: 'https://bucket.example.com/b',
        contentType: 'image/png',
        bytes: Uint8List.fromList([2]),
      );

      expect(factoryCalls, 2);
    });

    test('propaga errores del PUT sin envolverlos', () async {
      final failingAdapter = _FailingAdapter();
      final uploader = DriverPhotoUploader(
        dioFactory: () => Dio()..httpClientAdapter = failingAdapter,
      );

      await expectLater(
        uploader.upload(
          uploadUrl: 'https://bucket.example.com/objectKey',
          contentType: 'image/jpeg',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
        throwsA(isA<DioException>()),
      );
    });
  });
}

bool lastBodyBytesEqual(Uint8List? actual, Uint8List expected) {
  if (actual == null || actual.length != expected.length) {
    return false;
  }

  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      return false;
    }
  }

  return true;
}

class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString('{"message":"boom"}', 500);
  }

  @override
  void close({bool force = false}) {}
}
