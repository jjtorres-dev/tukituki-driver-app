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
import 'package:driver/features/driver/data/driver_profile_repository.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/domain/driver_document.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_progress.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_submit_review_screen.dart';

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
  String firstName = 'Rocio',
  String lastName = 'Alegre',
  String? email = 'rocio@example.com',
  String? photoUrl = 'https://cdn.example.com/rocio.jpg',
  DriverApplicationStatus status = DriverApplicationStatus.draft,
}) {
  return DriverApplication(
    id: 'profile-1',
    userId: 'user-1',
    firstName: firstName,
    lastName: lastName,
    status: status,
    documentType: IdentityDocumentType.dni,
    documentNumber: '76751234',
    birthDate: '1990-03-25',
    email: email,
    photoUrl: photoUrl,
  );
}

DriverVehicle _vehicle() {
  return const DriverVehicle(
    id: 'vehicle-1',
    driverProfileId: 'profile-1',
    plate: 'J-2637',
    brand: 'Honda',
    model: 'Mototaxi',
    year: 2022,
    color: 'Azul',
    ownership: VehicleOwnership.owned,
    status: VehicleStatus.draft,
  );
}

DriverDocument _completeDocument(DriverDocumentType type) {
  final needsExpiresAt =
      type == DriverDocumentType.driverLicense ||
      type == DriverDocumentType.soat;

  return DriverDocument(
    id: 'document-${type.value}',
    driverProfileId: 'profile-1',
    type: type,
    status: DriverDocumentStatus.draft,
    fileObjectKey: 'drivers/profile-1/documents/${type.value}.jpg',
    documentNumber: 'ABC123',
    issuedAt: '2024-01-01',
    expiresAt: needsExpiresAt ? '2030-06-15' : null,
  );
}

List<DriverDocument> _allCompleteDocuments() {
  return requiredDriverOnboardingDocumentTypes.map(_completeDocument).toList();
}

DriverSessionState _completeState({
  DriverApplication? application,
  DriverVehicle? vehicle,
  List<DriverDocument>? documents,
}) {
  return DriverSessionState(
    kind: DriverSessionKind.draftDocumentsComplete,
    user: _user(),
    application: application ?? _application(),
    vehicle: vehicle ?? _vehicle(),
    documents: documents ?? _allCompleteDocuments(),
  );
}

/// Estado de reenvío tras corrección (`DRIVER-ONBOARDING-R3.8`): mismo
/// shape que [_completeState] pero `kind: correctionsRequired` y sin
/// ninguna observación pendiente por defecto (`_vehicle()`/
/// `_allCompleteDocuments()` ya no tienen ningún `status: rejected`,
/// y `_application()` no trae `rejectionReason`).
DriverSessionState _resubmissionState({
  DriverApplication? application,
  DriverVehicle? vehicle,
  List<DriverDocument>? documents,
}) {
  return DriverSessionState(
    kind: DriverSessionKind.correctionsRequired,
    user: _user(),
    application: application ?? _application(),
    vehicle: vehicle ?? _vehicle(),
    documents: documents ?? _allCompleteDocuments(),
  );
}

