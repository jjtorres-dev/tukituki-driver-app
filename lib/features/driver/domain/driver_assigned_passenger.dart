/// Resumen mínimo del Passenger asignado, tal como lo expone
/// `drivers/me/rides/active` / `drivers/me/rides/:id` desde el
/// checkpoint Backend D0, extendido con `lastNameInitial` en R4.3
/// (`CROSS-APP-R4.3A`).
///
/// Deliberadamente NO incluye lastName completo/phone/email/document:
/// Backend no los expone en este contrato y no deben inventarse en
/// Driver.
class AssignedPassenger {
  const AssignedPassenger({
    required this.profileId,
    required this.firstName,
    this.lastNameInitial = '',
    required this.ratingAverage,
    required this.ratingCount,
    this.photoUrl,
  });

  final String profileId;
  final String firstName;
  final String lastNameInitial;
  final String? photoUrl;

  /// String tal como la envía Backend (numeric(3,2)), nunca redondeada
  /// aquí para no perder precisión antes de mostrarla.
  final String ratingAverage;

  /// Cantidad de CALIFICACIONES recibidas, no de viajes completados.
  final int ratingCount;

  /// Solo hay rating real que mostrar si existe al menos una
  /// calificación y el promedio es un número válido y positivo.
  bool get hasRating {
    final average = double.tryParse(ratingAverage);

    return ratingCount > 0 &&
        average != null &&
        average.isFinite &&
        average > 0;
  }

  static AssignedPassenger? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }

    return AssignedPassenger.fromJson(Map<String, dynamic>.from(json));
  }

  factory AssignedPassenger.fromJson(Map<String, dynamic> json) {
    return AssignedPassenger(
      profileId: json['profileId']?.toString() ?? '',
      firstName: json['firstName']?.toString() ?? '',
      lastNameInitial: json['lastNameInitial']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString(),
      ratingAverage: json['ratingAverage']?.toString() ?? '0.00',
      ratingCount: _tryParseInt(json['ratingCount']) ?? 0,
    );
  }
}

int? _tryParseInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString());
}
