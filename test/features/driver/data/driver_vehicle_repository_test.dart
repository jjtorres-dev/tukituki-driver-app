import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/data/driver_vehicle_repository.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';

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

Map<String, dynamic> _vehicleJson() {
  return {
    'id': 'vehicle-1',
    'driverProfileId': 'profile-1',
    'plate': '1234-AB',
    'brand': 'Bajaj',
    'model': 'RE 4S',
    'year': 2024,
    'color': 'Azul',
    'engineNumber': null,
    'chassisNumber': null,
    'ownership': 'OWNED',
    'vehicleType': 'MOTOTAXI',
    'status': 'DRAFT',
    'rejectionReason': null,
  };
}

void main() {
  group('DriverVehicleRepository.createVehicle', () {
    test('envía exactamente plate/brand/model/year/color/ownership, sin '
        'vehicleType/engineNumber/chassisNumber/driverProfileId', () async {
      final adapter = _RecordingAdapter(201, _vehicleJson());
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverVehicleRepository(dio);

      final vehicle = await repository.createVehicle(
        plate: '1234-AB',
        brand: 'Bajaj',
        model: 'RE 4S',
        year: 2024,
        color: 'Azul',
        ownership: VehicleOwnership.owned,
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(adapter.lastRequest!.path, 'drivers/me/vehicle');
      expect(adapter.lastRequest!.method, 'POST');
      expect(body['plate'], '1234-AB');
      expect(body['brand'], 'Bajaj');
      expect(body['model'], 'RE 4S');
      expect(body['year'], 2024);
      expect(body['color'], 'Azul');
      expect(body['ownership'], 'OWNED');
      expect(body.containsKey('vehicleType'), isFalse);
      expect(body.containsKey('engineNumber'), isFalse);
      expect(body.containsKey('chassisNumber'), isFalse);
      expect(body.containsKey('driverProfileId'), isFalse);
      expect(vehicle.plate, '1234-AB');
      expect(vehicle.ownership, VehicleOwnership.owned);
    });

    test('envía RENTED tal cual', () async {
      final adapter = _RecordingAdapter(201, _vehicleJson());
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverVehicleRepository(dio);

      await repository.createVehicle(
        plate: '1234-AB',
        brand: 'Bajaj',
        model: 'RE 4S',
        year: 2024,
        color: 'Azul',
        ownership: VehicleOwnership.rented,
      );

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(body['ownership'], 'RENTED');
    });

    test('propaga 409 (placa/vehículo duplicado) sin envolverlo', () async {
      final adapter = _RecordingAdapter(409, {
        'message': 'La placa ya está registrada',
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverVehicleRepository(dio);

      await expectLater(
        repository.createVehicle(
          plate: '1234-AB',
          brand: 'Bajaj',
          model: 'RE 4S',
          year: 2024,
          color: 'Azul',
          ownership: VehicleOwnership.owned,
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('DriverVehicleRepository.updateVehicle', () {
    test('solo envía los campos informados', () async {
      final adapter = _RecordingAdapter(200, _vehicleJson());
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverVehicleRepository(dio);

      await repository.updateVehicle(plate: '5678-CD');

      final body = adapter.lastRequest!.data as Map<String, dynamic>;

      expect(adapter.lastRequest!.method, 'PATCH');
      expect(body['plate'], '5678-CD');
      expect(body.containsKey('brand'), isFalse);
      expect(body.containsKey('ownership'), isFalse);
    });

    test('propaga error sin envolverlo', () async {
      final adapter = _RecordingAdapter(400, {'message': 'boom'});
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = DriverVehicleRepository(dio);

      await expectLater(
        repository.updateVehicle(color: 'Rojo'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
