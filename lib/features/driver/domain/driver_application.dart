/// Tipo de documento de identidad tal como lo expone/acepta
/// `drivers/me` (`IdentityDocumentType` en `identity-document-type.enum.ts`:
/// `DNI`/`FOREIGNER_CARD`/`PASSPORT`).
///
/// Decisión de producto (Paso 2 "Sobre ti"): la UI de creación solo
/// ofrece DNI y CE (`foreignerCard`) — `passport` se conserva
/// únicamente para poder leer/mostrar perfiles legacy que ya lo
/// tengan, nunca como opción seleccionable en el formulario nuevo.
enum IdentityDocumentType {
  dni('DNI', 'DNI'),
  foreignerCard('FOREIGNER_CARD', 'CE'),
  passport('PASSPORT', 'Pasaporte'),

  /// Backend devolvió un valor que este cliente todavía no conoce.
  unknown('', '');

  const IdentityDocumentType(this.value, this.label);

  /// Valor exacto que espera/devuelve Backend. Vacío para `unknown`
  /// — nunca se envía un tipo de documento no reconocido.
  final String value;

  /// Texto mostrado al usuario. El valor raw de Backend nunca llega
  /// a la UI.
  final String label;

  static IdentityDocumentType fromRaw(String? raw) {
    return IdentityDocumentType.values.firstWhere(
      (type) => type.value == raw,
      orElse: () => IdentityDocumentType.unknown,
    );
  }
}

enum DriverApplicationStatus {
  draft,
  pendingReview,
  approved,
  rejected,
  suspended,

  /// Backend devolvió un `status` que este cliente todavía no conoce.
  ///
  /// Deliberadamente NO se enruta a Home ni a ningún paso del
  /// onboarding: un status desconocido debe fallar de forma segura
  /// (ver `resolveDriverApplicationState` en `driver_session_state.dart`).
  unknown;

  static DriverApplicationStatus fromRaw(String? raw) {
    switch (raw) {
      case 'DRAFT':
        return DriverApplicationStatus.draft;
      case 'PENDING_REVIEW':
        return DriverApplicationStatus.pendingReview;
      case 'APPROVED':
        return DriverApplicationStatus.approved;
      case 'REJECTED':
        return DriverApplicationStatus.rejected;
      case 'SUSPENDED':
        return DriverApplicationStatus.suspended;
      default:
        return DriverApplicationStatus.unknown;
    }
  }
}

/// Solicitud de conductor tal como la devuelve `GET drivers/me`.
///
/// Solo incluye los campos que este checkpoint necesita para el
/// routing/foundation del onboarding (Backend expone más campos —
/// `documentType`, `birthDate`, `photoUrl`, etc. — que llegarán con
/// los pasos "Sobre ti"/"Documentos", fuera de alcance aquí).
class DriverApplication {
  const DriverApplication({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.status,
    this.documentType = IdentityDocumentType.unknown,
    this.documentNumber,
    this.birthDate,
    this.email,
    this.photoUrl,
    this.rawStatus,
    this.rejectionReason,
    this.suspensionReason,
    this.submittedAt,
    this.approvedAt,
  });

  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final DriverApplicationStatus status;

  final IdentityDocumentType documentType;
  final String? documentNumber;

  /// `YYYY-MM-DD` tal como lo devuelve Backend (columna `date` de
  /// Postgres) — nunca se parsea a `DateTime` para no introducir
  /// ambigüedad de zona horaria en una fecha sin hora.
  final String? birthDate;

  final String? email;

  /// Foto ya resuelta por Backend (capability token si hay Storage,
  /// legacy si no) — nunca `photoObjectKey`, que Backend no expone
  /// en este contrato (`DriverProfileResponseDto`).
  final String? photoUrl;

  /// Valor crudo devuelto por Backend, por si aparece un status
  /// todavía no mapeado (ver `DriverApplicationStatus.unknown`).
  final String? rawStatus;

  final String? rejectionReason;
  final String? suspensionReason;
  final DateTime? submittedAt;
  final DateTime? approvedAt;

  factory DriverApplication.fromJson(Map<String, dynamic> json) {
    final raw = json['status']?.toString();

    return DriverApplication(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      status: DriverApplicationStatus.fromRaw(raw),
      documentType: IdentityDocumentType.fromRaw(
        json['documentType']?.toString(),
      ),
      documentNumber: json['documentNumber']?.toString(),
      birthDate: json['birthDate']?.toString(),
      email: json['email']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      rawStatus: raw,
      rejectionReason: json['rejectionReason']?.toString(),
      suspensionReason: json['suspensionReason']?.toString(),
      submittedAt: _tryParseDate(json['submittedAt']),
      approvedAt: _tryParseDate(json['approvedAt']),
    );
  }
}

DateTime? _tryParseDate(dynamic value) {
  if (value == null) {
    return null;
  }

  final text = value.toString();

  if (text.isEmpty) {
    return null;
  }

  return DateTime.tryParse(text);
}