DioException _dioError({
  int? statusCode,
  Object? data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  final request = RequestOptions(path: 'drivers/me/submit');

  return DioException(
    requestOptions: request,
    type: type,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: request,
            statusCode: statusCode,
            data: data,
          ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriverOnboardingSubmitReviewScreen — render', () {
    testWidgets('A. renderiza el título y progress Paso 5 actual', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.text('Revisar y enviar'), findsOneWidget);
      final progress = tester.widget<DriverOnboardingProgress>(
        find.byType(DriverOnboardingProgress),
      );
      expect(progress.currentStep, 5);
    });

    testWidgets('C/E/G. muestra DNI completo, sin enmascarar', (tester) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.text('76751234'), findsOneWidget);
    });

    testWidgets('F. fecha de nacimiento en DD/MM/YYYY', (tester) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.text('25/03/1990'), findsOneWidget);
    });

    testWidgets('H. email ausente muestra "No registrado"', (tester) async {
      await _pumpScreen(
        tester,
        initialState: _completeState(application: _application(email: null)),
      );

      expect(find.text('No registrado'), findsOneWidget);
    });

    testWidgets('J/K. ownership humano: OWNED→Propio, RENTED→Alquilado', (
      tester,
    ) async {
      await _pumpScreen(
        tester,
        initialState: _completeState(
          vehicle: DriverVehicle(
            id: 'vehicle-1',
            driverProfileId: 'profile-1',
            plate: 'J-2637',
            brand: 'Honda',
            model: 'Mototaxi',
            year: 2022,
            color: 'Azul',
            ownership: VehicleOwnership.rented,
            status: VehicleStatus.draft,
          ),
        ),
      );

      expect(find.text('Alquilado'), findsOneWidget);
      expect(find.text('Propio'), findsNothing);
    });

    testWidgets('L/M. engineNumber/chassisNumber/vehicleType no visibles', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.textContaining('engineNumber'), findsNothing);
      expect(find.textContaining('chassisNumber'), findsNothing);
      expect(find.text('MOTOTAXI'), findsNothing);
      expect(find.text('vehicle-1'), findsNothing);
    });

    testWidgets(
      'P/Q/R. documentos: Licencia/SOAT con vencimiento, TIV solo número',
      (tester) async {
        await _pumpScreen(tester, initialState: _completeState());

        expect(find.text('N.º ABC123 · vence 15/06/2030'), findsNWidgets(2));
        expect(find.text('N.º ABC123'), findsOneWidget);
      },
    );

    testWidgets('S/T. issuedAt/objectKey/fileUrl nunca visibles', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.textContaining('2024-01-01'), findsNothing);
      expect(find.textContaining('objectKey'), findsNothing);
      expect(find.textContaining('drivers/profile-1'), findsNothing);
    });

    testWidgets('U. no ofrece "Ver documento"', (tester) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(find.textContaining('Ver documento'), findsNothing);
    });
  });

  group('DriverOnboardingSubmitReviewScreen — fallback de estado', () {
    testWidgets(
      'sin initialState, resuelve la sesión y renderiza con los datos '
      'frescos',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          resolvedState: _completeState(),
        );
        await _pumpScreen(tester, authRepository: authRepository);

        expect(authRepository.resolveSessionStateCalls, 1);
        expect(find.text('Revisar y enviar'), findsOneWidget);
      },
    );

    testWidgets('BA/BB. si el estado fresco ya no es draftDocumentsComplete, '
        'navega a donde corresponda (p.ej. documentos incompletos)', (
      tester,
    ) async {
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
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
    });

    testWidgets('error de carga muestra Reintentar', (tester) async {
      final authRepository = _FakeAuthRepository(
        resolveSessionStateError: _dioError(statusCode: 500),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.byKey(const Key('review-load-error')), findsOneWidget);
    });
  });

  group('DriverOnboardingSubmitReviewScreen — Editar', () {
    testWidgets('editar Sobre ti navega a about-you con el profile', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _completeState());

      final button = find.byKey(const Key('review-profile-edit-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('ABOUT_YOU_ROUTE'), findsOneWidget);
    });

    testWidgets('editar Tu mototaxi navega a vehicle con el vehículo', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _completeState());

      final button = find.byKey(const Key('review-vehicle-edit-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
    });

    testWidgets('editar Tus documentos navega a documents', (tester) async {
      await _pumpScreen(tester, initialState: _completeState());

      final button = find.byKey(const Key('review-documents-edit-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
    });
  });

  group('DriverOnboardingSubmitReviewScreen — confirmación y submit', () {
    testWidgets(
      'AI/AJ. tocar "Enviar solicitud" abre modal; Cancelar no hace POST',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository();
        await _pumpScreen(
          tester,
          initialState: _completeState(),
          profileRepository: profileRepository,
        );

        final submitButton = find.byKey(const Key('review-submit-button'));
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();

        expect(find.text('¿Enviar tu solicitud?'), findsOneWidget);

        await tester.tap(find.byKey(const Key('review-confirm-cancel-button')));
        await tester.pumpAndSettle();

        expect(profileRepository.submitCalls, 0);
      },
    );

    testWidgets('AL. confirmar hace exactamente un POST /drivers/me/submit', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(profileRepository.submitCalls, 1);
    });

    testWidgets('AN/AO. submit 200 PENDING_REVIEW navega a review-status', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(find.text('REVIEW_STATUS_ROUTE'), findsOneWidget);
    });

    testWidgets('AM. doble tap solo produce un submit', (tester) async {
      final completer = Completer<DriverApplication>();
      final profileRepository = _FakeDriverProfileRepository(
        completer: completer,
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      final submitButton = find.byKey(const Key('review-submit-button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-confirm-submit-button')));
      await tester.pump();

      await tester.tap(submitButton, warnIfMissed: false);
      await tester.pump();

      expect(profileRepository.submitCalls, 1);

      completer.complete(
        _application(status: DriverApplicationStatus.pendingReview),
      );
      await tester.pumpAndSettle();
    });
  });

  group('DriverOnboardingSubmitReviewScreen — errores de submit', () {
    testWidgets('AU. DRIVER_PROFILE_PHOTO missing ofrece revisar Sobre ti', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(
          statusCode: 400,
          data: {
            'message': 'La solicitud está incompleta',
            'missingRequirements': ['DRIVER_PROFILE_PHOTO'],
          },
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text('Falta información en tus datos personales.'),
        findsOneWidget,
      );
      expect(find.text('Revisar datos personales'), findsOneWidget);
    });

    testWidgets('AY. DRIVER_LICENSE_EXPIRED muestra mensaje específico', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(
          statusCode: 400,
          data: {
            'message': 'La solicitud contiene requisitos inválidos',
            'invalidRequirements': ['DRIVER_LICENSE_EXPIRED'],
          },
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text(
          'Tu licencia de conducir venció. Actualízala antes de enviar '
          'tu solicitud.',
        ),
        findsOneWidget,
      );
      expect(find.text('Revisar documentos'), findsOneWidget);
    });

    testWidgets('AX. SOAT_EXPIRED muestra mensaje específico', (tester) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(
          statusCode: 400,
          data: {
            'invalidRequirements': ['SOAT_EXPIRED'],
          },
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text('Tu SOAT venció. Actualízalo antes de enviar tu solicitud.'),
        findsOneWidget,
      );
    });

    testWidgets('AZ. otro invalidRequirement de documento: mensaje genérico', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(
          statusCode: 400,
          data: {
            'invalidRequirements': ['VEHICLE_REGISTRATION_INCOMPLETE'],
          },
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text('Revisa tus documentos antes de enviar la solicitud.'),
        findsOneWidget,
      );
    });

    testWidgets('51. error desconocido: mensaje genérico, sin JSON crudo', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(statusCode: 403),
      );
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(),
        getDriverProfileResult: _application(),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text(
          'No pudimos confirmar el envío de tu solicitud. '
          'Revisa tu conexión e inténtalo nuevamente.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('403'), findsNothing);
    });

    testWidgets('45. 401 limpia sesión y navega a Login', (tester) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(statusCode: 401),
      );
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(authRepository.clearSessionCalls, 1);
      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });
  });

  group('DriverOnboardingSubmitReviewScreen — recovery de red', () {
    testWidgets('AQ. network error + GET=PENDING_REVIEW → éxito', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(type: DioExceptionType.connectionError),
      );
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(),
        getDriverProfileResult: _application(
          status: DriverApplicationStatus.pendingReview,
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(find.text('REVIEW_STATUS_ROUTE'), findsOneWidget);
    });

    testWidgets('AR. network error + GET=DRAFT → permanece, mensaje amigable', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(type: DioExceptionType.connectionError),
      );
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(),
        getDriverProfileResult: _application(),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(find.text('Revisar y enviar'), findsOneWidget);
      expect(
        find.text(
          'No pudimos confirmar el envío de tu solicitud. '
          'Revisa tu conexión e inténtalo nuevamente.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'AS. 400 sin arrays (ya pending, carrera) + GET=PENDING_REVIEW → '
      'éxito',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository(
          error: _dioError(
            statusCode: 400,
            data: {'message': 'La solicitud no puede enviarse a revisión'},
          ),
        );
        final authRepository = _FakeAuthRepository(
          resolvedState: _completeState(),
          getDriverProfileResult: _application(
            status: DriverApplicationStatus.pendingReview,
          ),
        );
        await _pumpScreen(
          tester,
          initialState: _completeState(),
          profileRepository: profileRepository,
          authRepository: authRepository,
        );

        await _confirmSubmit(tester);

        expect(find.text('REVIEW_STATUS_ROUTE'), findsOneWidget);
      },
    );

    testWidgets('AT. network error y el GET de recovery también falla: mensaje '
        'de incertidumbre, sin asumir éxito ni fracaso definitivo', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(type: DioExceptionType.connectionError),
      );
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(),
        getDriverProfileError: _dioError(
          type: DioExceptionType.connectionError,
        ),
      );
      await _pumpScreen(
        tester,
        initialState: _completeState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(
        find.text(
          'No pudimos confirmar el envío de tu solicitud. '
          'Revisa tu conexión e inténtalo nuevamente.',
        ),
        findsOneWidget,
      );
      expect(find.text('REVIEW_STATUS_ROUTE'), findsNothing);
    });
  });

  group('DriverOnboardingSubmitReviewScreen — refresh tras edición '
      '(DRIVER-ONBOARDING-R3.7.2, hotfix stale state)', () {
    testWidgets('PROFILE: tras editar y volver, Review muestra el firstName '
        'fresco de resolveSessionState(), no el original con el que se '
        'abrió', (tester) async {
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(
          application: _application(firstName: 'Rociooo'),
        ),
      );

      await _pumpEditRefreshScenario(
        tester,
        authRepository: authRepository,
        editRoute: DriverOnboardingRoutes.aboutYou,
        editButtonKey: 'review-profile-edit-button',
      );

      expect(find.text('Rociooo Alegre'), findsOneWidget);
      expect(find.text('Rocio Alegre'), findsNothing);
    });

    testWidgets(
      'VEHICLE: tras editar y volver, Review muestra el color fresco',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          resolvedState: _completeState(
            vehicle: DriverVehicle(
              id: 'vehicle-1',
              driverProfileId: 'profile-1',
              plate: 'J-2637',
              brand: 'Honda',
              model: 'Mototaxi',
              year: 2022,
              color: 'Rojo',
              ownership: VehicleOwnership.owned,
              status: VehicleStatus.draft,
            ),
          ),
        );

        await _pumpEditRefreshScenario(
          tester,
          authRepository: authRepository,
          editRoute: DriverOnboardingRoutes.vehicle,
          editButtonKey: 'review-vehicle-edit-button',
        );

        expect(find.text('Rojo'), findsOneWidget);
        expect(find.text('Azul'), findsNothing);
      },
    );

    testWidgets('DOCUMENTS: tras editar y volver, Review muestra el número de '
        'documento fresco', (tester) async {
      final authRepository = _FakeAuthRepository(
        resolvedState: _completeState(
          documents: requiredDriverOnboardingDocumentTypes.map((type) {
            final needsExpiresAt =
                type == DriverDocumentType.driverLicense ||
                type == DriverDocumentType.soat;

            return DriverDocument(
              id: 'document-${type.value}',
              driverProfileId: 'profile-1',
              type: type,
              status: DriverDocumentStatus.draft,
              fileObjectKey: 'drivers/profile-1/documents/${type.value}.jpg',
              documentNumber: 'XYZ789',
              issuedAt: '2024-01-01',
              expiresAt: needsExpiresAt ? '2030-06-15' : null,
            );
          }).toList(),
        ),
      );

      await _pumpEditRefreshScenario(
        tester,
        authRepository: authRepository,
        editRoute: DriverOnboardingRoutes.documents,
        editButtonKey: 'review-documents-edit-button',
      );

      expect(find.textContaining('XYZ789'), findsNWidgets(3));
      expect(find.textContaining('ABC123'), findsNothing);
    });

    testWidgets(
      'entrada normal (Splash-style, initialState draftDocumentsComplete '
      'ya resuelto) sigue sin ejecutar resolveSessionState',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          resolvedState: _completeState(),
        );
        await _pumpScreen(
          tester,
          initialState: _completeState(),
          authRepository: authRepository,
        );

        expect(authRepository.resolveSessionStateCalls, 0);
      },
    );
  });

  group('DriverOnboardingSubmitReviewScreen — modo reenvío '
      '(DRIVER-ONBOARDING-R3.8)', () {
    testWidgets('correctionsRequired sin observaciones pendientes muestra '
        '"Revisar y reenviar" y "Reenviar solicitud", sin botones Editar', (
      tester,
    ) async {
      await _pumpScreen(tester, initialState: _resubmissionState());

      expect(find.text('Revisar y reenviar'), findsOneWidget);
      expect(find.text('Revisar y enviar'), findsNothing);
      expect(find.text('Reenviar solicitud'), findsOneWidget);
      expect(find.text('Enviar solicitud'), findsNothing);

      expect(find.byKey(const Key('review-profile-edit-button')), findsNothing);
      expect(find.byKey(const Key('review-vehicle-edit-button')), findsNothing);
      expect(
        find.byKey(const Key('review-documents-edit-button')),
        findsNothing,
      );
    });

    testWidgets('draftDocumentsComplete (envío inicial) sí muestra los botones '
        'Editar — el modo reenvío no afecta el flujo normal', (tester) async {
      await _pumpScreen(tester, initialState: _completeState());

      expect(
        find.byKey(const Key('review-profile-edit-button')),
        findsOneWidget,
      );
    });

    testWidgets('confirmar reenvío muestra "¿Reenviar tu solicitud?" y hace '
        'POST /drivers/me/submit igual que un envío inicial', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(
        tester,
        initialState: _resubmissionState(),
        profileRepository: profileRepository,
      );

      final submitButton = find.byKey(const Key('review-submit-button'));
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(find.text('¿Reenviar tu solicitud?'), findsOneWidget);
      expect(find.text('¿Enviar tu solicitud?'), findsNothing);

      await tester.tap(find.byKey(const Key('review-confirm-submit-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      expect(profileRepository.submitCalls, 1);
    });

    testWidgets('reenvío exitoso limpia el contexto de reenvío local y navega '
        'a review-status', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      final authRepository = _FakeAuthRepository();
      await _pumpScreen(
        tester,
        initialState: _resubmissionState(),
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _confirmSubmit(tester);

      expect(find.text('REVIEW_STATUS_ROUTE'), findsOneWidget);
      expect(authRepository.clearResubmissionContextCalls, 1);
      expect(authRepository.lastClearResubmissionContextUserId, 'user-1');
    });

    testWidgets(
      'envío inicial exitoso también limpia el marcador (idempotente, '
      'no debería quedar activo por error)',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository();
        final authRepository = _FakeAuthRepository();
        await _pumpScreen(
          tester,
          initialState: _completeState(),
          profileRepository: profileRepository,
          authRepository: authRepository,
        );

        await _confirmSubmit(tester);

        expect(authRepository.clearResubmissionContextCalls, 1);
      },
    );

    testWidgets('correctionsRequired CON observaciones pendientes nunca es '
        'usable — el gate de reenvío (decisión E) no depende de '
        'confiar en el extra recibido', (tester) async {
      final stillPending = _resubmissionState(
        application: _application(),
        vehicle: DriverVehicle(
          id: 'vehicle-1',
          driverProfileId: 'profile-1',
          plate: 'J-2637',
          brand: 'Honda',
          model: 'Mototaxi',
          year: 2022,
          color: 'Azul',
          ownership: VehicleOwnership.owned,
          status: VehicleStatus.rejected,
        ),
      );

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
        initialState: stillPending,
        authRepository: authRepository,
      );

      expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
      expect(find.text('Revisar y reenviar'), findsNothing);
    });
  });
}

