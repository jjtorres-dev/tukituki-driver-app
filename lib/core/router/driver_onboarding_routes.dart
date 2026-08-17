import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/domain/driver_session_state.dart';

/// Paths de las rutas del onboarding/gate de sesión de Driver App.
///
/// Centralizados aquí para que Splash, Login y las pantallas de
/// onboarding naveguen siempre al mismo path por caso — evita que
/// cada pantalla repita su propio mapeo de `DriverSessionKind`.
class DriverOnboardingRoutes {
  const DriverOnboardingRoutes._();

  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';

  /// "Tu cuenta" — Paso 1: crear cuenta nueva (celular + contraseña).
  static const account = '/onboarding/account';

  /// Foundation compartida por NO_PROFILE y DRAFT en este checkpoint:
  /// todavía no existen los pasos 2-5, así que ambos casos llegan a
  /// la misma pantalla de inicio del onboarding (ver `decisiones.md`,
  /// "no inventar lastCompletedStep").
  static const start = '/onboarding/start';

  static const rejected = '/onboarding/rejected';
  static const reviewStatus = '/onboarding/review-status';
  static const suspended = '/suspended';

  /// APPROVED sin rol DRIVER, o un `status` de solicitud que este
  /// cliente no reconoce: inconsistencia de Backend, nunca se entra
  /// a Home en silencio.
  static const stateError = '/onboarding/state-error';
}

/// Mapea el resultado de `resolveDriverApplicationState` al path que
/// Splash/Login deben usar para navegar. Función pura: no depende de
/// `BuildContext` ni de `go_router`.
String routeForDriverSessionKind(DriverSessionKind kind) {
  switch (kind) {
    case DriverSessionKind.noProfile:
    case DriverSessionKind.draft:
      return DriverOnboardingRoutes.start;
    case DriverSessionKind.rejected:
      return DriverOnboardingRoutes.rejected;
    case DriverSessionKind.pendingReview:
      return DriverOnboardingRoutes.reviewStatus;
    case DriverSessionKind.approved:
      return DriverOnboardingRoutes.home;
    case DriverSessionKind.suspended:
      return DriverOnboardingRoutes.suspended;
    case DriverSessionKind.approvedRoleMismatch:
    case DriverSessionKind.unknownApplicationStatus:
      return DriverOnboardingRoutes.stateError;
  }
}

/// Navega al path correspondiente a [state], pasando `application`
/// como `extra` únicamente en los casos que lo necesitan (rechazada/
/// suspendida, para mostrar el motivo). Único punto donde
/// Splash/Login/pantallas de estado deciden a dónde ir tras resolver
/// la sesión — evita repetir este mapeo en cada pantalla.
void goToDriverSessionRoute(BuildContext context, DriverSessionState state) {
  final route = routeForDriverSessionKind(state.kind);

  final needsApplication =
      route == DriverOnboardingRoutes.rejected ||
      route == DriverOnboardingRoutes.suspended;

  if (needsApplication) {
    context.go(route, extra: state.application);
  } else {
    context.go(route);
  }
}
