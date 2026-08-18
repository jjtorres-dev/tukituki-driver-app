import '../../driver/domain/driver_application.dart';
import '../../driver/domain/driver_document.dart';
import '../../driver/domain/driver_vehicle.dart';
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

  /// `DriverProfile.status == DRAFT` y `GET drivers/me/vehicle` →
  /// 404. Paso 3 ("Tu mototaxi") todavía no se completó.
  draftNoVehicle,

  /// `DriverProfile.status == DRAFT`, `GET drivers/me/vehicle` → 200
  /// y `GET drivers/me/documents` indica que falta al menos uno de
  /// los 3 documentos requeridos (ver
  /// `requiredDriverOnboardingDocumentTypes`/`isDriverDocumentComplete`).
  /// Paso 3 completo, Paso 4 ("Tus documentos") todavía no.
  draftDocumentsIncomplete,

  /// `DriverProfile.status == DRAFT`, vehículo existente y los 3
  /// documentos requeridos están completos (archivo + metadata
  /// válida). Paso 4 completo — va a la foundation de Paso 5.
  draftDocumentsComplete,

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
    this.vehicle,
    this.documents,
  });

  final DriverSessionKind kind;
  final AuthenticatedUser user;
  final DriverApplication? application;

  /// Presente cuando `kind` es `draftDocumentsIncomplete` o
  /// `draftDocumentsComplete` (resultado de `GET drivers/me/vehicle`).
  /// `null` en cualquier otro caso, incluido `draftNoVehicle`.
  final DriverVehicle? vehicle;

  /// Presente cuando `kind` es `draftDocumentsIncomplete` o
  /// `draftDocumentsComplete` (resultado de `GET drivers/me/documents`).
  /// `null` en cualquier otro caso.
  final List<DriverDocument>? documents;
}

/// `true` si [documents] cubre completo cada uno de
/// `requiredDriverOnboardingDocumentTypes` (archivo + metadata
/// válida por tipo, ver `isDriverDocumentComplete`). Usa el primer
/// documento que coincida con cada tipo — `drivers/me/documents`
/// tiene como máximo un documento por tipo (constraint única en
/// Backend).
bool _hasAllRequiredDriverDocuments(List<DriverDocument> documents) {
  for (final type in requiredDriverOnboardingDocumentTypes) {
    DriverDocument? match;

    for (final document in documents) {
      if (document.type == type) {
        match = document;
        break;
      }
    }

    if (!isDriverDocumentComplete(match)) {
      return false;
    }
  }

  return true;
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
///
/// `vehicle` solo se usa cuando `application.status == DRAFT`, para
/// distinguir Paso 3 de Paso 4/5 (ver `DriverSessionKind`). Se ignora
/// en cualquier otro status — `AuthRepository.resolveSessionState()`
/// no llama `GET drivers/me/vehicle` fuera de DRAFT.
///
/// `documents` solo se usa cuando además `vehicle != null`, para
/// distinguir Paso 4 de Paso 5 — `AuthRepository.resolveSessionState()`
/// no llama `GET drivers/me/documents` si todavía no hay vehículo.
DriverSessionState resolveDriverApplicationState({
  required AuthenticatedUser user,
  required DriverApplication? application,
  DriverVehicle? vehicle,
  List<DriverDocument>? documents,
}) {
  if (application == null) {
    return DriverSessionState(kind: DriverSessionKind.noProfile, user: user);
  }

  switch (application.status) {
    case DriverApplicationStatus.draft:
      if (vehicle == null) {
        return DriverSessionState(
          kind: DriverSessionKind.draftNoVehicle,
          user: user,
          application: application,
        );
      }

      final hasAllDocuments = _hasAllRequiredDriverDocuments(
        documents ?? const [],
      );

      return DriverSessionState(
        kind: hasAllDocuments
            ? DriverSessionKind.draftDocumentsComplete
            : DriverSessionKind.draftDocumentsIncomplete,
        user: user,
        application: application,
        vehicle: vehicle,
        documents: documents,
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
