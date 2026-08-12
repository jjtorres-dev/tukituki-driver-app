/// Motivos de cancelación que Backend acepta realmente en
/// `POST drivers/me/rides/:rideId/cancel` (`DriverCancellationReason`
/// en `driver-cancellation-reason.enum.ts`). `PASSENGER_NOT_FOUND`
/// existe en ese enum pero Backend lo rechaza expresamente para este
/// endpoint (exige el flujo waiting/no-show), así que nunca se
/// incluye aquí: este modelo solo representa los valores que el
/// Driver realmente puede enviar.
enum DriverCancellationReason {
  passengerRequestedCancel(
    'PASSENGER_REQUESTED_CANCEL',
    'El pasajero me pidió cancelar',
  ),
  cannotReachPickup(
    'CANNOT_REACH_PICKUP',
    'No puedo llegar al punto de recojo',
  ),
  vehicleProblem('VEHICLE_PROBLEM', 'Problema con mi vehículo'),
  safetyConcern('SAFETY_CONCERN', 'Problema de seguridad'),
  emergency('EMERGENCY', 'Emergencia'),
  other('OTHER', 'Otro motivo');

  const DriverCancellationReason(this.value, this.label);

  /// Valor exacto que espera `DriverCancelRideDto.reason`.
  final String value;

  /// Texto mostrado al Driver. El enum raw nunca llega a la UI.
  final String label;
}
