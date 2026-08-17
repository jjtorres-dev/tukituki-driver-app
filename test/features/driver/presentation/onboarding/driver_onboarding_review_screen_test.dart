import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_review_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra el estado sin inventar plazos (24h/48h/etc.)', (
    tester,
  ) async {
    await _pumpScreen(tester);

    expect(find.text('Solicitud en revisión'), findsOneWidget);
    expect(find.textContaining('24 horas'), findsNothing);
    expect(find.textContaining('48 horas'), findsNothing);
    expect(find.textContaining('hoy mismo'), findsNothing);
  });

  testWidgets('cerrar sesión desloguea y navega a login', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository: repository);

    await tester.tap(find.byKey(const Key('review-logout-button')));
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
    initialLocation: '/onboarding/review-status',
    routes: [
      GoRoute(
        path: '/onboarding/review-status',
        builder: (context, state) => const DriverOnboardingReviewScreen(),
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
