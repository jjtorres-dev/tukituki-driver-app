import 'driver_ride_payment.dart';

/// Resumen mínimo de un Ride COMPLETED con `RidePayment` todavía sin
/// confirmar, tal como lo expone `GET drivers/me/rides/pending-payments`
/// desde Backend D0. Suficiente para restaurar "Viaje completado /
/// Cobrar efectivo" sin depender de un `DriverRideCompletion` que solo
/// vive en memoria mientras la app sigue abierta.
///
/// Backend NO filtra por `method`: esta lista puede incluir pagos
/// PENDING de otros métodos (YAPE/PLIN/CARD). Filtrar por
/// `payment.method == 'CASH'` es responsabilidad de quien consuma
/// esta lista (ver [selectMostRecentCashPendingPayment]).
class DriverPendingPayment {
  const DriverPendingPayment({
    required this.rideId,
    required this.rideStatus,
    required this.originAddress,
    required this.destinationAddress,
    required this.completedAt,
    required this.finalFare,
    required this.currency,
    required this.payment,
  });

  final String rideId;
  final String rideStatus;
  final String originAddress;
  final String destinationAddress;
  final DateTime? completedAt;

  /// Nullable en el contrato real de Backend (`finalFare: string | null`).
  final String? finalFare;

  final String currency;
  final DriverRidePayment payment;

  factory DriverPendingPayment.fromJson(Map<String, dynamic> json) {
    return DriverPendingPayment(
      rideId: json['rideId']?.toString() ?? '',
      rideStatus: json['rideStatus']?.toString() ?? 'COMPLETED',
      originAddress: json['originAddress']?.toString() ?? '',
      destinationAddress: json['destinationAddress']?.toString() ?? '',
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      finalFare: json['finalFare']?.toString(),
      currency: json['currency']?.toString() ?? 'PEN',
      payment: DriverRidePayment.fromJson(
        Map<String, dynamic>.from(json['payment'] as Map? ?? const {}),
      ),
    );
  }
}

/// Selecciona el CASH PENDING más reciente de la lista real que
/// devuelve Backend, ya ordenada `completedAt DESC` server-side. Solo
/// filtra (`method == CASH && status == PENDING`) y toma el primero:
/// nunca reordena, para no asumir un contrato de orden distinto al
/// real. Devuelve `null` si no existe ninguno.
DriverPendingPayment? selectMostRecentCashPendingPayment(
  List<DriverPendingPayment> payments,
) {
  for (final candidate in payments) {
    if (candidate.payment.method == 'CASH' &&
        candidate.payment.status == 'PENDING') {
      return candidate;
    }
  }

  return null;
}
