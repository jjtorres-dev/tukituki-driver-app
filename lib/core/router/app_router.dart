import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/driver_session_state.dart';
import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/auth/presentation/driver_splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/driver/domain/driver_application.dart';
import '../../features/driver/presentation/driver_active_ride_screen.dart';
import '../../features/driver/presentation/driver_cash_payment_screen.dart';
import '../../features/driver/presentation/driver_completed_payment_screen.dart';
import '../../features/driver/presentation/driver_home_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_about_you_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_corrections_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_documents_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_review_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_state_error_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_submit_review_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_suspended_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_vehicle_screen.dart';
import 'driver_onboarding_routes.dart';
import 'route_not_found_screen.dart';

final appRouter = GoRouter(
  initialLocation: DriverOnboardingRoutes.splash,
  // Red de seguridad: cualquier ruta que go_router no pueda resolver
  // (p. ej. una notificación push que abre la app cerrada con una ruta
  // inválida) cae en una pantalla con salida real — nunca en el
  // ErrorScreen por defecto, cuyo botón "Home" apunta a `/`, que no
  // existe en esta app, y deja al usuario atrapado.
  errorBuilder: (context, state) {
    debugPrint(
      'DRIVER ROUTER - ruta no encontrada: "${state.uri}" '
      '(${state.error})',
    );

    return const RouteNotFoundScreen();
  },
  routes: [
    GoRoute(
      path: DriverOnboardingRoutes.splash,
      builder: (context, state) => const DriverSplashScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.account,
      builder: (context, state) => const CreateAccountScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.aboutYou,
      builder: (context, state) => DriverOnboardingAboutYouScreen(
        args: state.extra as DriverOnboardingAboutYouScreenArgs?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.vehicle,
      builder: (context, state) => DriverOnboardingVehicleScreen(
        args: state.extra as DriverOnboardingVehicleScreenArgs?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.documents,
      builder: (context, state) => DriverOnboardingDocumentsScreen(
        args: state.extra as DriverOnboardingDocumentsScreenArgs?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.review,
      builder: (context, state) => DriverOnboardingSubmitReviewScreen(
        initialState: state.extra as DriverSessionState?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.corrections,
      builder: (context, state) => DriverOnboardingCorrectionsScreen(
        initialState: state.extra as DriverSessionState?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.reviewStatus,
      builder: (context, state) => const DriverOnboardingReviewScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.suspended,
      builder: (context, state) => DriverOnboardingSuspendedScreen(
        application: state.extra as DriverApplication?,
      ),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.stateError,
      builder: (context, state) => const DriverOnboardingStateErrorScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.home,
      builder: (context, state) => const DriverHomeScreen(),
    ),
    GoRoute(
      path: '/active-ride',
      builder: (context, state) => const DriverActiveRideScreen(),
    ),
    GoRoute(
      path: '/cash-payment/:rideId',
      builder: (context, state) {
        final rideId = state.pathParameters['rideId']!;

        return DriverCashPaymentScreen(rideId: rideId);
      },
    ),
    GoRoute(
      path: '/completed-payment/:rideId',
      builder: (context, state) {
        final rideId = state.pathParameters['rideId']!;

        return DriverCompletedPaymentScreen(rideId: rideId);
      },
    ),
  ],
);
