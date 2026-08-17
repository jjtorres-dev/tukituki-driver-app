import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_rejected_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin rejectionReason no muestra ninguna card de motivo', (
    tester,
  ) async {
    await _pumpScreen(tester, application: null);

    expect(find.text('Tu solicitud necesita correcciones'), findsOneWidget);
    expect(find.textContaining('MOTIVO INDICADO'), findsNothing);
  });

  testWidgets('con rejectionReason lo muestra tal cual, sin inventarlo', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      application: _application(rejectionReason: 'Foto de licencia ilegible'),
    );

    expect(find.text('Foto de licencia ilegible'), findsOneWidget);
  });

  testWidgets('"Corregir solicitud" navega al inicio del onboarding', (
    tester,
  ) async {
    await _pumpScreen(tester, application: null);

    await tester.tap(find.byKey(const Key('rejected-fix-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ONBOARDING_START_ROUTE'), findsOneWidget);
  });

  testWidgets('cerrar sesión desloguea y navega a login', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, application: null, repository: repository);

    await tester.tap(find.byKey(const Key('rejected-logout-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.logoutCalls, 1);
    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
  });
}

DriverApplication _application({String? rejectionReason}) {
  return DriverApplication(
    id: 'profile-1',
    userId: 'user-1',
    firstName: 'Juan',
    lastName: 'Torres',
    status: DriverApplicationStatus.rejected,
    rejectionReason: rejectionReason,
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required DriverApplication? application,
  _FakeAuthRepository? repository,
}) async {
  final router = GoRouter(
    initialLocation: '/onboarding/rejected',
    routes: [
      GoRoute(
        path: '/onboarding/rejected',
        builder: (context, state) =>
            DriverOnboardingRejectedScreen(application: application),
      ),
      GoRoute(
        path: '/onboarding/start',
        builder: (context, state) =>
            const Scaffold(body: Text('ONBOARDING_START_ROUTE')),
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
