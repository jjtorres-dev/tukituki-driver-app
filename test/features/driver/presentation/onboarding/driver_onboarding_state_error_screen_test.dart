import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_state_error_screen.dart';

const _user = AuthenticatedUser(
  id: 'user-1',
  phoneE164: '+51987654321',
  roles: ['PASSENGER', 'DRIVER'],
  status: 'ACTIVE',
  isPhoneVerified: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'muestra el mensaje de inconsistencia con reintentar y cerrar sesión',
    (tester) async {
      await _pumpScreen(tester, _FakeAuthRepository());

      expect(find.text('No pudimos continuar'), findsOneWidget);
      expect(find.byKey(const Key('state-error-retry-button')), findsOneWidget);
      expect(
        find.byKey(const Key('state-error-logout-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('reintentar con estado ya resuelto navega a home', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      sessionState: const DriverSessionState(
        kind: DriverSessionKind.approved,
        user: _user,
      ),
    );
    await _pumpScreen(tester, repository);

    await tester.tap(find.byKey(const Key('state-error-retry-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('HOME_ROUTE'), findsOneWidget);
  });

  testWidgets('cerrar sesión desloguea y navega a login', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository);

    await tester.tap(find.byKey(const Key('state-error-logout-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(repository.logoutCalls, 1);
    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/onboarding/state-error',
    routes: [
      GoRoute(
        path: '/onboarding/state-error',
        builder: (context, state) => const DriverOnboardingStateErrorScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('HOME_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({DriverSessionState? sessionState})
    : sessionState =
          sessionState ??
          const DriverSessionState(
            kind: DriverSessionKind.unknownApplicationStatus,
            user: _user,
          ),
      super(Dio(), const FlutterSecureStorage());

  final DriverSessionState sessionState;

  int logoutCalls = 0;

  @override
  Future<DriverSessionState> resolveSessionState() async => sessionState;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
