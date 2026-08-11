import 'driver_assigned_passenger.dart';

class DriverActiveRide {
  const DriverActiveRide({
    required this.id,
    required this.status,
    required this.estimatedFare,
    required this.currency,
    required this.originAddress,
    required this.destinationAddress,
    required this.distanceMeters,
    required this.estimatedDurationSeconds,
    this.agreedFare,
    this.originLatitude,
    this.originLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.distanceToOriginMeters,
    this.passenger,
  });

  final String id;
  final String status;
  final String estimatedFare;
  final String currency;
  final String originAddress;
  final String destinationAddress;
  final num distanceMeters;
  final num estimatedDurationSeconds;

  /// Tarifa realmente negociada y aceptada. Nullable solo por
  /// consistencia con el contrato Backend; en DRIVER_ASSIGNED en
  /// adelante siempre debería venir presente.
  final String? agreedFare;

  final double? originLatitude;
  final double? originLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;

  /// Distancia real (PostGIS) del Driver al punto de recojo,
  /// recalculada por Backend en cada consulta del ride. Null si
  /// Backend todavía no tiene una ubicación del Driver.
  final num? distanceToOriginMeters;

  final AssignedPassenger? passenger;

  /// Fuente de verdad para "tarifa acordada". Si por una
  /// inconsistencia contractual excepcional `agreedFare` llega null,
  /// cae al `estimatedFare` ya existente (mismo fallback funcional
  /// que usaba la pantalla antes de este checkpoint) en vez de dejar
  /// la tarjeta vacía.
  String get displayFare => agreedFare ?? estimatedFare;

  factory DriverActiveRide.fromJson(Map<String, dynamic> json) {
    final origin = json['origin'] as Map<String, dynamic>? ?? {};

    final destination = json['destination'] as Map<String, dynamic>? ?? {};

    return DriverActiveRide(
      id: json['id'] as String,
      status: json['status']?.toString() ?? 'UNKNOWN',
      estimatedFare: json['estimatedFare']?.toString() ?? '0.00',
      agreedFare: json['agreedFare']?.toString(),
      currency: json['currency']?.toString() ?? 'PEN',
      originAddress: origin['address']?.toString() ?? 'Origen',
      destinationAddress: destination['address']?.toString() ?? 'Destino',
      originLatitude: _tryParseCoordinate(
        origin['latitude'],
        minimum: -90,
        maximum: 90,
      ),
      originLongitude: _tryParseCoordinate(
        origin['longitude'],
        minimum: -180,
        maximum: 180,
      ),
      destinationLatitude: _tryParseCoordinate(
        destination['latitude'],
        minimum: -90,
        maximum: 90,
      ),
      destinationLongitude: _tryParseCoordinate(
        destination['longitude'],
        minimum: -180,
        maximum: 180,
      ),
      distanceMeters: json['distanceMeters'] as num? ?? 0,
      estimatedDurationSeconds: json['estimatedDurationSeconds'] as num? ?? 0,
      distanceToOriginMeters: json['distanceToOriginMeters'] as num?,
      passenger: AssignedPassenger.tryParse(json['passenger']),
    );
  }
}

/// Mismo patrón de validación de coordenadas ya usado en Passenger
/// (`PassengerRide.fromJson`): descarta valores fuera de rango en vez
/// de fabricar un marker con una coordenada inválida.
double? _tryParseCoordinate(
  dynamic value, {
  required double minimum,
  required double maximum,
}) {
  if (value is! num) {
    return null;
  }

  final coordinate = value.toDouble();

  if (!coordinate.isFinite || coordinate < minimum || coordinate > maximum) {
    return null;
  }

  return coordinate;
}
