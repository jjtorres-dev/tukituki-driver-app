/// Estadísticas diarias del conductor.
///
/// Backend es la única fuente autoritativa: no se calculan
/// ni se derivan localmente a partir de historial de viajes.
class DriverDailyStats {
  const DriverDailyStats({
    required this.businessDate,
    required this.timezone,
    required this.completedRides,
    required this.grossAmount,
    required this.currency,
    required this.asOf,
  });

  final String businessDate;
  final String timezone;

  final int completedRides;

  /// Se conserva como String (no se convierte a double)
  /// para no introducir errores de redondeo con dinero.
  final String grossAmount;

  final String currency;

  final DateTime? asOf;

  factory DriverDailyStats.fromJson(Map<String, dynamic> json) {
    return DriverDailyStats(
      businessDate: json['businessDate']?.toString() ?? '',
      timezone: json['timezone']?.toString() ?? 'America/Lima',
      completedRides: _tryParseInt(json['completedRides']) ?? 0,
      grossAmount: json['grossAmount']?.toString() ?? '0.00',
      currency: json['currency']?.toString() ?? 'PEN',
      asOf: _tryParseDate(json['asOf']),
    );
  }
}

int? _tryParseInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString());
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
