import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
import 'package:driver/features/notifications/data/device_id_store.dart';
import 'package:driver/features/notifications/data/local_notifications_service.dart';
import 'package:driver/features/notifications/data/push_message_handler.dart';
import 'package:driver/features/notifications/data/push_messaging_service.dart';
import 'package:driver/features/notifications/data/push_registration_coordinator.dart';
import 'package:driver/features/notifications/data/push_registration_repository.dart';

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
    'DRIVER-PUSH-R1: con sesión válida dispara el registro de push, sin esperarlo '
    '(la navegación se completa aunque el registro nunca termine)',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [_stateOf(DriverSessionKind.approved)],
      );
      final coordinator = _FakePushRegistrationCoordinator(
        behavior: _CoordinatorBehavior.hangs,
      );
      await _pumpSplash(tester, repository, coordinator: coordinator);

      await _finishInitialDelay(tester);

      expect(find.text('HOME_ROUTE'), findsOneWidget);
      expect(coordinator.syncCalls, 1);
    },
  );

  testWidgets(
    'DRIVER-PUSH-R1: sin sesión NO se intenta registrar el dispositivo',
    (tester) async {
      final repository = _FakeAuthRepository(hasSessionResult: false);
      final coordinator = _FakePushRegistrationCoordinator();
      await _pumpSplash(tester, repository, coordinator: coordinator);

      await _finishInitialDelay(tester);

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
      expect(coordinator.syncCalls, 0);
    },
  );

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

      expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
      expect(repository.clearSessionCalls, 0);
    },
  );

  testWidgets(
    'sin solicitud de conductor (404) navega al formulario real de Sobre ti',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [_stateOf(DriverSessionKind.noProfile)],
      );
      await _pumpSplash(tester, repository);

      await _finishInitialDelay(tester);

      expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('DRAFT sin vehículo navega al formulario de Tu mototaxi', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.draftNoVehicle)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
  });

  testWidgets(
    'DRAFT con vehículo y documentos incompletos navega a Tus documentos '
    '(Paso 4)',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [_stateOf(DriverSessionKind.draftDocumentsIncomplete)],
      );
      await _pumpSplash(tester, repository);

      await _finishInitialDelay(tester);

      expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    'DRAFT con documentos completos navega a Revisar y enviar (Paso 5)',
    (tester) async {
      final repository = _FakeAuthRepository(
        results: [_stateOf(DriverSessionKind.draftDocumentsComplete)],
      );
      await _pumpSplash(tester, repository);

      await _finishInitialDelay(tester);

      expect(find.text('SUBMIT_REVIEW_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('correctionsRequired navega a la pantalla de correcciones '
      '(DRIVER-ONBOARDING-R3.8)', (tester) async {
    final repository = _FakeAuthRepository(
      results: [_stateOf(DriverSessionKind.correctionsRequired)],
    );
    await _pumpSplash(tester, repository);

    await _finishInitialDelay(tester);

    expect(find.text('CORRECTIONS_ROUTE'), findsOneWidget);
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
  _FakeAuthRepository repository, {
  _FakePushRegistrationCoordinator? coordinator,
}) async {
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
        path: '/onboarding/about-you',
        builder: (context, state) =>
            const Scaffold(body: Text('ABOUT_YOU_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/vehicle',
        builder: (context, state) =>
            const Scaffold(body: Text('VEHICLE_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/documents',
        builder: (context, state) =>
            const Scaffold(body: Text('DOCUMENTS_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/review',
        builder: (context, state) =>
            const Scaffold(body: Text('SUBMIT_REVIEW_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/corrections',
        builder: (context, state) =>
            const Scaffold(body: Text('CORRECTIONS_ROUTE')),
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
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        // El coordinador real toca FirebaseMessaging.instance, que no
        // existe en flutter_test. Se reemplaza por un doble no-op salvo
        // que el test quiera otro comportamiento.
        pushRegistrationCoordinatorProvider.overrideWithValue(
          coordinator ?? _FakePushRegistrationCoordinator(),
        ),
        // El handler real toca `FirebaseMessaging.onMessage`, ausente
        // en flutter_test. Doble no-op: el splash solo llama a
        // `start()` y no depende de su resultado.
        pushMessageHandlerProvider.overrideWithValue(
          _FakePushMessageHandler(),
        ),
      ],
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

enum _CoordinatorBehavior { noop, hangs }

class _NoopPushMessagingService implements PushMessagingService {
  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
}

/// Doble no-op del handler de mensajes push para los tests del splash.
/// El splash solo invoca `start()`; acá se vuelve inofensivo.
class _FakePushMessageHandler extends PushMessageHandler {
  _FakePushMessageHandler()
    : super(const Stream<RemoteMessage>.empty(), _NoopLocalNotifications());

  int startCalls = 0;

  @override
  void start() {
    startCalls += 1;
  }
}

class _NoopLocalNotifications implements LocalNotifications {
  @override
  Future<void> show({required String title, required String body}) async {}
}

/// Doble del coordinador de push para los tests del splash: cuenta las
/// invocaciones y puede simular un fallo o un cuelgue para verificar
/// que la navegación del splash no depende de él.
class _FakePushRegistrationCoordinator extends PushRegistrationCoordinator {
  _FakePushRegistrationCoordinator({
    this.behavior = _CoordinatorBehavior.noop,
  }) : super(
         _NoopPushMessagingService(),
         DeviceIdStore(const FlutterSecureStorage()),
         PushRegistrationRepository(Dio()),
       );

  final _CoordinatorBehavior behavior;
  int syncCalls = 0;

  @override
  Future<void> syncDeviceRegistration() async {
    syncCalls += 1;

    switch (behavior) {
      case _CoordinatorBehavior.noop:
        return;
      case _CoordinatorBehavior.hangs:
        await Completer<void>().future;
    }
  }
}
