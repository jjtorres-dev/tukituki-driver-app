import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_money.dart';

void main() {
  group('parseAmountToCents', () {
    test('parsea decimales de 2 dígitos', () {
      expect(parseAmountToCents('10.50'), 1050);
    });

    test('parsea enteros sin decimales', () {
      expect(parseAmountToCents('10'), 1000);
    });

    test('parsea un solo decimal (rellena con 0)', () {
      expect(parseAmountToCents('10.5'), 1050);
    });

    test('acepta coma como separador ya normalizado por el llamador', () {
      // El llamador (pantalla) normaliza coma->punto antes de invocar.
      expect(parseAmountToCents('10.5'), 1050);
    });

    test('retorna null para vacío', () {
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('   '), isNull);
    });

    test('retorna null para letras', () {
      expect(parseAmountToCents('abc'), isNull);
    });

    test('retorna null para negativos', () {
      expect(parseAmountToCents('-10.50'), isNull);
    });

    test('retorna null para más de 2 decimales', () {
      expect(parseAmountToCents('10.505'), isNull);
    });
  });

  group('formatCentsAsDecimal', () {
    test('formatea centavos a 2 decimales', () {
      expect(formatCentsAsDecimal(1050), '10.50');
    });

    test('formatea cero como 0.00', () {
      expect(formatCentsAsDecimal(0), '0.00');
    });

    test('formatea montos menores a un sol con cero a la izquierda', () {
      expect(formatCentsAsDecimal(50), '0.50');
    });
  });

  group('quickAmountsForDueCents', () {
    test('total 5 -> 5/10/20', () {
      expect(
        quickAmountsForDueCents(500),
        [500, 1000, 2000],
      );
    });

    test('total 17 -> 17/20/50', () {
      expect(
        quickAmountsForDueCents(1700),
        [1700, 2000, 5000],
      );
    });

    test('total 23 -> 23/50/100', () {
      expect(
        quickAmountsForDueCents(2300),
        [2300, 5000, 10000],
      );
    });

    test('total 99 -> 99/100/200', () {
      expect(
        quickAmountsForDueCents(9900),
        [9900, 10000, 20000],
      );
    });

    test('total superior a 500 usa múltiplos de 100 superiores', () {
      expect(
        quickAmountsForDueCents(65000),
        [65000, 70000, 80000],
      );
    });

    test('nunca duplica valores', () {
      final amounts = quickAmountsForDueCents(1700);
      expect(amounts.toSet().length, amounts.length);
    });
  });
}
