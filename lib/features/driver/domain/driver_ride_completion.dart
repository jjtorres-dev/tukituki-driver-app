class DriverRideCompletion {
  const DriverRideCompletion({
    required this.rideId,
    required this.status,
    required this.completedAt,
    required this.actualDistanceMeters,
    required this.actualDurationSeconds,
    required this.estimatedFare,
    required this.finalFare,
    required this.discountAmount,
    required this.passengerAmountDue,
    required this.currency,
    required this.fareWasCapped,
    required this.paymentMethod,
    required this.paymentStatus,
  });

  final String rideId;
  final String status;
  final DateTime completedAt;

  final num actualDistanceMeters;
  final num actualDurationSeconds;

  final String estimatedFare;
  final String finalFare;
  final String discountAmount;
  final String passengerAmountDue;

  final String currency;

  final bool fareWasCapped;

  final String paymentMethod;
  final String paymentStatus;

  factory DriverRideCompletion.fromJson(
    Map<String, dynamic> json,
  ) {
    return DriverRideCompletion(
      rideId:
          json['rideId']?.toString() ?? '',
      status:
          json['status']?.toString() ?? 'UNKNOWN',
      completedAt: DateTime.parse(
        json['completedAt'] as String,
      ),
      actualDistanceMeters:
          json['actualDistanceMeters'] as num? ?? 0,
      actualDurationSeconds:
          json['actualDurationSeconds'] as num? ?? 0,
      estimatedFare:
          json['estimatedFare']?.toString() ?? '0.00',
      finalFare:
          json['finalFare']?.toString() ?? '0.00',
      discountAmount:
          json['discountAmount']?.toString() ?? '0.00',
      passengerAmountDue:
          json['passengerAmountDue']?.toString() ??
              '0.00',
      currency:
          json['currency']?.toString() ?? 'PEN',
      fareWasCapped:
          json['fareWasCapped'] as bool? ?? false,
      paymentMethod:
          json['paymentMethod']?.toString() ?? 'CASH',
      paymentStatus:
          json['paymentStatus']?.toString() ??
              'PENDING',
    );
  }
}