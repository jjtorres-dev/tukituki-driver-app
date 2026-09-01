import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/secure_storage.dart';

final deviceIdStoreProvider = Provider<DeviceIdStore>((ref) {
  return DeviceIdStore(ref.watch(secureStorageProvider));
});

/// `DRIVER-PUSH-R1`: genera y persiste un identificador estable **por
/// instalación** (no por cuenta) para `POST /me/devices`.
///
/// Ver `StorageKeys.deviceId`: el valor sobrevive logout / cambio de
/// cuenta / reinicio de la app, y nunca se borra en `clearSession()`.
class DeviceIdStore {
  DeviceIdStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _uuid = Uuid();

  /// Devuelve el `deviceId` persistido; si todavía no existe, genera un
  /// UUID v4 nuevo y lo persiste.
  ///
  /// Si la escritura en el almacenamiento seguro falla (algunos
  /// dispositivos/ROMs), igualmente devuelve el valor recién generado
  /// sin lanzar: el registro de push de esta corrida usa ese valor y
  /// el próximo arranque reintenta la persistencia.
  Future<String> getOrCreate() async {
    final existing = await _storage.read(key: StorageKeys.deviceId);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = _uuid.v4();

    try {
      await _storage.write(key: StorageKeys.deviceId, value: generated);
    } catch (error) {
      debugPrint('DRIVER PUSH - no se pudo persistir el device_id: $error');
    }

    return generated;
  }
}
