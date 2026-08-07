import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/driver/presentation/driver_home_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  routes: [
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
  ],
);