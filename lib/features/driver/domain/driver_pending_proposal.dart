/// Propuesta PROPOSED enviada por el conductor y todavía
/// pendiente de decisión del pasajero.
///
/// Se obtiene de `GET drivers/me/ride-offers/proposals/pending`,
/// que puede devolver 0..N elementos. Es una entidad distinta
/// de las ofertas OFFERED (ver [DriverRideOffer]).
class DriverPendingProposal {
  const DriverPendingProposal({
    required this.offerId,
    required this.rideId,
    required this.status,
    required this.proposedFare,
    required this.passengerOfferFare,
    required this.estimatedFare,
    required this.currency,
    required this.expiresAt,
    required this.originAddress,
    required this.destinationAddress,
    required this.distanceToOriginMeters,
  });

  final String offerId;
  final String rideId;
  final String status;

  final String? proposedFare;
  final String passengerOfferFare;
  final String estimatedFare;

  final String currency;

  final DateTime? expiresAt;

  final String originAddress;
  final String destinationAddress;

  final num distanceToOriginMeters;

  factory DriverPendingProposal.fromJson(Map<String, dynamic> json) {
    return DriverPendingProposal(
      offerId: json['offerId']?.toString() ?? json['id']?.toString() ?? '',
      rideId: json['rideId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PROPOSED',
      proposedFare: json['proposedFare']?.toString(),
      passengerOfferFare: json['passengerOfferFare']?.toString() ?? '0.00',
      estimatedFare: json['estimatedFare']?.toString() ?? '0.00',
      currency: json['currency']?.toString() ?? 'PEN',
      expiresAt: _tryParseDate(json['expiresAt']),
      originAddress: _addressOf(json['origin']) ?? 'Origen',
      destinationAddress: _addressOf(json['destination']) ?? 'Destino',
      distanceToOriginMeters: json['distanceToOriginMeters'] as num? ?? 0,
    );
  }
}

String? _addressOf(dynamic value) {
  if (value is Map) {
    return value['address']?.toString();
  }

  if (value is String) {
    return value;
  }

  return null;
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
