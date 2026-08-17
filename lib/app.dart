import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/router/app_router.dart';

class TukiTukiDriverApp extends StatelessWidget {
  const TukiTukiDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TukiTuki Conductor',
      debugShowCheckedModeBanner: false,
      routerConfig: appRouter,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.amber,
        inputDecorationTheme: const InputDecorationTheme(filled: true),
      ),
      // TukiTuki está orientado a Perú: fuerza español (Flutter
      // resuelve internamente los recursos de Material vía el
      // bundle base "es", sin una variante "es_PE" propia — es el
      // comportamiento esperado, no un bug) en vez de caer al
      // inglés por defecto. Afecta widgets oficiales de Material
      // como `showDatePicker` (Paso 2 "Sobre ti"); no cambia ningún
      // formato de datos hacia Backend.
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
