/// `DriverVehicle.ownership` tal como lo expone/acepta
/// `drivers/me/vehicle` (`VehicleOwnership` en
/// `vehicle-ownership.enum.ts`: `OWNED`/`RENTED`).
enum VehicleOwnership {
  owned('OWNED', 'Propio'),
  rented('RENTED', 'Alquilado'),

  /// Backend devolvió un valor que este cliente todavía no conoce.
  unknown('', '');

  const VehicleOwnership(this.value, this.label);

  /// Valor exacto que espera/devuelve Backend. Vacío para `unknown`
  /// — nunca se envía un valor no reconocido.
  final String value;

  /// Texto mostrado al usuario ("Propio"/"Alquilado"). El valor raw
  /// de Backend nunca llega a la UI.
  final String label;

  static VehicleOwnership fromRaw(String? raw) {
    return VehicleOwnership.values.firstWhere(
      (ownership) => ownership.value == raw,
      orElse: () => VehicleOwnership.unknown,
    );
  }
}

/// `DriverVehicle.status` (`VehicleStatus` en `vehicle-status.enum.ts`)
/// — mismos 5 valores y misma filosofía defensiva que
/// `DriverApplicationStatus` en `driver_application.dart`.
enum VehicleStatus {
  draft,
  pendingReview,
  approved,
  rejected,
  suspended,

  /// Backend devolvió un `status` que este cliente todavía no conoce.
  unknown;

  static VehicleStatus fromRaw(String? raw) {
    switch (raw) {
      case 'DRAFT':
        return VehicleStatus.draft;
      case 'PENDING_REVIEW':
        return VehicleStatus.pendingReview;
      case 'APPROVED':
        return VehicleStatus.approved;
      case 'REJECTED':
        return VehicleStatus.rejected;
      case 'SUSPENDED':
        return VehicleStatus.suspended;
      default:
        return VehicleStatus.unknown;
    }
  }
}

/// El vehículo del conductor tal como lo devuelve `drivers/me/vehicle`
/// (`DriverVehicleResponseDto`).
///
/// Solo incluye los campos que este checkpoint necesita para el
/// routing/foundation del onboarding (Paso 3 "Tu mototaxi") — Backend
/// expone además `vehicleType` (fijo, `MOTOTAXI`, nunca elegido por
/// el cliente) y timestamps que ninguna pantalla usa todavía.
class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.driverProfileId,
    required this.plate,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.ownership,
    required this.status,
    this.engineNumber,
    this.chassisNumber,
    this.rejectionReason,
  });

  final String id;
  final String driverProfileId;
  final String plate;
  final String brand;
  final String model;
  final int year;
  final String color;
  final VehicleOwnership ownership;
  final VehicleStatus status;
  final String? engineNumber;
  final String? chassisNumber;
  final String? rejectionReason;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    return DriverVehicle(
      id: json['id']?.toString() ?? '',
      driverProfileId: json['driverProfileId']?.toString() ?? '',
      plate: json['plate']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      year: int.tryParse(json['year']?.toString() ?? '') ?? 0,
      color: json['color']?.toString() ?? '',
      ownership: VehicleOwnership.fromRaw(json['ownership']?.toString()),
      status: VehicleStatus.fromRaw(json['status']?.toString()),
      engineNumber: json['engineNumber']?.toString(),
      chassisNumber: json['chassisNumber']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
    );
  }
}
