import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/core/router/route_not_found_screen.dart';

/// Cubre la red de seguridad del router (`errorBuilder` en
/// `app_router.dart`): ante una ruta que go_router no resuelve, el
/// usuario ve una pantalla con salida real y nunca queda atrapado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/splash',
      errorBuilder: (context, state) => const RouteNotFoundScreen(),
      routes: [
        GoRoute(
          path: '/splash',
          builder: (context, state) =>
              const Scaffold(body: Text('SPLASH_ROUTE')),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Scaffold(body: Text('HOME_ROUTE')),
        ),
      ],
    );
  }

  testWidgets(
    'una ruta inexistente muestra la pantalla de fallback, no un crash',
    (tester) async {
      final router = buildRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();

      router.go('/ruta-que-no-existe');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Pantalla no encontrada'), findsOneWidget);
      expect(
        find.byKey(const Key('route-not-found-home-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('el botón "Volver al inicio" navega a /splash', (tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/otra-ruta-invalida');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('route-not-found-home-button')));
    await tester.pumpAndSettle();

    expect(find.text('SPLASH_ROUTE'), findsOneWidget);
  });
}
