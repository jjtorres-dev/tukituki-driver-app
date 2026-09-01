import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/core/storage/secure_storage.dart';
import 'package:driver/features/notifications/data/device_id_store.dart';

/// UUID v4 canónico (dígito de versión `4`, variante `8/9/a/b`).
final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  late Map<String, String> storageData;

  setUp(() {
    storageData = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      storageData,
    );
  });

  DeviceIdStore store() => DeviceIdStore(const FlutterSecureStorage());

  test('primera llamada genera un UUID v4 y lo persiste', () async {
    final id = await store().getOrCreate();

    expect(id, matches(_uuidV4));
    expect(storageData[StorageKeys.deviceId], id);
  });

  test('segunda llamada devuelve exactamente el mismo valor', () async {
    final s = store();

    final first = await s.getOrCreate();
    final second = await s.getOrCreate();

    expect(second, first);
  });

  test('una instancia nueva sobre el mismo storage lee el valor persistido', () async {
    final first = await store().getOrCreate();
    final second = await store().getOrCreate();

    expect(second, first);
    expect(second, matches(_uuidV4));
  });

  test('si la escritura del storage falla, igual devuelve un id usable sin lanzar', () async {
    FlutterSecureStoragePlatform.instance = _WriteFailingStoragePlatform(
      storageData,
    );

    final id = await store().getOrCreate();

    expect(id, matches(_uuidV4));
    // No se persistió (la escritura falló), pero no lanzó.
    expect(storageData.containsKey(StorageKeys.deviceId), isFalse);
  });
}

/// Igual que [TestFlutterSecureStoragePlatform] pero `write` siempre
/// lanza — simula un dispositivo/ROM donde el almacenamiento seguro
/// rechaza la escritura.
class _WriteFailingStoragePlatform extends TestFlutterSecureStoragePlatform {
  _WriteFailingStoragePlatform(super.data);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    throw Exception('escritura bloqueada en el test');
  }
}
