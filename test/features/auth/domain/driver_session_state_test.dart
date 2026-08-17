import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
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

    test('DRAFT con vehículo → draftWithVehicle, conserva el vehicle', () {
      final vehicle = _vehicle();

      final state = resolveDriverApplicationState(
        user: _user(),
        application: _application(DriverApplicationStatus.draft),
        vehicle: vehicle,
      );

      expect(state.kind, DriverSessionKind.draftWithVehicle);
      expect(state.vehicle, same(vehicle));
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
