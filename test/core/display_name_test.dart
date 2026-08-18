import 'package:driver/core/display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('displayCompactName', () {
    test('nombre + apellido -> nombre + inicial del apellido', () {
      expect(displayCompactName('Mark', 'Landeo'), 'Mark L.');
    });

    test('apellido compuesto -> inicial del primer apellido (primer carácter)', () {
      expect(displayCompactName('María', 'Rodríguez López'), 'María R.');
    });

    test('recorta espacios en los extremos de ambos campos', () {
      expect(displayCompactName(' María ', ' Rodríguez López '), 'María R.');
    });

    test('sin apellido -> solo el nombre', () {
      expect(displayCompactName('Mark', null), 'Mark');
    });

    test('apellido vacío -> solo el nombre', () {
      expect(displayCompactName('Mark', ''), 'Mark');
    });

    test('apellido solo espacios -> solo el nombre', () {
      expect(displayCompactName('Mark', '   '), 'Mark');
    });

    test('ambos null -> cadena vacía, nunca "null"', () {
      final result = displayCompactName(null, null);

      expect(result, '');
      expect(result, isNot(contains('null')));
    });

    test('nombre vacío con apellido presente -> cadena vacía', () {
      expect(displayCompactName('', 'Landeo'), '');
    });

    test('nunca produce un "." suelto ni espacios dobles', () {
      final result = displayCompactName('Mark', 'Landeo');

      expect(result, isNot(startsWith('.')));
      expect(result, isNot(contains('  ')));
    });

    test('inicial siempre en mayúscula aunque el apellido venga en minúscula', () {
      expect(displayCompactName('Mark', 'landeo'), 'Mark L.');
    });
  });

  group('displayCompactNameFromInitial', () {
    test('nombre + inicial ya derivada -> se combinan tal cual', () {
      expect(displayCompactNameFromInitial('Mark', 'L.'), 'Mark L.');
    });

    test('recorta espacios en los extremos de ambos campos', () {
      expect(displayCompactNameFromInitial(' Mark ', ' L. '), 'Mark L.');
    });

    test('sin inicial -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Mark', null), 'Mark');
    });

    test('inicial vacía -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Mark', ''), 'Mark');
    });

    test('inicial solo espacios (legacy) -> solo el nombre', () {
      expect(displayCompactNameFromInitial('Mark', '   '), 'Mark');
    });

    test('ambos null -> cadena vacía, nunca "null"', () {
      final result = displayCompactNameFromInitial(null, null);

      expect(result, '');
      expect(result, isNot(contains('null')));
    });

    test('nombre vacío con inicial presente -> cadena vacía', () {
      expect(displayCompactNameFromInitial('', 'L.'), '');
    });

    test('nunca produce espacios dobles', () {
      final result = displayCompactNameFromInitial('Mark', 'L.');

      expect(result, isNot(contains('  ')));
    });
  });
}
