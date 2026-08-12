import 'package:flutter/material.dart';

import '../../../core/theme/driver_palette.dart';

/// UI "Viaje completado" compartida entre el flujo en vivo
/// (`DriverActiveRideScreen`, justo después de `complete`) y el
/// restore server-side (`DriverCompletedPaymentScreen`, cuando el
/// Driver cierra la app antes de cobrar). Deliberadamente no depende
/// de `DriverRideCompletion` ni de ningún objeto en memoria: recibe
/// solo los campos primitivos que ambas fuentes pueden ofrecer
/// realmente, y cada llamador decide qué pasar cuando un dato (ej.
/// Passenger o las métricas de distancia/duración) no está disponible
/// en su contrato.
class DriverRideCompletionView extends StatelessWidget {
  const DriverRideCompletionView({
    required this.passengerFirstName,
    required this.passengerPhotoUrl,
    required this.finalFare,
    required this.actualDistanceMeters,
    required this.actualDurationSeconds,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.onCollectCash,
    super.key,
  });

  final String? passengerFirstName;
  final String? passengerPhotoUrl;

  /// `null` solo si Backend realmente no lo tiene (contrato nullable).
  final String? finalFare;

  /// `null` cuando el contrato de origen no las expone (restore desde
  /// `pending-payments`, que no incluye métricas de viaje).
  final num? actualDistanceMeters;
  final num? actualDurationSeconds;

  final String paymentMethod;
  final String paymentStatus;

  final VoidCallback onCollectCash;

  bool get _isCashPending =>
      paymentMethod == 'CASH' && paymentStatus == 'PENDING';

  bool get _hasPassenger =>
      passengerFirstName != null && passengerFirstName!.isNotEmpty;

  bool get _hasDistance =>
      actualDistanceMeters != null && actualDistanceMeters! > 0;

  bool get _hasDuration =>
      actualDurationSeconds != null && actualDurationSeconds! > 0;

  bool get _hasRecapCard => _hasPassenger || _hasDistance || _hasDuration;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        automaticallyImplyLeading: false,
        foregroundColor: DriverPalette.greenPrimary,
        title: const Text(
          'Viaje completado',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CompletionBadgeHeader(hasPassenger: _hasPassenger),

              const SizedBox(height: 8),

              Text(
                _hasPassenger
                    ? 'Llevaste a $passengerFirstName a su destino '
                          'con éxito'
                    : 'Llegaste al destino con éxito',
                textAlign: TextAlign.center,
                style: const TextStyle(color: DriverPalette.brown),
              ),

              const SizedBox(height: 22),

              _FinalFareCard(finalFare: finalFare),

              if (_hasRecapCard) ...[
                const SizedBox(height: 14),
                _PassengerRecapCard(
                  firstName: passengerFirstName,
                  photoUrl: passengerPhotoUrl,
                  actualDistanceMeters: _hasDistance
                      ? actualDistanceMeters
                      : null,
                  actualDurationSeconds: _hasDuration
                      ? actualDurationSeconds
                      : null,
                ),
              ],

              const SizedBox(height: 14),

              _PaymentStatusCard(
                paymentMethod: paymentMethod,
                paymentStatus: paymentStatus,
              ),

              const SizedBox(height: 22),

              if (_isCashPending)
                FilledButton.icon(
                  onPressed: onCollectCash,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriverPalette.greenPrimary,
                  ),
                  icon: const Icon(Icons.payments),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Cobrar efectivo'),
                  ),
                )
              else if (paymentMethod != 'CASH')
                const _SafeNotice(
                  text:
                      'Este viaje no se cobra en efectivo desde la app.',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletionBadgeHeader extends StatelessWidget {
  const _CompletionBadgeHeader({required this.hasPassenger});

  final bool hasPassenger;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: DriverPalette.amber.withValues(alpha: 0.24),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: DriverPalette.amber,
            size: 36,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '¡Viaje completado!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
      ],
    );
  }
}

class _FinalFareCard extends StatelessWidget {
  const _FinalFareCard({required this.finalFare});

