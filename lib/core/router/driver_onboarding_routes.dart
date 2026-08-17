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

  /// "Sobre ti" — Paso 2: crea el `DriverProfile` (DRAFT) + sube la
  /// foto de perfil. Solo NO_PROFILE llega aquí — un `DriverProfile`
  /// ya existente (DRAFT/REJECTED) significa que el Paso 2 ya se
  /// completó (sus campos son obligatorios para crearlo), así que
  /// esos casos van directo a [start].
  static const aboutYou = '/onboarding/about-you';

  /// "Tu mototaxi" — Paso 3: crea el `DriverVehicle` (DRAFT). Solo
  /// `draftNoVehicle` llega aquí — un `DriverVehicle` ya existente
  /// significa que el Paso 3 ya se completó, así que ese caso va
  /// directo a [start] (foundation de Paso 4).
  static const vehicle = '/onboarding/vehicle';

  /// Foundation de DRAFT+vehículo ya registrado en este checkpoint:
  /// todavía no existen los pasos 4-5, así que ese caso llega a esta
  /// misma pantalla de inicio (ver `decisiones.md`, "no inventar
  /// lastCompletedStep").
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
      return DriverOnboardingRoutes.aboutYou;
    case DriverSessionKind.draftNoVehicle:
      return DriverOnboardingRoutes.vehicle;
    case DriverSessionKind.draftWithVehicle:
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
