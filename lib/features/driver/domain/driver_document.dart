/// `DriverDocument.type` tal como lo expone/acepta
/// `drivers/me/documents` (`DriverDocumentType` en
/// `driver-document-type.enum.ts`).
///
/// Decisión de producto (Paso 4 "Tus documentos"): la UI solo ofrece
/// [driverLicense]/[soat]/[vehicleRegistration] — los 3 tipos legacy
/// ([dniFront]/[dniBack]/[profilePhoto]) se conservan únicamente para
/// poder parsear defensivamente un `DriverDocument` legacy si Backend
/// lo devuelve, nunca se muestran ni se ofrecen como opción nueva.
enum DriverDocumentType {
  driverLicense('DRIVER_LICENSE', 'Licencia de conducir'),
  soat('SOAT', 'SOAT'),
  vehicleRegistration('VEHICLE_REGISTRATION', 'Tarjeta de propiedad / TIV'),
  dniFront('DNI_FRONT', ''),
  dniBack('DNI_BACK', ''),
  profilePhoto('PROFILE_PHOTO', ''),

  /// Backend devolvió un valor que este cliente todavía no conoce.
  unknown('', '');

  const DriverDocumentType(this.value, this.label);

  /// Valor exacto que espera/devuelve Backend. Vacío para
  /// `unknown`/legacy — nunca se envía un tipo no reconocido, y los
  /// legacy nunca se crean desde este onboarding.
  final String value;

  /// Texto mostrado al usuario. Vacío para los tipos que nunca se
  /// muestran en Paso 4 (legacy y `unknown`).
  final String label;

  static DriverDocumentType fromRaw(String? raw) {
    return DriverDocumentType.values.firstWhere(
      (type) => type.value == raw,
      orElse: () => DriverDocumentType.unknown,
    );
  }
}

/// `DriverDocument.status` (`DriverDocumentStatus` en
/// `driver-document-status.enum.ts`) — 4 valores, sin `SUSPENDED` (a
/// diferencia de `DriverApplicationStatus`/`VehicleStatus`).
enum DriverDocumentStatus {
  draft,
  pendingReview,
  approved,
  rejected,

  /// Backend devolvió un `status` que este cliente todavía no conoce.
  unknown;

  static DriverDocumentStatus fromRaw(String? raw) {
    switch (raw) {
      case 'DRAFT':
        return DriverDocumentStatus.draft;
      case 'PENDING_REVIEW':
        return DriverDocumentStatus.pendingReview;
      case 'APPROVED':
        return DriverDocumentStatus.approved;
      case 'REJECTED':
        return DriverDocumentStatus.rejected;
      default:
        return DriverDocumentStatus.unknown;
    }
  }
}

/// Un documento del expediente del conductor tal como lo devuelve
/// `drivers/me/documents` (`DriverDocumentResponseDto`).
///
/// Solo incluye los campos que este checkpoint necesita — Backend
/// expone además `reviewedByUserId`/timestamps que ninguna pantalla
/// de onboarding usa todavía.
class DriverDocument {
  const DriverDocument({
    required this.id,
    required this.driverProfileId,
    required this.type,
    required this.status,
    this.fileUrl,
    this.fileObjectKey,
    this.documentNumber,
    this.issuedAt,
    this.expiresAt,
    this.rejectionReason,
  });

  final String id;
  final String driverProfileId;
  final DriverDocumentType type;
  final DriverDocumentStatus status;

  final String? fileUrl;
  final String? fileObjectKey;

  final String? documentNumber;

  /// `YYYY-MM-DD`, mismo criterio que `DriverApplication.birthDate`:
  /// nunca se parsea a `DateTime` en el modelo para no introducir
  /// ambigüedad de zona horaria en una fecha sin hora.
  final String? issuedAt;
  final String? expiresAt;

  final String? rejectionReason;

  bool get hasFile =>
      (fileUrl != null && fileUrl!.isNotEmpty) ||
      (fileObjectKey != null && fileObjectKey!.isNotEmpty);

  factory DriverDocument.fromJson(Map<String, dynamic> json) {
    return DriverDocument(
      id: json['id']?.toString() ?? '',
      driverProfileId: json['driverProfileId']?.toString() ?? '',
      type: DriverDocumentType.fromRaw(json['type']?.toString()),
      status: DriverDocumentStatus.fromRaw(json['status']?.toString()),
      fileUrl: json['fileUrl']?.toString(),
      fileObjectKey: json['fileObjectKey']?.toString(),
      documentNumber: json['documentNumber']?.toString(),
      issuedAt: json['issuedAt']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
    );
  }
}

/// Los 3 tipos que el Paso 4 exige, en el orden en que se muestran
/// (`REQUIRED_DRIVER_APPLICATION_DOCUMENT_TYPES` en Backend).
const List<DriverDocumentType> requiredDriverOnboardingDocumentTypes = [
  DriverDocumentType.driverLicense,
  DriverDocumentType.soat,
  DriverDocumentType.vehicleRegistration,
];

/// Mismo criterio de completitud que Backend exige recién al hacer
/// `POST drivers/me/submit` (`DriverApplicationSubmissionService.
/// validateDocumentData`) — replicado aquí como ayuda de UX para
/// decidir cuándo el Paso 4 ya está listo para el Paso 5. Backend
/// sigue siendo la fuente de verdad final en el submit real.
///
/// `DRIVER_LICENSE`/`SOAT`: archivo + documentNumber + issuedAt (no
/// futuro) + expiresAt (posterior a issuedAt, no vencido).
/// `VEHICLE_REGISTRATION`: archivo + documentNumber + issuedAt (no
/// futuro) — sin exigir `expiresAt`.
bool isDriverDocumentComplete(DriverDocument? document, {DateTime? today}) {
  if (document == null || !document.hasFile) {
    return false;
  }

  final documentNumber = document.documentNumber;

  if (documentNumber == null || documentNumber.trim().isEmpty) {
    return false;
  }

  final issuedAt = _tryParseIsoDate(document.issuedAt);

  if (issuedAt == null) {
    return false;
  }

  final now = today ?? DateTime.now();
  final todayUtc = DateTime.utc(now.year, now.month, now.day);

  if (issuedAt.isAfter(todayUtc)) {
    return false;
  }

  switch (document.type) {
    case DriverDocumentType.driverLicense:
    case DriverDocumentType.soat:
      final expiresAt = _tryParseIsoDate(document.expiresAt);

      if (expiresAt == null) {
        return false;
      }

      if (!expiresAt.isAfter(issuedAt)) {
        return false;
      }

      if (expiresAt.isBefore(todayUtc)) {
        return false;
      }

      return true;

    case DriverDocumentType.vehicleRegistration:
      return true;

    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return false;
  }
}

DateTime? _tryParseIsoDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final parts = value.split('-');

  if (parts.length != 3) {
    return null;
  }

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);

  if (year == null || month == null || day == null) {
    return null;
  }

  return DateTime.utc(year, month, day);
}
