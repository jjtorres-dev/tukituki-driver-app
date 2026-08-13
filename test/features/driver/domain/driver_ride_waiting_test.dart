import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_ride_waiting.dart';

Map<String, dynamic> _baseJson({
  Object? rideId = 'ride-1',
  Object? waitingStartedAt = '2026-08-10T12:00:00.000Z',
  Object? noShowAvailableAt = '2026-08-10T12:05:00.000Z',
  Object? requiredWaitingSeconds = 300,
  Object? elapsedWaitingSeconds = 60,
  Object? remainingWaitingSeconds = 240,
  Object? canReportNoShow = false,
  Object? startDistanceMeters = const _Absent(),
}) {
  final json = <String, dynamic>{
    'rideId': rideId,
    'waitingStartedAt': waitingStartedAt,
    'noShowAvailableAt': noShowAvailableAt,
    'requiredWaitingSeconds': requiredWaitingSeconds,
    'elapsedWaitingSeconds': elapsedWaitingSeconds,
    'remainingWaitingSeconds': remainingWaitingSeconds,
    'canReportNoShow': canReportNoShow,
  };

  if (startDistanceMeters is! _Absent) {
    json['startDistanceMeters'] = startDistanceMeters;
  }

  return json;
}

class _Absent {
  const _Absent();
}

void main() {
  group('DriverRideWaiting.fromJson', () {
    test('A: parsea un RideWaiting real completo', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(startDistanceMeters: 35),
      );

      expect(waiting.rideId, 'ride-1');
      expect(waiting.requiredWaitingSeconds, 300);
      expect(waiting.elapsedWaitingSeconds, 60);
      expect(waiting.remainingWaitingSeconds, 240);
      expect(waiting.startDistanceMeters, 35);
    });

    test('B: canReportNoShow=false se preserva', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(canReportNoShow: false),
      );

      expect(waiting.canReportNoShow, isFalse);
    });

    test('C: canReportNoShow=true se preserva', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(canReportNoShow: true),
      );

      expect(waiting.canReportNoShow, isTrue);
    });

    test('C2: canReportNoShow con valor no-booleano se interpreta como false '
        '(dirección segura, nunca habilita por error)', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(canReportNoShow: 'true'),
      );

      expect(waiting.canReportNoShow, isFalse);
    });

    test('D: remainingWaitingSeconds real se parsea', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(remainingWaitingSeconds: 137),
      );

      expect(waiting.remainingWaitingSeconds, 137);
      expect(waiting.remainingSecondsForDisplay, 137);
    });

    test('D2: remainingWaitingSeconds negativo (drift) nunca se muestra '
        'negativo', () {
      final waiting = DriverRideWaiting.fromJson(
        _baseJson(remainingWaitingSeconds: -4),
      );

      expect(waiting.remainingWaitingSeconds, -4);
      expect(waiting.remainingSecondsForDisplay, 0);
    });

    test('E: waitingStartedAt/noShowAvailableAt reales se parsean', () {
      final waiting = DriverRideWaiting.fromJson(_baseJson());

      expect(
        waiting.waitingStartedAt,
        DateTime.parse('2026-08-10T12:00:00.000Z'),
      );
      expect(
        waiting.noShowAvailableAt,
        DateTime.parse('2026-08-10T12:05:00.000Z'),
      );
    });

    test('F: startDistanceMeters nullable se preserva como null si el '
        'contrato no lo envía', () {
      final json = _baseJson();

      final waiting = DriverRideWaiting.fromJson(json);

      expect(waiting.startDistanceMeters, isNull);
    });

    test('G: rideId ausente/corrupto lanza FormatException (parsing '
        'defensivo, sin inventar un estado válido)', () {
      expect(
        () => DriverRideWaiting.fromJson(_baseJson(rideId: null)),
        throwsFormatException,
      );

      expect(
        () => DriverRideWaiting.fromJson(_baseJson(rideId: 42)),
        throwsFormatException,
      );
    });

    test('H: fechas ausentes/corruptas lanzan FormatException', () {
      expect(
        () => DriverRideWaiting.fromJson(_baseJson(waitingStartedAt: null)),
        throwsFormatException,
      );

      expect(
        () => DriverRideWaiting.fromJson(
          _baseJson(noShowAvailableAt: 'no-es-una-fecha'),
        ),
        throwsFormatException,
      );
    });

    test('I: conteo de segundos ausente/corrupto lanza FormatException', () {
      expect(
        () =>
            DriverRideWaiting.fromJson(_baseJson(requiredWaitingSeconds: null)),
        throwsFormatException,
      );

      expect(
        () => DriverRideWaiting.fromJson(
          _baseJson(remainingWaitingSeconds: 'no-es-un-numero'),
        ),
        throwsFormatException,
      );
    });
  });
}
