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
  /// significa que el Paso 3 ya se completó, así que ese caso va a
  /// [documents] (Paso 4) o [start] según los documentos.
  static const vehicle = '/onboarding/vehicle';

  /// "Tus documentos" — Paso 4: sube licencia/SOAT/tarjeta de
  /// propiedad y captura su metadata. Solo `draftDocumentsIncomplete`
  /// llega aquí directo desde el routing — los 3 documentos completos
  /// significan que el Paso 4 ya se completó, así que ese caso va a
  /// [review]. También se reutiliza (via `context.push`, sin `extra`)
  /// como edición de documentos desde "Editar" en Paso 5.
  static const documents = '/onboarding/documents';

  /// "Revisar y enviar" — Paso 5 real (`DRIVER-ONBOARDING-R3.7`). Solo
  /// `draftDocumentsComplete` llega aquí desde el routing.
  static const review = '/onboarding/review';

  /// Foundation histórica de DRAFT con Pasos 2-4 completos, previa a
  /// `R3.7`. Ya no es destino de ningún `DriverSessionKind` — se
  /// conserva únicamente porque `DriverOnboardingRejectedScreen`
  /// ("Corregir solicitud") todavía navega aquí; la corrección
  /// granular de una solicitud `REJECTED` queda diferida a
  /// `DRIVER-ONBOARDING-R3.8` (ver `decisiones.md`).
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
    case DriverSessionKind.draftDocumentsIncomplete:
      return DriverOnboardingRoutes.documents;
    case DriverSessionKind.draftDocumentsComplete:
      return DriverOnboardingRoutes.review;
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

/// Navega al path correspondiente a [state], pasando `extra` cuando la
/// pantalla destino lo necesita: `application` para rechazada/
/// suspendida (mostrar el motivo), o el [DriverSessionState] completo
/// para "Revisar y enviar" (`application`+`vehicle`+`documents`, ya
/// resueltos — evita que esa pantalla repita 3 GETs que
/// `resolveSessionState()` ya hizo). Único punto donde Splash/Login/
/// pantallas de estado y edición deciden a dónde ir tras resolver la
/// sesión — evita repetir este mapeo en cada pantalla.
void goToDriverSessionRoute(BuildContext context, DriverSessionState state) {
  final route = routeForDriverSessionKind(state.kind);

  if (route == DriverOnboardingRoutes.rejected ||
      route == DriverOnboardingRoutes.suspended) {
    context.go(route, extra: state.application);
    return;
  }

  if (route == DriverOnboardingRoutes.review) {
    context.go(route, extra: state);
    return;
  }

  context.go(route);
}
