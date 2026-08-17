import 'package:flutter_test/flutter_test.dart';

import 'package:driver/core/router/driver_onboarding_routes.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';

void main() {
  group('routeForDriverSessionKind', () {
    test('mapea cada DriverSessionKind exactamente a un path', () {
      expect(
        routeForDriverSessionKind(DriverSessionKind.noProfile),
        DriverOnboardingRoutes.aboutYou,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.draft),
        DriverOnboardingRoutes.start,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.rejected),
        DriverOnboardingRoutes.rejected,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.pendingReview),
        DriverOnboardingRoutes.reviewStatus,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.approved),
        DriverOnboardingRoutes.home,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.suspended),
        DriverOnboardingRoutes.suspended,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.approvedRoleMismatch),
        DriverOnboardingRoutes.stateError,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.unknownApplicationStatus),
        DriverOnboardingRoutes.stateError,
      );
    });

    test('noProfile va al formulario real de Sobre ti; draft a la foundation '
        '(DRIVER-ONBOARDING-R3.4: ya no comparten pantalla)', () {
      expect(
        routeForDriverSessionKind(DriverSessionKind.noProfile),
        isNot(routeForDriverSessionKind(DriverSessionKind.draft)),
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.noProfile),
        DriverOnboardingRoutes.aboutYou,
      );
      expect(
        routeForDriverSessionKind(DriverSessionKind.draft),
        DriverOnboardingRoutes.start,
      );
    });

    test('approved es el único kind que enruta a Home', () {
      for (final kind in DriverSessionKind.values) {
        final route = routeForDriverSessionKind(kind);

        if (kind == DriverSessionKind.approved) {
          expect(route, DriverOnboardingRoutes.home);
        } else {
          expect(route, isNot(DriverOnboardingRoutes.home));
        }
      }
    });
  });
}