  final String? finalFare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'TARIFA FINAL',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DriverPalette.brown,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            finalFare != null ? 'S/ $finalFare' : '—',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: DriverPalette.greenPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerRecapCard extends StatelessWidget {
  const _PassengerRecapCard({
    required this.firstName,
    required this.photoUrl,
    required this.actualDistanceMeters,
    required this.actualDurationSeconds,
  });

  final String? firstName;
  final String? photoUrl;
  final num? actualDistanceMeters;
  final num? actualDurationSeconds;

  @override
  Widget build(BuildContext context) {
    final metrics = <String>[
      if (actualDistanceMeters != null)
        formatCompletionDistance(actualDistanceMeters!),
      if (actualDurationSeconds != null)
        formatCompletionDuration(actualDurationSeconds!),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (firstName != null && firstName!.isNotEmpty) ...[
            _CompletionAvatar(firstName: firstName!, photoUrl: photoUrl),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (firstName != null && firstName!.isNotEmpty)
                  Text(
                    firstName!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DriverPalette.greenPrimary,
                    ),
                  ),
                if (metrics.isNotEmpty) ...[
                  if (firstName != null && firstName!.isNotEmpty)
                    const SizedBox(height: 4),
                  Text(
                    metrics.join(' · '),
                    style: const TextStyle(
                      fontSize: 13,
                      color: DriverPalette.brown,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletionAvatar extends StatelessWidget {
  const _CompletionAvatar({required this.firstName, required this.photoUrl});

  final String firstName;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;

    if (url == null || url.isEmpty) {
      return _InitialAvatar(firstName: firstName);
    }

    return ClipOval(
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _InitialAvatar(firstName: firstName);
        },
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: DriverPalette.greenAvailable,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
    );
  }
}

class _PaymentStatusCard extends StatelessWidget {
  const _PaymentStatusCard({
    required this.paymentMethod,
    required this.paymentStatus,
  });

  final String paymentMethod;
  final String paymentStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _PaymentStatusRow(
            label: 'Método de pago',
            value: paymentMethodLabel(paymentMethod),
          ),
          const Divider(),
          _PaymentStatusRow(
            label: 'Estado del pago',
            value: paymentStatusLabel(paymentStatus),
          ),
        ],
      ),
    );
  }
}

class _PaymentStatusRow extends StatelessWidget {
  const _PaymentStatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: DriverPalette.brown)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DriverPalette.greenPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeNotice extends StatelessWidget {
  const _SafeNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: DriverPalette.brown),
      ),
    );
  }
}

/// Etiqueta legible del método de pago. Cualquier valor real no
/// mapeado se muestra tal cual llega de Backend (nunca se oculta).
String paymentMethodLabel(String method) {
  switch (method) {
    case 'CASH':
      return 'Efectivo';
    case 'YAPE':
      return 'Yape';
    case 'PLIN':
      return 'Plin';
    case 'CARD':
      return 'Tarjeta';
    default:
      return method;
  }
}

/// Etiqueta legible del estado de pago real (`RidePaymentStatus`).
String paymentStatusLabel(String status) {
  switch (status) {
    case 'PENDING':
      return 'Pendiente';
    case 'PAID':
      return 'Pagado';
    case 'PROCESSING':
      return 'Procesando';
    case 'FAILED':
      return 'Fallido';
    case 'EXPIRED':
      return 'Vencido';
    case 'DISPUTED':
      return 'En disputa';
    case 'VOIDED':
      return 'Anulado';
    default:
      return status;
  }
}

/// `< 60 s`: segundos. `< 60 min`: minutos. En adelante: horas y
/// minutos ("1 h 4 min", o "1 h" si los minutos son 0).
String formatCompletionDuration(num seconds) {
  final totalSeconds = seconds.round();

  if (totalSeconds < 60) {
    return '$totalSeconds s';
  }

  final totalMinutes = totalSeconds ~/ 60;

  if (totalMinutes < 60) {
    return '$totalMinutes min';
  }

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;

  return minutes > 0 ? '$hours h $minutes min' : '$hours h';
}

/// `< 1000 m`: metros redondeados. `>= 1000 m`: km con 1 decimal.
/// El llamador es responsable de omitir esta métrica cuando la
/// distancia real es 0 (no se muestra "0.0 km" ni "0 m").
String formatCompletionDistance(num meters) {
  final rounded = meters.round();

  if (rounded < 1000) {
    return '$rounded m';
  }

  final kilometers = rounded / 1000;

  return '${kilometers.toStringAsFixed(1)} km';
}
