enum DriverOperationalStatus {
  offline,
  available,
  busy,
  unknown;

  static DriverOperationalStatus fromRaw(String? raw) {
    switch (raw) {
      case 'OFFLINE':
        return DriverOperationalStatus.offline;
      case 'AVAILABLE':
        return DriverOperationalStatus.available;
      case 'BUSY':
        return DriverOperationalStatus.busy;
      default:
        return DriverOperationalStatus.unknown;
    }
  }
}

/// Estado operativo tipado del conductor.
///
/// Reemplaza el uso de String mágicos ('AVAILABLE', 'BUSY', ...)
/// esparcidos por el Home.
class DriverOperationalState {
  const DriverOperationalState({
    required this.status,
    this.rawStatus,
    this.id,
    this.driverProfileId,
    this.connectedAt,
    this.disconnectedAt,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
  });

  final DriverOperationalStatus status;

  /// Valor crudo devuelto por Backend, por si aparece
  /// un status todavía no mapeado.
  final String? rawStatus;

  final String? id;
  final String? driverProfileId;

  final DateTime? connectedAt;
  final DateTime? disconnectedAt;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory DriverOperationalState.fromJson(Map<String, dynamic> json) {
    final raw = json['status']?.toString();

    return DriverOperationalState(
      status: DriverOperationalStatus.fromRaw(raw),
      rawStatus: raw,
      id: json['id']?.toString(),
      driverProfileId: json['driverProfileId']?.toString(),
      connectedAt: _tryParseDate(json['connectedAt']),
      disconnectedAt: _tryParseDate(json['disconnectedAt']),
      lastSeenAt: _tryParseDate(json['lastSeenAt']),
      createdAt: _tryParseDate(json['createdAt']),
      updatedAt: _tryParseDate(json['updatedAt']),
    );
  }

  /// Para endpoints que solo devuelven `{"status": "..."}`
  /// (por ejemplo online/offline/heartbeat cuando Backend
  /// no envía el objeto completo).
  factory DriverOperationalState.fromStatusOnly(String? raw) {
    return DriverOperationalState(
      status: DriverOperationalStatus.fromRaw(raw),
      rawStatus: raw,
    );
  }

  /// Tiempo transcurrido desde `connectedAt`, solo cuando
  /// tiene sentido mostrarlo: sesión online vigente
  /// (AVAILABLE o BUSY dentro del mismo ciclo) y con
  /// `connectedAt` conocido.
  ///
  /// Devuelve null en OFFLINE o si no hay `connectedAt`.
  Duration? onlineDurationAt(DateTime now) {
    final startedAt = connectedAt;

    if (startedAt == null) {
      return null;
    }

    if (status != DriverOperationalStatus.available &&
        status != DriverOperationalStatus.busy) {
      return null;
    }

    return now.difference(startedAt);
  }
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
