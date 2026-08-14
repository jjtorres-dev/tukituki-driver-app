class DriverRideOffer {
  const DriverRideOffer({
    required this.id,
    required this.rideId,
    required this.status,
    required this.distanceToOriginMeters,
    required this.estimatedFare,
    required this.passengerOfferFare,
    required this.proposedFare,
    required this.proposedAt,
    required this.currency,
    required this.originAddress,
    required this.destinationAddress,
    required this.expiresAt,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.passengerFirstName,
  });

  final String id;
  final String rideId;
  final String status;

  final num distanceToOriginMeters;

  /// Precio recomendado por TukiTuki.
  final String estimatedFare;

  /// Precio elegido inicialmente por el pasajero.
  final String passengerOfferFare;

  /// Precio propuesto por el conductor.
  /// Será null mientras la oferta siga en OFFERED.
  final String? proposedFare;

  final DateTime? proposedAt;

  final String currency;

  final String originAddress;
  final String destinationAddress;

  final DateTime expiresAt;

  /// Coordenadas reales de pickup/destino, tal como las envía Backend
  /// en `ride.origin`/`ride.destination`. Nulas si Backend no las
  /// incluyó o si el valor recibido no es un número — NUNCA se
  /// inventan ni se completan con un fallback numérico.
  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  /// `true` solo si AMBAS coordenadas de origen y destino son
  /// válidas. El mapa de Solicitudes (G4B2) depende de este chequeo
  /// para decidir si puede dibujar los markers A/B sin arriesgarse a
  /// un `LatLng` a medias.
  bool get hasValidRouteCoordinates =>
      originLatitude != null &&
      originLongitude != null &&
      destinationLatitude != null &&
      destinationLongitude != null;

  /// Nombre real del Passenger (`ride.passenger.firstName`). Null si
  /// Backend no lo entregó (p.ej. inconsistencia de datos) —
  /// deliberadamente NUNCA se completa con un placeholder tipo
  /// "Pasajero": la UI simplemente omite la fila del nombre.
  final String? passengerFirstName;

  bool get hasProposal => status == 'PROPOSED' && proposedFare != null;

  bool get isCounterOffer {
    final proposed = proposedFare;

    if (proposed == null) {
      return false;
    }

    final passenger = _tryParseFareInCents(passengerOfferFare);

    final driver = _tryParseFareInCents(proposed);

    if (passenger == null || driver == null) {
      return false;
    }

    return driver != passenger;
  }

  factory DriverRideOffer.fromJson(Map<String, dynamic> json) {
    final ride =
        json['ride'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final origin =
        ride['origin'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final destination =
        ride['destination'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    final passenger = ride['passenger'] as Map<String, dynamic>?;

    final estimatedFare =
        json['estimatedFare']?.toString() ??
        ride['estimatedFare']?.toString() ??
        '0.00';

    final passengerOfferFare =
        json['passengerOfferFare']?.toString() ??
        ride['passengerOfferFare']?.toString() ??
        estimatedFare;

    return DriverRideOffer(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      status: json['status']?.toString() ?? 'OFFERED',
      distanceToOriginMeters: json['distanceToOriginMeters'] as num,
      estimatedFare: estimatedFare,
      passengerOfferFare: passengerOfferFare,
      proposedFare: json['proposedFare']?.toString(),
      proposedAt: json['proposedAt'] == null
          ? null
          : DateTime.parse(json['proposedAt'].toString()),
      currency:
          json['currency']?.toString() ?? ride['currency']?.toString() ?? 'PEN',
      originAddress: origin['address']?.toString() ?? 'Origen',
      destinationAddress: destination['address']?.toString() ?? 'Destino',
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      originLatitude: _tryParseCoordinate(origin['latitude']),
      originLongitude: _tryParseCoordinate(origin['longitude']),
      destinationLatitude: _tryParseCoordinate(destination['latitude']),
      destinationLongitude: _tryParseCoordinate(destination['longitude']),
      passengerFirstName: _tryParseNonEmptyString(passenger?['firstName']),
    );
  }
}

/// `num -> double` seguro: cualquier valor que no sea numérico
/// (ausente, null, string, mapa mal formado) se resuelve como `null`
/// en vez de lanzar, para que una coordenada inválida nunca tumbe el
/// parseo de la Offer completa.
double? _tryParseCoordinate(Object? value) {
  if (value is num) {
    return value.toDouble();
  }

  return null;
}

/// Normaliza `firstName`: ausente, no-string o vacío tras `trim()`
/// se resuelven como `null` — nunca una cadena vacía silenciosa.
String? _tryParseNonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();

  return trimmed.isEmpty ? null : trimmed;
}

int? _tryParseFareInCents(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(normalized);

  if (match == null) {
    return null;
  }

  final wholeUnits = int.tryParse(match.group(1)!);
  final decimalPart = (match.group(2) ?? '').padRight(2, '0');
  final cents = int.tryParse(decimalPart);

  if (wholeUnits == null || cents == null) {
    return null;
  }

  return (wholeUnits * 100) + cents;
}
