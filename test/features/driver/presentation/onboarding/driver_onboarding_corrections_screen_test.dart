import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/core/router/driver_onboarding_routes.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/domain/driver_document.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_corrections_screen.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_documents_screen.dart';

AuthenticatedUser _user() {
  return const AuthenticatedUser(
    id: 'user-1',
    phoneE164: '+51987654321',
    roles: ['PASSENGER'],
    status: 'ACTIVE',
    isPhoneVerified: true,
  );
}

DriverApplication _application({
  String? rejectionReason,
  DriverApplicationStatus status = DriverApplicationStatus.draft,
}) {
  return DriverApplication(
    id: 'profile-1',
    userId: 'user-1',
    firstName: 'Rocio',
    lastName: 'Alegre',
    status: status,
    documentType: IdentityDocumentType.dni,
    documentNumber: '76751234',
    birthDate: '1990-03-25',
    rejectionReason: rejectionReason,
  );
}

DriverVehicle _vehicle({VehicleStatus status = VehicleStatus.draft}) {
  return DriverVehicle(
    id: 'vehicle-1',
    driverProfileId: 'profile-1',
    plate: 'J-2637',
    brand: 'Honda',
    model: 'Mototaxi',
    year: 2022,
    color: 'Azul',
    ownership: VehicleOwnership.owned,
    status: status,
  );
}

DriverDocument _document(
  DriverDocumentType type, {
  DriverDocumentStatus status = DriverDocumentStatus.draft,
  String? rejectionReason,
}) {
  final needsExpiresAt =
      type == DriverDocumentType.driverLicense ||
      type == DriverDocumentType.soat;

  return DriverDocument(
    id: 'document-${type.value}',
    driverProfileId: 'profile-1',
    type: type,
    status: status,
    fileObjectKey: 'drivers/profile-1/documents/${type.value}.jpg',
    documentNumber: 'ABC123',
    issuedAt: '2024-01-01',
    expiresAt: needsExpiresAt ? '2030-06-15' : null,
    rejectionReason: rejectionReason,
  );
}

List<DriverDocument> _cleanDocuments() {
  return requiredDriverOnboardingDocumentTypes.map(_document).toList();
}

