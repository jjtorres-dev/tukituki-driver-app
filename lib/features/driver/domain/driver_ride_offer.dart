class DriverRideOffer {
  const DriverRideOffer({
    required this.id,
    required this.rideId,
    required this.status,
    required this.distanceToOriginMeters,
    required this.estimatedFare,
    required this.currency,
    required this.originAddress,
    required this.destinationAddress,
    required this.expiresAt,
  });

  final String id;
  final String rideId;
  final String status;
  final num distanceToOriginMeters;
  final String estimatedFare;
  final String currency;
  final String originAddress;
  final String destinationAddress;
  final DateTime expiresAt;

  factory DriverRideOffer.fromJson(
    Map<String, dynamic> json,
  ) {
    final ride =
        json['ride'] as Map<String, dynamic>? ?? {};

    final origin =
        ride['origin'] as Map<String, dynamic>? ?? {};

    final destination =
        ride['destination'] as Map<String, dynamic>? ?? {};

    return DriverRideOffer(
      id: json['id'] as String,
      rideId: json['rideId'] as String,
      status: json['status'] as String,
      distanceToOriginMeters:
          json['distanceToOriginMeters'] as num,
      estimatedFare:
          ride['estimatedFare']?.toString() ?? '0.00',
      currency:
          ride['currency']?.toString() ?? 'PEN',
      originAddress:
          origin['address']?.toString() ?? 'Origen',
      destinationAddress:
          destination['address']?.toString() ??
              'Destino',
      expiresAt: DateTime.parse(
        json['expiresAt'] as String,
      ),
    );
  }
}