import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/notifications/data/device_id_store.dart';
import 'package:driver/features/notifications/data/push_messaging_service.dart';
import 'package:driver/features/notifications/data/push_registration_coordinator.dart';
import 'package:driver/features/notifications/data/push_registration_repository.dart';

class _FakePushMessagingService implements PushMessagingService {
  String? token = 'token-1';
  bool tokenThrows = false;
  bool permissionThrows = false;

  int requestPermissionCalls = 0;
  int getTokenCalls = 0;

  final StreamController<String> tokenRefreshController =
      StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls += 1;
    if (permissionThrows) {
      throw Exception('permiso falló en el test');
    }
    return true;
  }

  @override
  Future<String?> getToken() async {
    getTokenCalls += 1;
    if (tokenThrows) {
      throw Exception('getToken falló en el test');
    }
    return token;
  }

  @override
  Stream<String> get onTokenRefresh => tokenRefreshController.stream;
}

class _FakeDeviceIdStore extends DeviceIdStore {
  _FakeDeviceIdStore(this._value) : super(const FlutterSecureStorage());

  final String _value;
  int calls = 0;

  @override
  Future<String> getOrCreate() async {
    calls += 1;
    return _value;
  }
}

class _RegisterCall {
  _RegisterCall(this.pushToken, this.deviceId, this.appVersion);

  final String pushToken;
  final String deviceId;
  final String? appVersion;
}

class _SpyPushRegistrationRepository extends PushRegistrationRepository {
  _SpyPushRegistrationRepository() : super(Dio());

  bool throwOnCall = false;
  final List<_RegisterCall> calls = [];

  @override
  Future<void> registerDevice({
    required String pushToken,
    required String deviceId,
    String? appVersion,
  }) async {
    calls.add(_RegisterCall(pushToken, deviceId, appVersion));
    if (throwOnCall) {
      throw DioException(requestOptions: RequestOptions(path: 'me/devices'));
    }
  }
}

void main() {
  late _FakePushMessagingService messaging;
  late _FakeDeviceIdStore deviceIdStore;
  late _SpyPushRegistrationRepository repository;

  PushRegistrationCoordinator build() {
    final coordinator = PushRegistrationCoordinator(
      messaging,
      deviceIdStore,
      repository,
    );
    addTearDown(coordinator.dispose);
    return coordinator;
  }

  setUp(() {
    messaging = _FakePushMessagingService();
    deviceIdStore = _FakeDeviceIdStore('device-1');
    repository = _SpyPushRegistrationRepository();
    addTearDown(messaging.tokenRefreshController.close);
  });

  test('happy path: registra una vez con el token y el deviceId correctos', () async {
    await build().syncDeviceRegistration();

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single.pushToken, 'token-1');
    expect(repository.calls.single.deviceId, 'device-1');
    expect(repository.calls.single.appVersion, isNull);
  });

  test('token null → no llama al repositorio y no lanza', () async {
    messaging.token = null;

    await build().syncDeviceRegistration();

    expect(repository.calls, isEmpty);
  });

  test('getToken() que lanza → se traga, no llama al repositorio', () async {
    messaging.tokenThrows = true;

    await build().syncDeviceRegistration();

    expect(messaging.getTokenCalls, 1);
    expect(repository.calls, isEmpty);
  });

  test('el repositorio que lanza → syncDeviceRegistration() completa igual', () async {
    repository.throwOnCall = true;

    await build().syncDeviceRegistration();

    expect(repository.calls, hasLength(1));
  });

  test('requestPermission() que lanza → se llega igual a getToken() y al registro', () async {
    messaging.permissionThrows = true;

    await build().syncDeviceRegistration();

    expect(messaging.requestPermissionCalls, 1);
    expect(messaging.getTokenCalls, 1);
    expect(repository.calls, hasLength(1));
  });

  test('onTokenRefresh emite un token nuevo → re-registra con ese token y el mismo deviceId', () async {
    await build().syncDeviceRegistration();
    expect(repository.calls, hasLength(1));

    messaging.tokenRefreshController.add('token-2');
    await pumpEventQueue();

    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.pushToken, 'token-2');
    expect(repository.calls.last.deviceId, 'device-1');
  });

  test('dos llamadas a syncDeviceRegistration() → una sola suscripción a onTokenRefresh', () async {
    final coordinator = build();

    await coordinator.syncDeviceRegistration();
    await coordinator.syncDeviceRegistration();
    expect(repository.calls, hasLength(2));

    messaging.tokenRefreshController.add('token-2');
    await pumpEventQueue();

    // 2 registros de los sync + 1 del único handler de refresh = 3.
    // Con doble suscripción serían 4.
    expect(repository.calls, hasLength(3));
  });

  test('dispose() cancela la suscripción: un emit posterior no re-registra', () async {
    final coordinator = build();
    await coordinator.syncDeviceRegistration();

    coordinator.dispose();

    messaging.tokenRefreshController.add('token-2');
    await pumpEventQueue();

    expect(repository.calls, hasLength(1));
  });
}
