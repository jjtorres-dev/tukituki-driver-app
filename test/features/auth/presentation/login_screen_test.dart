import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/presentation/login_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('muestra todos los elementos visuales aprobados', (tester) async {
    await _pumpLogin(tester, _FakeAuthRepository());

    expect(find.text('MODO CONDUCTOR'), findsOneWidget);
    expect(find.text('TukiTuki Conductor'), findsOneWidget);
    expect(find.text('Inicia sesión para avanzar'), findsOneWidget);
    expect(find.text('Número de celular'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
    expect(
      find.textContaining('¿Aún no eres socio conductor?'),
      findsOneWidget,
    );
    expect(find.textContaining('Crea tu cuenta'), findsOneWidget);
    expect(find.textContaining('¿Eres pasajero?'), findsOneWidget);
    expect(find.textContaining('Ir a TukiTuki App'), findsOneWidget);
    expect(_driverLogoFinder(), findsOneWidget);
  });

  testWidgets('teléfono menor de 9 dígitos no ejecuta login', (tester) async {
    final repository = _FakeAuthRepository();
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester, phone: '94315', password: 'password');
    await _tapSubmit(tester);

    expect(repository.loginCalls, 0);
    expect(find.textContaining('9 dígitos'), findsOneWidget);
  });

  testWidgets('teléfono queda limitado a 9 dígitos', (tester) async {
    await _pumpLogin(tester, _FakeAuthRepository());

    await tester.enterText(_phoneField, '94315444399');

    final field = tester.widget<TextFormField>(_phoneField);
    expect(field.controller!.text, '943154443');
  });

  testWidgets('teléfono filtra caracteres no numéricos', (tester) async {
    await _pumpLogin(tester, _FakeAuthRepository());

    await tester.enterText(_phoneField, '94a3-15b4443');

    final field = tester.widget<TextFormField>(_phoneField);
    expect(field.controller!.text, '943154443');
  });

  testWidgets('password menor de 8 caracteres no ejecuta login', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester, phone: '943154443', password: '1234567');
    await _tapSubmit(tester);

    expect(repository.loginCalls, 0);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
  });

  testWidgets('credenciales válidas envían el mismo phoneE164 con +51', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester);
    await _tapSubmit(tester);

    expect(repository.loginCalls, 1);
    expect(repository.lastPhoneE164, '+51943154443');
    expect(repository.lastPassword, 'password');
  });

  testWidgets(
    'login exitoso navega a /splash (routing real lo decide Splash)',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpLogin(tester, repository);

      await _enterCredentials(tester);
      await _tapSubmit(tester);

      expect(find.text('SPLASH_ROUTE'), findsOneWidget);
    },
  );

  testWidgets(
    'una cuenta PASSENGER-only NO se desloguea ni bloquea en Login: la resolución queda para Splash',
    (tester) async {
      // Este checkpoint quitó el gate `isDriver()` + logout de Login:
      // una cuenta sin rol DRIVER hoy puede loguearse y postular
      // (decisión de producto). No hay ningún método `isDriver`
      // que este repositorio falso necesite implementar.
      final repository = _FakeAuthRepository();
      await _pumpLogin(tester, repository);

      await _enterCredentials(tester);
      await _tapSubmit(tester);

      expect(repository.logoutCalls, 0);
      expect(find.text('SPLASH_ROUTE'), findsOneWidget);
    },
  );

  testWidgets('401 muestra credenciales incorrectas', (tester) async {
    final repository = _FakeAuthRepository(loginError: _dioError(401));
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester);
    await _tapSubmit(tester);

    expect(find.text('Teléfono o contraseña incorrectos.'), findsOneWidget);
    expect(find.text('SPLASH_ROUTE'), findsNothing);
  });

  testWidgets('403 muestra cuenta no habilitada', (tester) async {
    final repository = _FakeAuthRepository(loginError: _dioError(403));
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester);
    await _tapSubmit(tester);

    expect(find.text('La cuenta no está habilitada.'), findsOneWidget);
  });

  testWidgets('error de red muestra mensaje recuperable', (tester) async {
    final repository = _FakeAuthRepository(
      loginError: _dioError(null, DioExceptionType.connectionError),
    );
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester);
    await _tapSubmit(tester);

    expect(find.text('No se pudo conectar con TukiTuki.'), findsOneWidget);
    expect(find.text('SPLASH_ROUTE'), findsNothing);
  });

  testWidgets('5xx muestra indisponibilidad temporal', (tester) async {
    final repository = _FakeAuthRepository(loginError: _dioError(503));
    await _pumpLogin(tester, repository);

    await _enterCredentials(tester);
    await _tapSubmit(tester);

    expect(
      find.text(
        'TukiTuki no está disponible temporalmente. Intenta nuevamente.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('doble tap durante loading ejecuta una sola llamada', (
    tester,
  ) async {
    final completer = Completer<void>();
    final repository = _FakeAuthRepository(loginCompleter: completer);
    await _pumpLogin(tester, repository);
    await _enterCredentials(tester);

    await tester.tap(_submitButton);
    await tester.tap(_submitButton);
    await tester.pump();

    expect(repository.loginCalls, 1);

    completer.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('ojo alterna obscureText', (tester) async {
    await _pumpLogin(tester, _FakeAuthRepository());

    EditableText password = tester.widget<EditableText>(
      find.descendant(of: _passwordField, matching: find.byType(EditableText)),
    );
    expect(password.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('password-visibility-button')));
    await tester.pump();

    password = tester.widget<EditableText>(
      find.descendant(of: _passwordField, matching: find.byType(EditableText)),
    );
    expect(password.obscureText, isFalse);
  });

  testWidgets('loading deshabilita CTA y muestra estado visual', (
    tester,
  ) async {
    final completer = Completer<void>();
    final repository = _FakeAuthRepository(loginCompleter: completer);
    await _pumpLogin(tester, repository);
    await _enterCredentials(tester);

    await tester.tap(_submitButton);
    await tester.pump();

    final button = tester.widget<FilledButton>(_submitButton);
    expect(button.onPressed, isNull);
    expect(find.text('Iniciando sesión...'), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump();
  });

  testWidgets('viewport 360x640 con teclado no produce overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await _pumpLogin(tester, _FakeAuthRepository());
    await tester.ensureVisible(_submitButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(_submitButton, findsOneWidget);
  });

  testWidgets('viewport estándar 390x844 no produce overflow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLogin(tester, _FakeAuthRepository());
    await tester.ensureVisible(_submitButton);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('TukiTuki Conductor'), findsOneWidget);
  });

  testWidgets(
    'copys informativos (olvidé mi contraseña / pasajero) no navegan ni ejecutan login',
    (tester) async {
      final repository = _FakeAuthRepository();
      await _pumpLogin(tester, repository);

      final forgot = find.text('¿Olvidaste tu contraseña?');
      final passenger = find.textContaining('Ir a TukiTuki App');

      await tester.tap(forgot);
      await tester.ensureVisible(passenger);
      await tester.tap(passenger);
      await tester.pump();

      expect(find.text('SPLASH_ROUTE'), findsNothing);
      expect(find.text('ACCOUNT_ROUTE'), findsNothing);
      expect(repository.loginCalls, 0);
      expect(
        find.ancestor(of: forgot, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.ancestor(of: passenger, matching: find.byType(InkWell)),
        findsNothing,
      );
    },
  );

  testWidgets('"Crea tu cuenta" navega a la pantalla de crear cuenta', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await _pumpLogin(tester, repository);

    final createAccountLink = find.byKey(
      const Key('login-create-account-link'),
    );

    await tester.ensureVisible(createAccountLink);
    await tester.tap(createAccountLink);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ACCOUNT_ROUTE'), findsOneWidget);
    expect(repository.loginCalls, 0);
  });
}

Finder get _phoneField => find.byKey(const Key('login-phone-field'));
Finder get _passwordField => find.byKey(const Key('login-password-field'));
Finder get _submitButton => find.byKey(const Key('login-submit-button'));

Future<void> _enterCredentials(
  WidgetTester tester, {
  String phone = '943154443',
  String password = 'password',
}) async {
  await tester.enterText(_phoneField, phone);
  await tester.enterText(_passwordField, password);
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submitButton);
  await tester.tap(_submitButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _pumpLogin(
  WidgetTester tester,
  _FakeAuthRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/splash',
        builder: (context, state) => const Scaffold(body: Text('SPLASH_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/account',
        builder: (context, state) =>
            const Scaffold(body: Text('ACCOUNT_ROUTE')),
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

DioException _dioError(
  int? statusCode, [
  DioExceptionType type = DioExceptionType.badResponse,
]) {
  final request = RequestOptions(path: 'auth/login');

  return DioException(
    requestOptions: request,
    type: type,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: request, statusCode: statusCode),
  );
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.loginError, this.loginCompleter})
    : super(Dio(), const FlutterSecureStorage());

  final Object? loginError;
  final Completer<void>? loginCompleter;

  int loginCalls = 0;
  int logoutCalls = 0;
  String? lastPhoneE164;
  String? lastPassword;

  @override
  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    loginCalls += 1;
    lastPhoneE164 = phoneE164;
    lastPassword = password;

    if (loginError case final error?) {
      throw error;
    }

    await loginCompleter?.future;
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
