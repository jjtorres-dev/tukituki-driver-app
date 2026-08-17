import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:driver/app.dart';

void main() {
  testWidgets('TukiTuki Driver inicia correctamente', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: TukiTukiDriverApp()));

    expect(find.text('TukiTuki'), findsOneWidget);
    expect(find.text('Conductor'), findsOneWidget);
  });

  group('Localización (DRIVER-ONBOARDING-R3.4.2)', () {
    testWidgets('A. la app declara es_PE como locale, con es como fallback', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: TukiTukiDriverApp()));

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));

      expect(materialApp.locale, const Locale('es', 'PE'));
      expect(materialApp.supportedLocales, contains(const Locale('es', 'PE')));
      expect(materialApp.supportedLocales, contains(const Locale('es')));
    });

    testWidgets(
      'C. las delegates oficiales de Material/Widgets/Cupertino están '
      'declaradas (son las que traducen showDatePicker)',
      (tester) async {
        await tester.pumpWidget(
          const ProviderScope(child: TukiTukiDriverApp()),
        );

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        final delegates = materialApp.localizationsDelegates!.toList();

        expect(delegates, contains(GlobalMaterialLocalizations.delegate));
        expect(delegates, contains(GlobalWidgetsLocalizations.delegate));
        expect(delegates, contains(GlobalCupertinoLocalizations.delegate));
      },
    );

    testWidgets('el locale efectivo resuelto por Flutter es español', (
      tester,
    ) async {
      await tester.pumpWidget(const ProviderScope(child: TukiTukiDriverApp()));

      final locale = Localizations.localeOf(
        tester.element(find.text('TukiTuki')),
      );

      expect(locale.languageCode, 'es');
    });
  });
}
