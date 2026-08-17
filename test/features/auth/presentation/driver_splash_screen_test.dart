import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/auth/presentation/driver_splash_screen.dart';
import 'package:driver/features/driver/domain/driver_application.dart';

const _user = AuthenticatedUser(
  id: 'user-1',
  phoneE164: '+51987654321',
  roles: ['PASSENGER', 'DRIVER'],
  status: 'ACTIVE',
  isPhoneVerified: true,
);

DriverSessionState _stateOf(
  DriverSessionKind kind, {
  DriverApplication? application,
}) {
  return DriverSessionState(kind: kind, user: _user, application: application);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra la identidad visual completa de Driver', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpSplash(tester, repository);

    expect(find.text('MODO CONDUCTOR'), findsOneWidget);
    expect(find.text('TukiTuki'), findsOneWidget);
    expect(find.text('Conductor'), findsOneWidget);
    expect(find.text('Recuperando tu sesión...'), findsOneWidget);
    expect(
      find.text('Prepara tu mototaxi, ya casi estás en línea'),
      findsOneWidget,
    );
    expect(_driverLogoFinder(), findsOneWidget);
  });

  testWidgets('sin sesión navega a login después de la espera mínima', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(hasSessionResult: false);
    await _pumpSplash(tester, repository);

    await tester.pump(const Duration(milliseconds: 799));
    expect(find.text('LOGIN_ROUTE'), findsNothing);

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(repository.clearSessionCalls, 1);
    expect(repository.resolveSessionStateCalls, 0);
  });

  testWidgets('APPROVED + rol DRIVER navega a home', (tester) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.approved)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('HOME_ROUTE'), findsOneWidget);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets(
    'MVP: teléfono no verificado + sin solicitud navega igual al onboarding '
    '(OTP diferido, no bloquea)',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [
          DriverSessionState(
            kind: DriverSessionKind.noProfile,
            user: const AuthenticatedUser(
              id: 'user-1',
              phoneE164: '+51987654321',
              roles: ['PASSENGER'],
              status: 'ACTIVE',
              isPhoneVerified: false,
            ),
          ),
        ],
      );
      await _pumpSplash(tester, repository);

      await _finishInitialDelay(tester);

      expect(find.text('ONBOARDING_START_ROUTE'), findsOneWidget);
      expect(repository.clearSessionCalls, 0);
    },
  );

  testWidgets(
    'sin solicitud de conductor (404) navega al inicio del onboarding',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [_stateOf(DriverSessionKind.noProfile)],
      );
      await _pumpSplash(tester, repository);

      await _finishInitialDelay(tester);

      expect(find.text('ONBOARDING_START_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('DRAFT navega al mismo inicio del onboarding', (tester) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.draft)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('ONBOARDING_START_ROUTE'), findsOneWidget);
  });

  testWidgets('REJECTED navega a la pantalla de corrección', (tester) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.rejected)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('REJECTED_ROUTE'), findsOneWidget);
  });

  testWidgets('PENDING_REVIEW navega a la pantalla de revisión', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.pendingReview)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('REVIEW_ROUTE'), findsOneWidget);
  });

  testWidgets('SUSPENDED navega a la pantalla de suspensión', (tester) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.suspended)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('SUSPENDED_ROUTE'), findsOneWidget);
  });

  testWidgets('APPROVED sin rol DRIVER (inconsistencia) NUNCA entra a home', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.approvedRoleMismatch)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('HOME_ROUTE'), findsNothing);
    expect(find.text('STATE_ERROR_ROUTE'), findsOneWidget);
  });

  testWidgets('status de solicitud desconocido NUNCA entra a home', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.unknownApplicationStatus)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('HOME_ROUTE'), findsNothing);
    expect(find.text('STATE_ERROR_ROUTE'), findsOneWidget);
  });

  testWidgets('401 definitivo limpia la sesión y navega a login', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_dioError(statusCode: 401)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(repository.clearSessionCalls, 1);
  });

  testWidgets('timeout conserva sesión y muestra error recuperable', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_dioError(type: DioExceptionType.connectionTimeout)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('No pudimos continuar'), findsOneWidget);
    expect(find.textContaining('tardando más de lo esperado'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('LOGIN_ROUTE'), findsNothing);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets('error de conexión conserva sesión y es recuperable', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_dioError(type: DioExceptionType.connectionError)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
    expect(find.text('Ir al inicio de sesión'), findsOneWidget);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets('5xx conserva sesión y muestra indisponibilidad temporal', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_dioError(statusCode: 503)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(
      find.textContaining('no está disponible temporalmente'),
      findsOneWidget,
    );
    expect(find.textContaining('sesión se mantiene guardada'), findsOneWidget);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets(
    'Reintentar ejecuta una restauración y un retry exitoso va a home',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [
          _dioError(type: DioExceptionType.connectionError),
          _stateOf(DriverSessionKind.approved),
        ],
      );
      await _pumpSplash(tester, repository);
      await _finishInitialDelay(tester);

      expect(repository.resolveSessionStateCalls, 1);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(repository.resolveSessionStateCalls, 2);
      expect(find.text('HOME_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('dispose cancela timer y AnimationController sin excepciones', (
    tester,
  ) async {
    await _pumpSplash(tester, _FakeAuthRepository());

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('viewport 360x640 no produce overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSplash(tester, _FakeAuthRepository());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(
      find.text('Prepara tu mototaxi, ya casi estás en línea'),
      findsOneWidget,
    );
  });

  testWidgets('viewport 390x844 no produce overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSplash(tester, _FakeAuthRepository());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('MODO CONDUCTOR'), findsOneWidget);
  });
}

Future<void> _finishInitialDelay(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 801));
  await tester.pump();
}

