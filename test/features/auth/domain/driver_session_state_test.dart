import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/domain/driver_document.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';

AuthenticatedUser _user({
  List<String> roles = const ['PASSENGER'],
  bool isPhoneVerified = true,
}) {
  return AuthenticatedUser(
    id: 'user-1',
    phoneE164: '+51987654321',
    roles: roles,
    status: 'ACTIVE',
    isPhoneVerified: isPhoneVerified,
  );
}

DriverApplication _application(DriverApplicationStatus status) {
  return DriverApplication(
    id: 'profile-1',
    userId: 'user-1',
    firstName: 'Juan',
    lastName: 'Torres',
    status: status,
  );
}

DriverVehicle _vehicle() {
  return const DriverVehicle(
    id: 'vehicle-1',
    driverProfileId: 'profile-1',
    plate: '1234-AB',
    brand: 'Bajaj',
    model: 'RE 4S',
    year: 2024,
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
    expiresAt: needsExpiresAt ? '2030-01-01' : null,
  );
}

List<DriverDocument> _allCompleteDocuments() {
  return requiredDriverOnboardingDocumentTypes.map(_completeDocument).toList();
}

void main() {
  group('resolveDriverApplicationState', () {
    test(
      'MVP: isPhoneVerified=false NO bloquea el routing (OTP diferido, '
      'DRIVER-ONBOARDING-R3.3) — application null → noProfile igual que verificado',
      () {
        final state = resolveDriverApplicationState(
          user: _user(isPhoneVerified: false),
          application: null,
        );

        expect(state.kind, DriverSessionKind.noProfile);
      },
    );

    test(
      'MVP: isPhoneVerified=false + DRAFT sin vehículo → draftNoVehicle',
      () {
        final state = resolveDriverApplicationState(
          user: _user(isPhoneVerified: false),
          application: _application(DriverApplicationStatus.draft),
        );

        expect(state.kind, DriverSessionKind.draftNoVehicle);
      },
    );

    test('MVP: isPhoneVerified=false + PENDING_REVIEW → pendingReview', () {
      final state = resolveDriverApplicationState(
        user: _user(isPhoneVerified: false),
        application: _application(DriverApplicationStatus.pendingReview),
      );

      expect(state.kind, DriverSessionKind.pendingReview);
    });

    test('MVP: isPhoneVerified=false + APPROVED + rol DRIVER → approved', () {
      final state = resolveDriverApplicationState(
        user: _user(isPhoneVerified: false, roles: const ['DRIVER']),
        application: _application(DriverApplicationStatus.approved),
      );

      expect(state.kind, DriverSessionKind.approved);
    });

    test('application null (404) → noProfile', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: null,
      );

      expect(state.kind, DriverSessionKind.noProfile);
    });

    test('DRAFT sin vehículo (vehicle: null) → draftNoVehicle', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
      );

      expect(state.kind, DriverSessionKind.draftNoVehicle);
      expect(state.vehicle, isNull);
    });

    test('DRAFT con vehículo y sin documentos (documents: null) → '
        'draftDocumentsIncomplete, conserva el vehicle', () {
      final vehicle = _vehicle();

      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: vehicle,
      );

      expect(state.kind, DriverSessionKind.draftDocumentsIncomplete);
      expect(state.vehicle, same(vehicle));
      expect(state.documents, isNull);
    });

    test('DRAFT con vehículo y documentos vacíos (lista []) → '
        'draftDocumentsIncomplete', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: _vehicle(),
        documents: const [],
      );

      expect(state.kind, DriverSessionKind.draftDocumentsIncomplete);
    });

    test('DRAFT con vehículo y solo 2 de los 3 documentos completos → '
        'draftDocumentsIncomplete', () {
      final documents = [
        _completeDocument(DriverDocumentType.driverLicense),
        _completeDocument(DriverDocumentType.soat),
      ];

      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: _vehicle(),
        documents: documents,
      );

      expect(state.kind, DriverSessionKind.draftDocumentsIncomplete);
    });

    test('DRAFT con vehículo y un documento requerido incompleto (sin '
        'documentNumber) → draftDocumentsIncomplete', () {
      final documents = [
        _completeDocument(DriverDocumentType.driverLicense),
        _completeDocument(DriverDocumentType.soat),
        DriverDocument(
          id: 'document-vehicle-registration',
          driverProfileId: 'profile-1',
          type: DriverDocumentType.vehicleRegistration,
          status: DriverDocumentStatus.draft,
          fileObjectKey: 'drivers/profile-1/documents/tiv.jpg',
        ),
      ];

      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: _vehicle(),
        documents: documents,
      );

      expect(state.kind, DriverSessionKind.draftDocumentsIncomplete);
    });

    test('DRAFT con vehículo y los 3 documentos requeridos completos → '
        'draftDocumentsComplete, conserva vehicle y documents', () {
      final vehicle = _vehicle();
      final documents = _allCompleteDocuments();

      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: vehicle,
        documents: documents,
      );

      expect(state.kind, DriverSessionKind.draftDocumentsComplete);
      expect(state.vehicle, same(vehicle));
      expect(state.documents, same(documents));
    });

    test(
      'vehicle se ignora fuera de DRAFT (p.ej. PENDING_REVIEW no lo necesita)',
      () {
        final state = resolveDriverApplicationState(
          user: _user(),
          application: _application(DriverApplicationStatus.pendingReview),
          vehicle: _vehicle(),
        );

        expect(state.kind, DriverSessionKind.pendingReview);
      },
    );

    test('REJECTED → rejected', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.rejected),
      );

      expect(state.kind, DriverSessionKind.rejected);
    });

    test('PENDING_REVIEW → pendingReview', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.pendingReview),
      );

      expect(state.kind, DriverSessionKind.pendingReview);
    });

    test('SUSPENDED → suspended', () {
      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.suspended),
      );

      expect(state.kind, DriverSessionKind.suspended);
    });

    test('APPROVED + rol DRIVER → approved (único caso que entra a Home)', () {
      final state = resolveDriverApplicationState(
        user: _user(roles: const ['PASSENGER', 'DRIVER']),
        application: _application(DriverApplicationStatus.approved),
      );

      expect(state.kind, DriverSessionKind.approved);
    });

    test('APPROVED sin rol DRIVER → approvedRoleMismatch, nunca approved', () {
      final state = resolveDriverApplicationState(
        user: _user(roles: const ['PASSENGER']),
        application: _application(DriverApplicationStatus.approved),
      );

      expect(state.kind, DriverSessionKind.approvedRoleMismatch);
    });

    test('status desconocido → unknownApplicationStatus, nunca a Home', () {
      final state = resolveDriverApplicationState(
        user: _user(roles: const ['PASSENGER', 'DRIVER']),
        application: _application(DriverApplicationStatus.unknown),
      );

      expect(state.kind, DriverSessionKind.unknownApplicationStatus);
    });

    test('el resultado conserva la application original', () {
      final application = _application(DriverApplicationStatus.pendingReview);

      final state = resolveDriverApplicationState(
        user: _user(),
        application: application,
      );

      expect(state.application, same(application));
      expect(state.user.id, 'user-1');
    });
  });
}
