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
