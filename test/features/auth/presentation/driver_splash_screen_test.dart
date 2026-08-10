import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/presentation/driver_splash_screen.dart';

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
    expect(repository.isDriverCalls, 0);
  });

  testWidgets('sesión válida con rol DRIVER navega a home', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('HOME_ROUTE'), findsOneWidget);
    expect(repository.clearSessionCalls, 0);
  });

  testWidgets('rol distinto de DRIVER limpia la sesión y navega a login', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(driverResults: [false]);
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    expect(repository.clearSessionCalls, 1);
  });

  testWidgets('401 definitivo limpia la sesión y navega a login', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      driverResults: [_dioError(statusCode: 401)],
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
      driverResults: [_dioError(type: DioExceptionType.connectionTimeout)],
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
      driverResults: [_dioError(type: DioExceptionType.connectionError)],
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
      driverResults: [_dioError(statusCode: 503)],
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
        driverResults: [
          _dioError(type: DioExceptionType.connectionError),
          true,
        ],
      );
      await _pumpSplash(tester, repository);
      await _finishInitialDelay(tester);

      expect(repository.isDriverCalls, 1);

      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(repository.isDriverCalls, 2);
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
  _FakeAuthRepository({
    this.hasSessionResult = true,
    List<Object>? driverResults,
  }) : driverResults = driverResults ?? <Object>[true],
       super(Dio(), const FlutterSecureStorage());

  final bool hasSessionResult;
  final List<Object> driverResults;

  int isDriverCalls = 0;
  int clearSessionCalls = 0;

  @override
  Future<bool> hasSession() async => hasSessionResult;

  @override
  Future<bool> isDriver() async {
    isDriverCalls += 1;
    final result = driverResults.length > 1
        ? driverResults.removeAt(0)
        : driverResults.first;

    if (result is bool) {
      return result;
    }

    throw result;
  }

  @override
  Future<void> clearSession() async {
    clearSessionCalls += 1;
  }
}