DriverSessionState _correctionsState({
  DriverApplication? application,
  DriverVehicle? vehicle,
  List<DriverDocument>? documents,
}) {
  return DriverSessionState(
    kind: DriverSessionKind.correctionsRequired,
    user: _user(),
    application: application ?? _application(),
    vehicle: vehicle ?? _vehicle(),
    documents: documents ?? _cleanDocuments(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriverOnboardingCorrectionsScreen — carga', () {
    testWidgets('muestra un loader mientras carga', (tester) async {
      final authRepository = _FakeAuthRepository(
        completer: Completer<DriverSessionState>(),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.byKey(const Key('corrections-loading')), findsOneWidget);
    });

    testWidgets('error de carga muestra Reintentar y recarga al tocarlo', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        resolveSessionStateError: _dioError(500),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.byKey(const Key('corrections-load-error')), findsOneWidget);

      authRepository.resolveSessionStateError = null;
      authRepository.resolvedState = _correctionsState();
      await tester.tap(find.byKey(const Key('corrections-retry-button')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('corrections-load-error')), findsNothing);
      expect(find.text('Correcciones requeridas'), findsOneWidget);
    });

    testWidgets(
      'initialState con kind distinto de correctionsRequired resuelve de '
      'nuevo y se autocorrige navegando a donde corresponda',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          resolvedState: const DriverSessionState(
            kind: DriverSessionKind.draftDocumentsIncomplete,
            user: AuthenticatedUser(
              id: 'user-1',
              phoneE164: '+51987654321',
              roles: ['PASSENGER'],
              status: 'ACTIVE',
              isPhoneVerified: true,
            ),
          ),
        );

        await _pumpScreen(
          tester,
          authRepository: authRepository,
          initialState: const DriverSessionState(
            kind: DriverSessionKind.draftDocumentsComplete,
            user: AuthenticatedUser(
              id: 'user-1',
              phoneE164: '+51987654321',
              roles: ['PASSENGER'],
              status: 'ACTIVE',
              isPhoneVerified: true,
            ),
          ),
        );

        expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
      },
    );
  });

  group('DriverOnboardingCorrectionsScreen — las 5 secciones (decisión B)', () {
    testWidgets('siempre muestra las 5 secciones; solo las observadas tienen '
        '"Corregir", el resto "Sin observaciones"', (tester) async {
      await _pumpScreen(
        tester,
        initialState: _correctionsState(
          application: _application(rejectionReason: 'Foto ilegible'),
          documents: [
            _document(
              DriverDocumentType.driverLicense,
              status: DriverDocumentStatus.rejected,
              rejectionReason: 'Vencida',
            ),
            _document(DriverDocumentType.soat),
            _document(DriverDocumentType.vehicleRegistration),
          ],
        ),
      );

      expect(find.text('Sobre ti'), findsOneWidget);
      expect(find.text('Tu mototaxi'), findsOneWidget);
      expect(find.text('Licencia de conducir'), findsOneWidget);
      expect(find.text('SOAT'), findsOneWidget);
      expect(find.text('Tarjeta de propiedad / TIV'), findsOneWidget);

      expect(find.text('Foto ilegible'), findsOneWidget);
      expect(find.text('Vencida'), findsOneWidget);

      expect(find.text('Sin observaciones'), findsNWidgets(3));
      expect(
        find.byKey(const Key('corrections-profile-correct-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('corrections-license-correct-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('corrections-vehicle-correct-button')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('corrections-soat-correct-button')),
        findsNothing,
      );
      expect(
        find.byKey(
          const Key('corrections-vehicle-registration-correct-button'),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'vehicle.status == rejected observa solo Tu mototaxi — nunca usa '
      'application.status == REJECTED como señal',
      (tester) async {
        await _pumpScreen(
          tester,
          initialState: _correctionsState(
            vehicle: _vehicle(status: VehicleStatus.rejected),
          ),
        );

        expect(
          find.byKey(const Key('corrections-vehicle-correct-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('corrections-profile-correct-button')),
          findsNothing,
        );
        expect(find.text('Sin observaciones'), findsNWidgets(4));
      },
    );

    testWidgets('el texto de la observación se muestra exacto (decisión H, '
        'solo trim de espacios externos)', (tester) async {
      await _pumpScreen(
        tester,
        initialState: _correctionsState(
          application: _application(rejectionReason: '  Foto borrosa  '),
        ),
      );

      expect(find.text('Foto borrosa'), findsOneWidget);
    });
  });

  group('DriverOnboardingCorrectionsScreen — Corregir navega a cada paso', () {
    testWidgets('Sobre ti navega a about-you con el profile exacto', (
      tester,
    ) async {
      final application = _application(rejectionReason: 'Foto ilegible');
      await _pumpScreen(
        tester,
        initialState: _correctionsState(application: application),
      );

      final button = find.byKey(
        const Key('corrections-profile-correct-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
    });

    testWidgets('Tu mototaxi navega a vehicle con el vehículo exacto', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialState: _correctionsState(
          vehicle: _vehicle(status: VehicleStatus.rejected),
        ),
      );

      final button = find.byKey(
        const Key('corrections-vehicle-correct-button'),
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
    });

    testWidgets(
      'un documento observado navega a documents enfocado y restringido '
      '(decisión D)',
      (tester) async {
        await _pumpScreen(
          tester,
          initialState: _correctionsState(
            documents: [
              _document(DriverDocumentType.driverLicense),
              _document(
                DriverDocumentType.soat,
                status: DriverDocumentStatus.rejected,
                rejectionReason: 'SOAT vencido',
              ),
              _document(DriverDocumentType.vehicleRegistration),
            ],
          ),
        );

        final button = find.byKey(const Key('corrections-soat-correct-button'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
        expect(_lastDocumentsArgs?.focusDocumentType, DriverDocumentType.soat);
        expect(_lastDocumentsArgs?.editableDocumentTypes, {
          DriverDocumentType.soat,
        });
      },
    );

    testWidgets(
      'al volver de "Corregir" recarga el estado (resolveSessionState)',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          resolvedState: _correctionsState(),
        );
        await _pumpScreen(
          tester,
          authRepository: authRepository,
          initialState: _correctionsState(
            application: _application(rejectionReason: 'Foto ilegible'),
          ),
        );

        expect(authRepository.resolveSessionStateCalls, 0);

        final button = find.byKey(
          const Key('corrections-profile-correct-button'),
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('fake-back-button')));
        await tester.pumpAndSettle();

        expect(authRepository.resolveSessionStateCalls, 1);
        expect(find.text('Correcciones requeridas'), findsOneWidget);
      },
    );
  });

  group('DriverOnboardingCorrectionsScreen — Revisar y reenviar', () {
    testWidgets('deshabilitado mientras haya al menos una observación '
        'pendiente', (tester) async {
      await _pumpScreen(
        tester,
        initialState: _correctionsState(
          application: _application(rejectionReason: 'Foto ilegible'),
        ),
      );

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('corrections-resend-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      '19. application.status == REJECTED con rejectionReason == null NO '
      'bloquea el CTA — el perfil nunca fue observado, solo un hijo '
      '(caso físico real: Backend deja profile.status en REJECTED '
      'aunque el admin solo haya observado un documento)',
      (tester) async {
        await _pumpScreen(
          tester,
          initialState: _correctionsState(
            application: _application(status: DriverApplicationStatus.rejected),
          ),
        );

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('corrections-resend-button')),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets(
      '20. application.status == REJECTED CON rejectionReason no vacío '
      'SÍ bloquea el CTA',
      (tester) async {
        await _pumpScreen(
          tester,
          initialState: _correctionsState(
            application: _application(
              status: DriverApplicationStatus.rejected,
              rejectionReason: 'Foto ilegible',
            ),
          ),
        );

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('corrections-resend-button')),
        );
        expect(button.onPressed, isNull);
      },
    );

    testWidgets('habilitado y navega a Revisar y reenviar cuando ya no hay '
        'observaciones pendientes', (tester) async {
      final resubmissionReady = _correctionsState();
      final authRepository = _FakeAuthRepository(
        resolvedState: resubmissionReady,
      );
      await _pumpScreen(
        tester,
        authRepository: authRepository,
        initialState: resubmissionReady,
      );

      final button = find.byKey(const Key('corrections-resend-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('SUBMIT_REVIEW_ROUTE'), findsOneWidget);
    });

    testWidgets(
      'siempre vuelve a resolver el estado real antes de navegar — no '
      'confía ciegamente en el snapshot local (decisión E, gate no '
      'negociable)',
      (tester) async {
        final stillPending = _correctionsState(
          application: _application(rejectionReason: 'Foto ilegible'),
        );

        final authRepository = _FakeAuthRepository(resolvedState: stillPending);

        await _pumpScreen(
          tester,
          authRepository: authRepository,
          initialState: _correctionsState(),
        );

        final button = find.byKey(const Key('corrections-resend-button'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(find.text('SUBMIT_REVIEW_ROUTE'), findsNothing);
        expect(find.text('Correcciones requeridas'), findsOneWidget);
        expect(authRepository.resolveSessionStateCalls, 1);
      },
    );
  });

  group('DriverOnboardingCorrectionsScreen — REGRESSION R3.8.2 (CTA no se '
      'habilita hasta reiniciar la app)', () {
    testWidgets(
      'caso físico exacto: SOAT observado, se corrige y se vuelve vía '
      'context.go (como el botón Continuar real de Documentos, NO un '
      'simple pop) — el CTA debe habilitarse en la MISMA sesión',
      (tester) async {
        final initial = _correctionsState(
          application: _application(status: DriverApplicationStatus.rejected),
          documents: [
            _document(DriverDocumentType.driverLicense),
            _document(
              DriverDocumentType.soat,
              status: DriverDocumentStatus.rejected,
              rejectionReason: 'SOAT vencido',
            ),
            _document(DriverDocumentType.vehicleRegistration),
          ],
        );

        final freshState = _correctionsState(
          application: _application(status: DriverApplicationStatus.rejected),
        );

        final authRepository = _FakeAuthRepository(resolvedState: freshState);

        await _pumpScreenWithGoBackDocuments(
          tester,
          authRepository: authRepository,
          initialState: initial,
          freshStateAfterCorrection: freshState,
        );

        final correctButton = find.byKey(
          const Key('corrections-soat-correct-button'),
        );
        await tester.ensureVisible(correctButton);
        await tester.tap(correctButton);
        await tester.pumpAndSettle();

        expect(find.text('DOCUMENTS_ROUTE_GOBACK'), findsOneWidget);

        await tester.tap(find.byKey(const Key('fake-go-continue-button')));
        await tester.pumpAndSettle();

        expect(find.text('Correcciones requeridas'), findsOneWidget);
        expect(find.text('Sin observaciones'), findsNWidgets(5));

        final button = tester.widget<FilledButton>(
          find.byKey(const Key('corrections-resend-button')),
        );
        expect(
          button.onPressed,
          isNotNull,
          reason:
              'El CTA debe habilitarse inmediatamente al volver, sin '
              'necesitar reiniciar la app.',
        );
      },
    );
  });

  group('DriverOnboardingCorrectionsScreen — navegación', () {
    testWidgets('el botón de volver cierra sesión y navega a Login', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        resolvedState: _correctionsState(),
      );
      await _pumpScreen(
        tester,
        authRepository: authRepository,
        initialState: _correctionsState(),
      );

      await tester.tap(find.byKey(const Key('corrections-back-button')));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCalls, 1);
      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });
  });
}

DriverOnboardingDocumentsScreenArgs? _lastDocumentsArgs;

DioException _dioError(int? statusCode) {
  final request = RequestOptions(path: 'drivers/me');

  return DioException(
    requestOptions: request,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: request, statusCode: statusCode),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  DriverSessionState? initialState,
  _FakeAuthRepository? authRepository,
}) async {
  _lastDocumentsArgs = null;

  final router = GoRouter(
    initialLocation: DriverOnboardingRoutes.corrections,
    routes: [
      GoRoute(
        path: DriverOnboardingRoutes.corrections,
        builder: (context, state) => DriverOnboardingCorrectionsScreen(
          initialState: state.extra as DriverSessionState? ?? initialState,
        ),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.aboutYou,
        builder: (context, state) =>
            const _FakeSubScreen(label: 'ABOUT_YOU_ROUTE'),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.vehicle,
        builder: (context, state) =>
            const _FakeSubScreen(label: 'VEHICLE_ROUTE'),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.documents,
        builder: (context, state) {
          _lastDocumentsArgs =
              state.extra as DriverOnboardingDocumentsScreenArgs?;
          return const _FakeSubScreen(label: 'DOCUMENTS_ROUTE');
        },
      ),
      GoRoute(
        path: DriverOnboardingRoutes.review,
        builder: (context, state) =>
            const Scaffold(body: Text('SUBMIT_REVIEW_ROUTE')),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          authRepository ?? _FakeAuthRepository(resolvedState: initialState),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// `DRIVER-ONBOARDING-R3.8.2`: variante de [_pumpScreen] donde la ruta
/// `documents` NO hace un `Navigator.pop()` simple al volver — en vez
/// de eso, reproduce EXACTAMENTE lo que hace el botón "Continuar" real
/// de `DriverOnboardingDocumentsScreen._continue()`:
/// `goToDriverSessionRoute(context, freshState)`, es decir
/// `context.go(...)`, nunca un pop imperativo. Esto es lo que el caso
/// físico reportado por JuanJo realmente ejercita — el helper
/// `_pumpScreen` (con `_FakeSubScreen`, que sí usa `pop()`) no lo
/// reproducía.
Future<void> _pumpScreenWithGoBackDocuments(
  WidgetTester tester, {
  required DriverSessionState initialState,
  required DriverSessionState freshStateAfterCorrection,
  _FakeAuthRepository? authRepository,
}) async {
  final router = GoRouter(
    initialLocation: DriverOnboardingRoutes.corrections,
    routes: [
      GoRoute(
        path: DriverOnboardingRoutes.corrections,
        builder: (context, state) => DriverOnboardingCorrectionsScreen(
          initialState: state.extra as DriverSessionState? ?? initialState,
        ),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.documents,
        builder: (context, state) =>
            _FakeGoBackSubScreen(freshState: freshStateAfterCorrection),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.review,
        builder: (context, state) =>
            const Scaffold(body: Text('SUBMIT_REVIEW_ROUTE')),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          authRepository ?? _FakeAuthRepository(resolvedState: initialState),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _FakeGoBackSubScreen extends StatelessWidget {
  const _FakeGoBackSubScreen({required this.freshState});

  final DriverSessionState freshState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DOCUMENTS_ROUTE_GOBACK'),
            TextButton(
              key: const Key('fake-go-continue-button'),
              onPressed: () => goToDriverSessionRoute(context, freshState),
              child: const Text('continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pantalla mínima empujada por cada "Corregir" — solo necesita un
/// botón para volver (`context.pop()`), que es lo único que
/// `DriverOnboardingCorrectionsScreen` necesita observar para volver a
/// cargar el estado al regresar.
class _FakeSubScreen extends StatelessWidget {
  const _FakeSubScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            TextButton(
              key: const Key('fake-back-button'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    this.resolvedState,
    this.resolveSessionStateError,
    this.completer,
  }) : super(Dio(), const FlutterSecureStorage());

  DriverSessionState? resolvedState;
  Object? resolveSessionStateError;
  Completer<DriverSessionState>? completer;

  int resolveSessionStateCalls = 0;
  int logoutCalls = 0;

  @override
  Future<DriverSessionState> resolveSessionState() async {
    resolveSessionStateCalls += 1;

    if (completer != null) {
      return completer!.future;
    }

    if (resolveSessionStateError case final e?) {
      throw e;
    }

    return resolvedState!;
  }

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }
}
