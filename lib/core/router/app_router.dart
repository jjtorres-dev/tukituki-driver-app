import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/auth/presentation/driver_splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/driver/domain/driver_application.dart';
import '../../features/driver/presentation/driver_active_ride_screen.dart';
import '../../features/driver/presentation/driver_cash_payment_screen.dart';
import '../../features/driver/presentation/driver_completed_payment_screen.dart';
import '../../features/driver/presentation/driver_home_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_about_you_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_rejected_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_review_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_start_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_state_error_screen.dart';
import '../../features/driver/presentation/onboarding/driver_onboarding_suspended_screen.dart';
import 'driver_onboarding_routes.dart';

final appRouter = GoRouter(
  initialLocation: DriverOnboardingRoutes.splash,
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
      builder: (context, state) => const DriverOnboardingAboutYouScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.start,
      builder: (context, state) => const DriverOnboardingStartScreen(),
    ),
    GoRoute(
      path: DriverOnboardingRoutes.rejected,
      builder: (context, state) => DriverOnboardingRejectedScreen(
        application: state.extra as DriverApplication?,
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
