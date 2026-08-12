class DriverRidePayment {
  const DriverRidePayment({
    required this.id,
    required this.rideId,
    required this.method,
    required this.status,
    required this.amountDue,
    required this.grossAmount,
    required this.discountAmount,
    required this.currency,
    this.cashReceived,
    this.changeGiven,
    this.confirmedAt,
  });

  final String id;
  final String rideId;

  final String method;
  final String status;

  final String amountDue;
  final String grossAmount;
  final String discountAmount;

  final String? cashReceived;
  final String? changeGiven;

  /// Solo presente una vez que Backend confirmó el cobro (PAID).
  final DateTime? confirmedAt;

  final String currency;

  factory DriverRidePayment.fromJson(Map<String, dynamic> json) {
    return DriverRidePayment(
      id: json['id']?.toString() ?? '',
      rideId: json['rideId']?.toString() ?? '',
      method: json['method']?.toString() ?? 'CASH',
      status: json['status']?.toString() ?? 'PENDING',
      amountDue: json['amountDue']?.toString() ?? '0.00',
      grossAmount: json['grossAmount']?.toString() ?? '0.00',
      discountAmount: json['discountAmount']?.toString() ?? '0.00',
      cashReceived: json['cashReceived']?.toString(),
      changeGiven: json['changeGiven']?.toString(),
      confirmedAt: json['confirmedAt'] != null
          ? DateTime.tryParse(json['confirmedAt'].toString())
          : null,
      currency: json['currency']?.toString() ?? 'PEN',
    );
  }
}
