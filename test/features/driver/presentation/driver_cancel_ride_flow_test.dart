import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/presentation/driver_cancel_ride_flow.dart';

void main() {
  group('driverCancelDetailValidationError', () {
    test('vacío es válido (el campo es opcional)', () {
      expect(driverCancelDetailValidationError(''), isNull);
    });

    test('solo espacios cuenta como vacío', () {
      expect(driverCancelDetailValidationError('    '), isNull);
    });

    test('1 a 4 caracteres reales es inválido', () {
      expect(driverCancelDetailValidationError('abc'), isNotNull);
      expect(driverCancelDetailValidationError('abcd'), isNotNull);
    });

    test('exactamente 5 caracteres es válido (mínimo real de Backend)', () {
      expect(driverCancelDetailValidationError('abcde'), isNull);
    });

    test('300 caracteres (máximo defensivo del cliente) es válido', () {
      expect(driverCancelDetailValidationError('a' * 300), isNull);
    });
  });
}
