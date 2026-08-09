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

  bool get hasProposal => status == 'PROPOSED' && proposedFare != null;

  bool get isCounterOffer {
    final proposed = proposedFare;

    if (proposed == null) {
      return false;
    }

    final passenger = double.tryParse(passengerOfferFare);

    final driver = double.tryParse(proposed);

    if (passenger == null || driver == null) {
      return false;
    }

    return driver > passenger;
  }

  factory DriverRideOffer.fromJson(Map<String, dynamic> json) {
    final ride =
        json['ride'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final origin =
        ride['origin'] as Map<String, dynamic>? ?? const <String, dynamic>{};

    final destination =
        ride['destination'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

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
    );
  }
}
