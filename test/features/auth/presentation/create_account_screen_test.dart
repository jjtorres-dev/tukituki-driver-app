import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/auth/presentation/create_account_screen.dart';

const _unverifiedUser = AuthenticatedUser(
  id: 'user-1',
  phoneE164: '+51943154443',
  roles: ['PASSENGER'],
  status: 'ACTIVE',
  isPhoneVerified: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra el paso 1 con los 3 campos y el progreso', (
    tester,
  ) async {
    await _pumpScreen(tester, _FakeAuthRepository());

    expect(find.text('Tu cuenta'), findsOneWidget);
    expect(find.text('Número de celular'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Confirmar contraseña'), findsOneWidget);
    expect(
      find.byKey(const Key('create-account-submit-button')),
      findsOneWidget,
    );
  });

  testWidgets('teléfono inválido no ejecuta el registro', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository);

    await tester.enterText(_phoneField, '123');
    await tester.enterText(_passwordField, 'Password1');
    await tester.enterText(_confirmField, 'Password1');
    await _tapSubmit(tester);

    expect(repository.registerCalls, 0);
    expect(find.textContaining('9 dígitos'), findsOneWidget);
  });

  testWidgets('contraseña sin mayúscula no ejecuta el registro', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository);

    await tester.enterText(_phoneField, '943154443');
    await tester.enterText(_passwordField, 'password1');
    await tester.enterText(_confirmField, 'password1');
    await _tapSubmit(tester);

    expect(repository.registerCalls, 0);
    expect(find.text('Incluye al menos una mayúscula'), findsOneWidget);
  });

  testWidgets('contraseñas que no coinciden no ejecutan el registro', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpScreen(tester, repository);

    await tester.enterText(_phoneField, '943154443');
    await tester.enterText(_passwordField, 'Password1');
    await tester.enterText(_confirmField, 'Password2');
    await _tapSubmit(tester);

    expect(repository.registerCalls, 0);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('registro + login exitosos navegan según resolveSessionState', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      sessionState: const DriverSessionState(
        kind: DriverSessionKind.noProfile,
        user: _unverifiedUser,
      ),
    );
    await _pumpScreen(tester, repository);

    await _fillValidForm(tester);
    await _tapSubmit(tester);

    expect(repository.registerCalls, 1);
    expect(repository.loginCalls, 1);
    expect(repository.lastPhoneE164, '+51943154443');
    expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
  });

  group('409 en registro (teléfono ya registrado)', () {
    testWidgets('muestra el modal centrado (no SnackBar) con título y CTA, '
        'y restaura el loading', (tester) async {
      final repository = _FakeAuthRepository(
        registerError: _dioError(409, path: 'auth/register/passenger'),
      );
      await _pumpScreen(tester, repository);

      await _fillValidForm(tester);
      await _tapSubmit(tester);

      // A. modal visible.
      expect(find.byType(Dialog), findsOneWidget);
      // B. título del modal.
      expect(find.text('Número ya registrado'), findsOneWidget);
      expect(
        find.textContaining('ya tiene una cuenta en TukiTuki'),
        findsOneWidget,
      );
      // C. CTA del modal.
      expect(
        find.byKey(const Key('duplicate-phone-dialog-login-button')),
        findsOneWidget,
      );
      // F. sin SnackBar, sin jerga técnica/Passenger.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('Passenger'), findsNothing);
      expect(find.textContaining('409'), findsNothing);
      expect(find.textContaining('ConflictException'), findsNothing);
      expect(repository.loginCalls, 0);

      // G. loading restaurado (el CTA "Crear cuenta" vuelve a
      // estar habilitado detrás del modal).
      final button = tester.widget<FilledButton>(_submitButton);
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
      'D. la X cierra el modal sin navegar y sin reenviar el registro',
      (tester) async {
        final repository = _FakeAuthRepository(
          registerError: _dioError(409, path: 'auth/register/passenger'),
        );
        await _pumpScreen(tester, repository);

        await _fillValidForm(tester);
        await _tapSubmit(tester);

        expect(find.byType(Dialog), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('duplicate-phone-dialog-close-button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Dialog), findsNothing);
        expect(find.text('LOGIN_ROUTE'), findsNothing);
        expect(_phoneField, findsOneWidget);
        expect(repository.registerCalls, 1, reason: 'no debe reenviar');
      },
    );

    testWidgets('E. el CTA "Iniciar sesión" del modal navega a Login', (
      tester,
    ) async {
      final repository = _FakeAuthRepository(
        registerError: _dioError(409, path: 'auth/register/passenger'),
      );
      await _pumpScreen(tester, repository);

      await _fillValidForm(tester);
      await _tapSubmit(tester);

      await tester.tap(
        find.byKey(const Key('duplicate-phone-dialog-login-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });
  });

  testWidgets(
    'si el registro tuvo éxito pero el login falla, un reintento NO vuelve a registrar',
    (tester) async {
      final repository = _FakeAuthRepository(
        loginError: _dioError(
          null,
          path: 'auth/login',
          type: DioExceptionType.connectionError,
        ),
        sessionState: const DriverSessionState(
          kind: DriverSessionKind.noProfile,
          user: _unverifiedUser,
        ),
      );
      await _pumpScreen(tester, repository);

      await _fillValidForm(tester);
      await _tapSubmit(tester);

      expect(repository.registerCalls, 1);
      expect(repository.loginCalls, 1);
      expect(find.textContaining('No se pudo conectar'), findsOneWidget);

      repository.loginError = null;
      await _tapSubmit(tester);

      expect(repository.registerCalls, 1, reason: 'no debe re-registrar');
      expect(repository.loginCalls, 2);
      expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('loading deshabilita el CTA', (tester) async {
    final completer = Completer<void>();
    final repository = _FakeAuthRepository(registerCompleter: completer);
    await _pumpScreen(tester, repository);

    await _fillValidForm(tester);
    await tester.tap(_submitButton);
    await tester.pump();

    final button = tester.widget<FilledButton>(_submitButton);
    expect(button.onPressed, isNull);
    expect(find.text('Creando cuenta...'), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('el botón de regresar navega a login', (tester) async {
    await _pumpScreen(tester, _FakeAuthRepository());

    await tester.tap(find.byKey(const Key('create-account-back-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('LOGIN_ROUTE'), findsOneWidget);
  });
}

Finder get _phoneField => find.byKey(const Key('create-account-phone-field'));
Finder get _passwordField =>
    find.byKey(const Key('create-account-password-field'));
Finder get _confirmField =>
    find.byKey(const Key('create-account-confirm-password-field'));
Finder get _submitButton =>
    find.byKey(const Key('create-account-submit-button'));

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(_phoneField, '943154443');
  await tester.enterText(_passwordField, 'Password1');
  await tester.enterText(_confirmField, 'Password1');
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submitButton);
  await tester.tap(_submitButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/onboarding/account',
    routes: [
      GoRoute(
        path: '/onboarding/account',
        builder: (context, state) => const CreateAccountScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/about-you',
        builder: (context, state) =>
            const Scaffold(body: Text('ABOUT_YOU_ROUTE')),
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

DioException _dioError(
  int? statusCode, {
  required String path,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final request = RequestOptions(path: path);

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
    this.registerError,
    this.loginError,
    this.registerCompleter,
    DriverSessionState? sessionState,
  }) : sessionState =
           sessionState ??
           const DriverSessionState(
             kind: DriverSessionKind.noProfile,
             user: _unverifiedUser,
           ),
       super(Dio(), const FlutterSecureStorage());

  Object? registerError;
  Object? loginError;
  final Completer<void>? registerCompleter;
  final DriverSessionState sessionState;

  int registerCalls = 0;
  int loginCalls = 0;
  String? lastPhoneE164;

  @override
  Future<void> registerPassenger({
    required String phoneE164,
    required String password,
  }) async {
    registerCalls += 1;
    lastPhoneE164 = phoneE164;

    if (registerError case final error?) {
      throw error;
    }

    await registerCompleter?.future;
  }

  @override
  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    loginCalls += 1;

    if (loginError case final error?) {
      throw error;
    }
  }

  @override
  Future<DriverSessionState> resolveSessionState() async => sessionState;
}
