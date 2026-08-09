import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/driver_splash_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/driver/presentation/driver_active_ride_screen.dart';
import '../../features/driver/presentation/driver_cash_payment_screen.dart';
import '../../features/driver/presentation/driver_home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) =>
          const DriverSplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          const LoginScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) =>
          const DriverHomeScreen(),
    ),
    GoRoute(
      path: '/active-ride',
      builder: (context, state) =>
          const DriverActiveRideScreen(),
    ),
    GoRoute(
      path: '/cash-payment/:rideId',
      builder: (context, state) {
        final rideId =
            state.pathParameters['rideId']!;

        return DriverCashPaymentScreen(
          rideId: rideId,
        );
      },
    ),
  ],
);