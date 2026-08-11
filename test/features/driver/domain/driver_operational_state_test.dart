import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/domain/driver_operational_state.dart';

void main() {
  group('DriverOperationalState.fromJson', () {
    test('parsea el objeto completo con timestamps', () {
      final state = DriverOperationalState.fromJson({
        'id': 'state-1',
        'driverProfileId': 'driver-1',
        'status': 'AVAILABLE',
        'connectedAt': '2026-08-10T10:00:00.000Z',
        'disconnectedAt': null,
        'lastSeenAt': '2026-08-10T10:05:00.000Z',
        'createdAt': '2026-08-01T00:00:00.000Z',
        'updatedAt': '2026-08-10T10:05:00.000Z',
      });

      expect(state.status, DriverOperationalStatus.available);
      expect(state.rawStatus, 'AVAILABLE');
      expect(state.id, 'state-1');
      expect(state.driverProfileId, 'driver-1');
      expect(state.connectedAt, DateTime.parse('2026-08-10T10:00:00.000Z'));
      expect(state.disconnectedAt, isNull);
      expect(state.lastSeenAt, DateTime.parse('2026-08-10T10:05:00.000Z'));
      expect(state.createdAt, DateTime.parse('2026-08-01T00:00:00.000Z'));
      expect(state.updatedAt, DateTime.parse('2026-08-10T10:05:00.000Z'));
    });

    test('mapea OFFLINE y BUSY', () {
      expect(
        DriverOperationalState.fromJson({'status': 'OFFLINE'}).status,
        DriverOperationalStatus.offline,
      );
      expect(
        DriverOperationalState.fromJson({'status': 'BUSY'}).status,
        DriverOperationalStatus.busy,
      );
    });

    test('status desconocido no rompe el parsing y conserva el raw', () {
      final state = DriverOperationalState.fromJson({'status': 'WEIRD'});

      expect(state.status, DriverOperationalStatus.unknown);
      expect(state.rawStatus, 'WEIRD');
    });

    test('fechas vacías o inválidas quedan null en vez de lanzar', () {
      final state = DriverOperationalState.fromJson({
        'status': 'AVAILABLE',
        'connectedAt': '',
        'lastSeenAt': 'no-es-fecha',
      });

      expect(state.connectedAt, isNull);
      expect(state.lastSeenAt, isNull);
    });
  });

  test('fromStatusOnly solo conoce el status', () {
    final state = DriverOperationalState.fromStatusOnly('BUSY');

    expect(state.status, DriverOperationalStatus.busy);
    expect(state.connectedAt, isNull);
    expect(state.id, isNull);
  });

  group('onlineDurationAt', () {
    test('null cuando no hay connectedAt', () {
      const state = DriverOperationalState(
        status: DriverOperationalStatus.available,
      );

      expect(state.onlineDurationAt(DateTime.utc(2026)), isNull);
    });

    test('null cuando el status es OFFLINE aunque haya connectedAt', () {
      final state = DriverOperationalState(
        status: DriverOperationalStatus.offline,
        connectedAt: DateTime.utc(2026, 1, 1, 10),
      );

      expect(state.onlineDurationAt(DateTime.utc(2026, 1, 1, 10, 30)), isNull);
    });

    test('calcula la duración cuando AVAILABLE y connectedAt existen', () {
      final state = DriverOperationalState(
        status: DriverOperationalStatus.available,
        connectedAt: DateTime.utc(2026, 1, 1, 10),
      );

      expect(
        state.onlineDurationAt(DateTime.utc(2026, 1, 1, 10, 30)),
        const Duration(minutes: 30),
      );
    });

    test('también calcula la duración en BUSY (continuidad de sesión)', () {
      final state = DriverOperationalState(
        status: DriverOperationalStatus.busy,
        connectedAt: DateTime.utc(2026, 1, 1, 10),
      );

      expect(
        state.onlineDurationAt(DateTime.utc(2026, 1, 1, 10, 15)),
        const Duration(minutes: 15),
      );
    });
  });
}
