import '../../driver/domain/driver_application.dart';
import 'authenticated_user.dart';

/// Resultado del routing conceptual acordado para Driver App:
///
/// SIN SESIÓN → Login
/// CON SESIÓN → auth/me → drivers/me → uno de estos casos.
///
/// DECISIÓN DE PRODUCTO MVP (`DRIVER-ONBOARDING-R3.3`): la
/// verificación de teléfono por OTP queda diferida hasta contar con
/// un proveedor SMS real (`OTP-R3`, hoy pausado). `isPhoneVerified`
/// ya NO bloquea este routing — una cuenta puede seguir su
/// onboarding con `isPhoneVerified == false`. Backend sigue
/// exigiendo `phoneE164` único y OTP-R2 permanece intacto para
/// cuando se retome la verificación real.
enum DriverSessionKind {
  /// `GET drivers/me` respondió 404 — el usuario todavía no inició
  /// ninguna solicitud de conductor.
  noProfile,

  /// `DriverProfile.status == DRAFT`.
  draft,

  /// `DriverProfile.status == REJECTED`.
  rejected,

  /// `DriverProfile.status == PENDING_REVIEW`.
  pendingReview,

  /// `DriverProfile.status == APPROVED` y el usuario ya tiene el rol
  /// `DRIVER` — único caso que debe entrar a Home.
  approved,

  /// `DriverProfile.status == APPROVED` pero el usuario NO tiene el
  /// rol `DRIVER` todavía. Inconsistencia de datos entre Backend y
  /// el rol de la cuenta: nunca se entra a Home en silencio.
  approvedRoleMismatch,

  /// `DriverProfile.status == SUSPENDED`.
  suspended,

  /// Backend devolvió un `status` que este cliente no reconoce.
  /// Debe fallar de forma segura, nunca enrutarse a Home.
  unknownApplicationStatus,
}

class DriverSessionState {
  const DriverSessionState({
    required this.kind,
    required this.user,
    this.application,
  });

  final DriverSessionKind kind;
  final AuthenticatedUser user;
  final DriverApplication? application;
}

/// Función pura: dado el usuario autenticado y su solicitud de
/// conductor (si existe), decide a qué caso del routing corresponde.
///
/// No hace llamadas de red ni conoce rutas/widgets — eso es
/// responsabilidad de `AuthRepository` (obtener los datos) y de las
/// pantallas (navegar según el `DriverSessionKind` resultante).
///
/// `user.isPhoneVerified` deliberadamente no se lee aquí (MVP sin
/// bloqueo de OTP, ver doc de `DriverSessionKind`).
DriverSessionState resolveDriverApplicationState({
  required AuthenticatedUser user,
  required DriverApplication? application,
}) {
  if (application == null) {
    return DriverSessionState(kind: DriverSessionKind.noProfile, user: user);
  }

  switch (application.status) {
    case DriverApplicationStatus.draft:
      return DriverSessionState(
        kind: DriverSessionKind.draft,
        user: user,
        application: application,
      );
    case DriverApplicationStatus.rejected:
      return DriverSessionState(
        kind: DriverSessionKind.rejected,
        user: user,
        application: application,
      );
    case DriverApplicationStatus.pendingReview:
      return DriverSessionState(
        kind: DriverSessionKind.pendingReview,
        user: user,
        application: application,
      );
    case DriverApplicationStatus.suspended:
      return DriverSessionState(
        kind: DriverSessionKind.suspended,
        user: user,
        application: application,
      );
    case DriverApplicationStatus.approved:
      return DriverSessionState(
        kind: user.isDriver
            ? DriverSessionKind.approved
            : DriverSessionKind.approvedRoleMismatch,
        user: user,
        application: application,
      );
    case DriverApplicationStatus.unknown:
      return DriverSessionState(
        kind: DriverSessionKind.unknownApplicationStatus,
        user: user,
        application: application,
      );
  }
}
