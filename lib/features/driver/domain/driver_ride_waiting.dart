/// Estado real de la espera del Driver en el punto de recojo
/// (Checkpoint G2 — `RideWaiting`), tal como lo expone
/// `POST/GET drivers/me/rides/:rideId/waiting[/start]`.
///
/// Backend es la única autoridad de tiempo: este modelo nunca calcula
/// `remainingWaitingSeconds` ni `canReportNoShow` por su cuenta, solo
/// los transporta tal como llegan.
class DriverRideWaiting {
  const DriverRideWaiting({
    required this.rideId,
    required this.waitingStartedAt,
    required this.noShowAvailableAt,
    required this.requiredWaitingSeconds,
    required this.elapsedWaitingSeconds,
    required this.remainingWaitingSeconds,
    required this.canReportNoShow,
    this.startDistanceMeters,
  });

  final String rideId;
  final DateTime waitingStartedAt;
  final DateTime noShowAvailableAt;
  final num requiredWaitingSeconds;
  final num elapsedWaitingSeconds;
  final num remainingWaitingSeconds;

  /// `true` únicamente cuando Backend confirma explícitamente que el
  /// tiempo de espera se cumplió. Nunca se deriva de
  /// `remainingWaitingSeconds` ni de un reloj local.
  final bool canReportNoShow;

  /// Distancia real del Driver al pickup en el momento de iniciar la
  /// espera. Nullable porque Backend puede no tenerla disponible.
  final num? startDistanceMeters;

  /// Igual que `remainingWaitingSeconds`, pero nunca negativo — solo
  /// para presentación (drift de reloj/red no debe mostrar "-3s").
  int get remainingSecondsForDisplay =>
      remainingWaitingSeconds < 0 ? 0 : remainingWaitingSeconds.round();

  /// Parsing defensivo: un payload sin los campos temporales/numéricos
  /// que Backend garantiza se rechaza con [FormatException] en vez de
  /// fabricar un estado "válido" a partir de datos ausentes o
  /// corruptos. `canReportNoShow` es la única excepción deliberada:
  /// cualquier valor que no sea literalmente `true` se interpreta como
  /// `false` (la dirección segura, nunca habilita no-show por error).
  factory DriverRideWaiting.fromJson(Map<String, dynamic> json) {
    final rideId = json['rideId'];

    if (rideId is! String || rideId.isEmpty) {
      throw const FormatException(
        'RideWaiting inválido: rideId ausente o inválido.',
      );
    }

    final waitingStartedAt = DateTime.tryParse(
      json['waitingStartedAt']?.toString() ?? '',
    );
    final noShowAvailableAt = DateTime.tryParse(
      json['noShowAvailableAt']?.toString() ?? '',
    );

    if (waitingStartedAt == null || noShowAvailableAt == null) {
      throw const FormatException(
        'RideWaiting inválido: fechas ausentes o corruptas.',
      );
    }

    final requiredWaitingSeconds = json['requiredWaitingSeconds'];
    final elapsedWaitingSeconds = json['elapsedWaitingSeconds'];
    final remainingWaitingSeconds = json['remainingWaitingSeconds'];

    if (requiredWaitingSeconds is! num ||
        elapsedWaitingSeconds is! num ||
        remainingWaitingSeconds is! num) {
      throw const FormatException(
        'RideWaiting inválido: conteo de segundos ausente o corrupto.',
      );
    }

    final startDistanceMeters = json['startDistanceMeters'];

    return DriverRideWaiting(
      rideId: rideId,
      waitingStartedAt: waitingStartedAt,
      noShowAvailableAt: noShowAvailableAt,
      requiredWaitingSeconds: requiredWaitingSeconds,
      elapsedWaitingSeconds: elapsedWaitingSeconds,
      remainingWaitingSeconds: remainingWaitingSeconds,
      canReportNoShow: json['canReportNoShow'] == true,
      startDistanceMeters: startDistanceMeters is num
          ? startDistanceMeters
          : null,
    );
  }
}