Future<void> _pumpSplash(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const DriverSplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('HOME_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/account',
        builder: (context, state) =>
            const Scaffold(body: Text('ACCOUNT_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/start',
        builder: (context, state) =>
            const Scaffold(body: Text('ONBOARDING_START_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/rejected',
        builder: (context, state) =>
            const Scaffold(body: Text('REJECTED_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/review-status',
        builder: (context, state) => const Scaffold(body: Text('REVIEW_ROUTE')),
      ),
      GoRoute(
        path: '/suspended',
        builder: (context, state) =>
            const Scaffold(body: Text('SUSPENDED_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/state-error',
        builder: (context, state) =>
            const Scaffold(body: Text('STATE_ERROR_ROUTE')),
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

Finder _driverLogoFinder() {
  return find.byWidgetPredicate((widget) {
    if (widget is! Image || widget.image is! AssetImage) {
      return false;
    }

    return (widget.image as AssetImage).assetName ==
        'assets/images/tukituki_driver_logo.png';
  });
}

DioException _dioError({
  DioExceptionType type = DioExceptionType.badResponse,
  int? statusCode,
}) {
  final request = RequestOptions(path: 'auth/me');

  return DioException(
    requestOptions: request,
    type: type,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: request, statusCode: statusCode),
  );
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.hasSessionResult = true, List<Object>? results})
    : results = results ?? <Object>[_stateOf(DriverSessionKind.approved)],
      super(Dio(), const FlutterSecureStorage());

  final bool hasSessionResult;
  final List<Object> results;

  int resolveSessionStateCalls = 0;
  int clearSessionCalls = 0;

  @override
  Future<bool> hasSession() async => hasSessionResult;

  @override
  Future<DriverSessionState> resolveSessionState() async {
    resolveSessionStateCalls += 1;
    final result = results.length > 1 ? results.removeAt(0) : results.first;

    if (result is DriverSessionState) {
      return result;
    }

    throw result;
  }

  @override
  Future<void> clearSession() async {
    clearSessionCalls += 1;
  }
}
