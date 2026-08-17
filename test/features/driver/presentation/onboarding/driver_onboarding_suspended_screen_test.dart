import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_suspended_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin suspensionReason no muestra ninguna card de motivo', (
    tester,
  ) async {
    await _pumpScreen(tester, application: null);

    expect(find.text('Cuenta de conductor suspendida'), findsOneWidget);
    expect(find.textContaining('MOTIVO INDICADO'), findsNothing);
  });

  testWidgets('con suspensionReason lo muestra tal cual, sin inventarlo', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      application: DriverApplication(
        id: 'profile-1',
        userId: 'user-1',
        firstName: 'Juan',
        lastName: 'Torres',
        status: DriverApplicationStatus.suspended,
        suspensionReason: 'Reincidencia de cancelaciones',
      ),
    );

    expect(find.text('Reincidencia de cancelaciones'), findsOneWidget);
  });

  testWidgets('solo ofrece cerrar sesión, ninguna operación de Driver', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, application: null, repository: repository);

    expect(find.byKey(const Key('suspended-logout-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('suspended-logout-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.logoutCalls, 1);
    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DriverApplication? application,
  _FakeAuthRepository? repository,
}) async {
  final router = GoRouter(
    initialLocation: '/suspended',
    routes: [
      GoRoute(
        path: '/suspended',
        builder: (context, state) =>
            DriverOnboardingSuspendedScreen(application: application),
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