Future<void> _confirmSubmit(WidgetTester tester) async {
  final submitButton = find.byKey(const Key('review-submit-button'));
  await tester.ensureVisible(submitButton);
  await tester.tap(submitButton);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('review-confirm-submit-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

/// Reproduce el flujo físico real de edición desde Revisar y enviar:
/// Review (`_editProfile`/`_editVehicle`/`_editDocuments`) empuja la
/// pantalla de edición con `context.push`; al "guardar" exitosamente,
/// las pantallas reales de edición (`DriverOnboardingAboutYouScreen`/
/// `DriverOnboardingVehicleScreen`/`DriverOnboardingDocumentsScreen`)
/// hacen `resolveSessionState()` + `goToDriverSessionRoute()` — nunca
/// `context.pop()`. `_FakeEditScreen` imita exactamente esa segunda
/// mitad sin necesitar las pantallas reales completas (que ya tienen
/// su propia cobertura en sus respectivos archivos de test).
Future<void> _pumpEditRefreshScenario(
  WidgetTester tester, {
  required _FakeAuthRepository authRepository,
  required String editRoute,
  required String editButtonKey,
}) async {
  final staleState = _completeState();

  final router = GoRouter(
    initialLocation: DriverOnboardingRoutes.review,
    routes: [
      GoRoute(
        path: DriverOnboardingRoutes.review,
        builder: (context, state) => DriverOnboardingSubmitReviewScreen(
          initialState: state.extra as DriverSessionState? ?? staleState,
        ),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.aboutYou,
        builder: (context, state) => const _FakeEditScreen(),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.vehicle,
        builder: (context, state) => const _FakeEditScreen(),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.documents,
        builder: (context, state) => const _FakeEditScreen(),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.login,
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: DriverOnboardingRoutes.reviewStatus,
        builder: (context, state) =>
            const Scaffold(body: Text('REVIEW_STATUS_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepository),
        driverProfileRepositoryProvider.overrideWithValue(
          _FakeDriverProfileRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();

  final editButton = find.byKey(Key(editButtonKey));
  await tester.ensureVisible(editButton);
  await tester.tap(editButton);
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('fake-edit-save-button')));
  await tester.pumpAndSettle();
}

class _FakeEditScreen extends ConsumerWidget {
  const _FakeEditScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('fake-edit-save-button'),
          onPressed: () async {
            final authRepository = ref.read(authRepositoryProvider);
            final freshState = await authRepository.resolveSessionState();

            if (context.mounted) {
              goToDriverSessionRoute(context, freshState);
            }
          },
          child: const Text('save'),
        ),
      ),
    );
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  DriverSessionState? initialState,
  _FakeAuthRepository? authRepository,
  _FakeDriverProfileRepository? profileRepository,
}) async {
  final router = GoRouter(
    initialLocation: '/onboarding/review',
    routes: [
      GoRoute(
        path: '/onboarding/review',
        builder: (context, state) =>
            DriverOnboardingSubmitReviewScreen(initialState: initialState),
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
        path: '/onboarding/review-status',
        builder: (context, state) =>
            const Scaffold(body: Text('REVIEW_STATUS_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          authRepository ?? _FakeAuthRepository(),
        ),
        driverProfileRepositoryProvider.overrideWithValue(
          profileRepository ?? _FakeDriverProfileRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    this.resolvedState,
    this.resolveSessionStateError,
    this.getDriverProfileResult,
    this.getDriverProfileError,
  }) : super(Dio(), const FlutterSecureStorage());

  DriverSessionState? resolvedState;
  Object? resolveSessionStateError;
  DriverApplication? getDriverProfileResult;
  Object? getDriverProfileError;

  int resolveSessionStateCalls = 0;
  int getDriverProfileCalls = 0;
  int clearSessionCalls = 0;
  int clearResubmissionContextCalls = 0;
  String? lastClearResubmissionContextUserId;

  @override
  Future<DriverSessionState> resolveSessionState() async {
    resolveSessionStateCalls += 1;

    if (resolveSessionStateError case final e?) {
      throw e;
    }

    return resolvedState!;
  }

  @override
  Future<DriverApplication?> getDriverProfile() async {
    getDriverProfileCalls += 1;

    if (getDriverProfileError case final e?) {
      throw e;
    }

    return getDriverProfileResult;
  }

  @override
  Future<void> clearSession() async {
    clearSessionCalls += 1;
  }

  @override
  Future<void> clearResubmissionContext({required String userId}) async {
    clearResubmissionContextCalls += 1;
    lastClearResubmissionContextUserId = userId;
  }
}

class _FakeDriverProfileRepository extends DriverProfileRepository {
  _FakeDriverProfileRepository({this.error, this.completer}) : super(Dio());

  Object? error;
  Completer<DriverApplication>? completer;

  int submitCalls = 0;

  @override
  Future<DriverApplication> submitApplication() async {
    submitCalls += 1;

    if (completer != null) {
      return completer!.future;
    }

    if (error case final e?) {
      throw e;
    }

    return _application(status: DriverApplicationStatus.pendingReview);
  }
}
