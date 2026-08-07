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
  });

  final String id;
  final String status;
  final String estimatedFare;
  final String currency;
  final String originAddress;
  final String destinationAddress;
  final num distanceMeters;
  final num estimatedDurationSeconds;

  factory DriverActiveRide.fromJson(
    Map<String, dynamic> json,
  ) {
    final origin =
        json['origin'] as Map<String, dynamic>? ?? {};

    final destination =
        json['destination'] as Map<String, dynamic>? ?? {};

    return DriverActiveRide(
      id: json['id'] as String,
      status: json['status']?.toString() ?? 'UNKNOWN',
      estimatedFare:
          json['estimatedFare']?.toString() ?? '0.00',
      currency:
          json['currency']?.toString() ?? 'PEN',
      originAddress:
          origin['address']?.toString() ?? 'Origen',
      destinationAddress:
          destination['address']?.toString() ?? 'Destino',
      distanceMeters:
          json['distanceMeters'] as num? ?? 0,
      estimatedDurationSeconds:
          json['estimatedDurationSeconds'] as num? ?? 0,
    );
  }
}