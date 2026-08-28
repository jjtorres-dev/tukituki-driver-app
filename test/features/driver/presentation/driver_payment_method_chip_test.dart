import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/presentation/driver_payment_method_chip.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? method) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DriverPaymentMethodChip(method: method)),
      ),
    );
  }

  group('DriverPaymentMethodChip', () {
    testWidgets('mapea los métodos conocidos a etiquetas en español', (
      tester,
    ) async {
      for (final entry in const {
        'CASH': 'Efectivo',
        'YAPE': 'Yape',
        'PLIN': 'Plin',
        'CARD': 'Tarjeta',
      }.entries) {
        await pump(tester, entry.key);

        expect(find.text('Pago: ${entry.value}'), findsOneWidget);
      }
    });

    testWidgets('un método desconocido se muestra tal cual, nunca se oculta', (
      tester,
    ) async {
      await pump(tester, 'TRANSFER');

      expect(find.text('Pago: TRANSFER'), findsOneWidget);
    });

    testWidgets('método null o vacío no renderiza nada', (tester) async {
      await pump(tester, null);
      expect(find.textContaining('Pago:'), findsNothing);

      await pump(tester, '   ');
      expect(find.textContaining('Pago:'), findsNothing);
    });

    test('hasMethod distingue presencia real de vacío/nulo', () {
      expect(DriverPaymentMethodChip.hasMethod('YAPE'), isTrue);
      expect(DriverPaymentMethodChip.hasMethod('  '), isFalse);
      expect(DriverPaymentMethodChip.hasMethod(null), isFalse);
    });
  });
}
