import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_start_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra el mensaje de foundation y los próximos pasos', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Completemos tu solicitud'), findsOneWidget);
    expect(find.textContaining('Tus documentos y Revisar'), findsOneWidget);
  });

  testWidgets('cerrar sesión desloguea y navega a login', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('onboarding-start-logout-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.logoutCalls, 1);
    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeAuthRepository? repository,
}) async {
  final router = GoRouter(
    initialLocation: '/onboarding/start',
    routes: [
      GoRoute(
        path: '/onboarding/start',
        builder: (context, state) => const DriverOnboardingStartScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          repository ?? _FakeAuthRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(Dio(), const FlutterSecureStorage());

  int logoutCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
