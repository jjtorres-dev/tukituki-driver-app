import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:driver/features/driver/presentation/driver_counter_offer_dialog.dart';

void main() {
  group('validateDriverCounterOfferInput', () {
    test('acepta importes menores, iguales y mayores que la oferta', () {
      expect(validateDriverCounterOfferInput('6.00').proposedFare, '6.00');
      expect(validateDriverCounterOfferInput('7.00').proposedFare, '7.00');
      expect(validateDriverCounterOfferInput('8.00').proposedFare, '8.00');
    });

    test('acepta coma decimal y normaliza a dos decimales', () {
      expect(validateDriverCounterOfferInput('6,5').proposedFare, '6.50');
    });

    test('rechaza valores no positivos o no finitos', () {
      for (final input in ['0', '-1', 'NaN', 'Infinity', '-Infinity']) {
        expect(
          validateDriverCounterOfferInput(input).isValid,
          isFalse,
          reason: input,
        );
      }
    });

    test('rechaza el exceso de rango o decimales', () {
      expect(validateDriverCounterOfferInput('10000').isValid, isFalse);
      expect(validateDriverCounterOfferInput('7.123').isValid, isFalse);
      expect(validateDriverCounterOfferInput('9999.99').isValid, isTrue);
    });
  });

  test('409 produce un mensaje controlado y entendible', () {
    expect(
      driverCounterOfferErrorMessage(statusCode: 409, hasResponse: true),
      'Esta solicitud ya venció o ya no está disponible.',
    );
  });

  testWidgets('se puede abrir y cancelar sin excepciones', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _DialogHarness()));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Resultado: cancelado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('envía una contraoferta válida y desmonta el controlador', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _DialogHarness()));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6,00');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Resultado: 6.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('doble tap solo devuelve un resultado', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _DialogHarness()));

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8.00');

    await tester.tap(find.text('Enviar'));
    await tester.tap(find.text('Enviar'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Resultado: 8.00'), findsOneWidget);
    expect(find.text('Resultados: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DialogHarness extends StatefulWidget {
  const _DialogHarness();

  @override
  State<_DialogHarness> createState() => _DialogHarnessState();
}

class _DialogHarnessState extends State<_DialogHarness> {
  final List<String?> _results = [];

  Future<void> _open() async {
    final result = await showDriverCounterOfferDialog(
      context: context,
      passengerOfferFare: '7.00',
    );

    if (!mounted) return;

    setState(() {
      _results.add(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _results.isEmpty
        ? 'sin resultado'
        : (_results.last ?? 'cancelado');

    return Scaffold(
      body: Column(
        children: [
          FilledButton(onPressed: _open, child: const Text('Abrir')),
          Text('Resultado: $result'),
          Text('Resultados: ${_results.length}'),
        ],
      ),
    );
  }
}
