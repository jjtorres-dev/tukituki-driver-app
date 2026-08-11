import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/domain/driver_daily_stats.dart';

void main() {
  group('DriverDailyStats.fromJson', () {
    test('parsea el contrato completo', () {
      final stats = DriverDailyStats.fromJson({
        'businessDate': '2026-08-10',
        'timezone': 'America/Lima',
        'completedRides': 5,
        'grossAmount': '18.50',
        'currency': 'PEN',
        'asOf': '2026-08-10T15:00:00.000Z',
      });

      expect(stats.businessDate, '2026-08-10');
      expect(stats.timezone, 'America/Lima');
      expect(stats.completedRides, 5);
      expect(stats.grossAmount, '18.50');
      expect(stats.grossAmount, isA<String>());
      expect(stats.currency, 'PEN');
      expect(stats.asOf, DateTime.parse('2026-08-10T15:00:00.000Z'));
    });

    test(
      'cero viajes y "0.00" se conservan tal cual, sin convertir a double',
      () {
        final stats = DriverDailyStats.fromJson({
          'businessDate': '2026-08-10',
          'timezone': 'America/Lima',
          'completedRides': 0,
          'grossAmount': '0.00',
          'currency': 'PEN',
          'asOf': '2026-08-10T00:00:00.000Z',
        });

        expect(stats.completedRides, 0);
        expect(stats.grossAmount, '0.00');
      },
    );

    test('campos ausentes usan valores por defecto seguros', () {
      final stats = DriverDailyStats.fromJson(const {});

      expect(stats.businessDate, '');
      expect(stats.timezone, 'America/Lima');
      expect(stats.completedRides, 0);
      expect(stats.grossAmount, '0.00');
      expect(stats.currency, 'PEN');
      expect(stats.asOf, isNull);
    });

    test('completedRides numérico distinto de int también se parsea', () {
      final stats = DriverDailyStats.fromJson({
        'businessDate': '2026-08-10',
        'timezone': 'America/Lima',
        'completedRides': 3.0,
        'grossAmount': '9.90',
        'currency': 'PEN',
        'asOf': null,
      });

      expect(stats.completedRides, 3);
    });
  });
}
