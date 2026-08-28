import 'package:flutter/material.dart';

import '../../../core/theme/driver_palette.dart';
import 'driver_ride_completion_view.dart' show paymentMethodLabel;

/// Indicador REFERENCIAL del método de pago que eligió el pasajero.
///
/// No hay pasarela ni cobro dentro de la app: el pasajero le paga
/// directo al conductor. Este chip solo le dice al conductor *cómo* le
/// van a pagar (Efectivo, Yape, Plin, Tarjeta) para que pueda decidir
/// —antes de aceptar— si le sirve ese medio.
///
/// Reutiliza [paymentMethodLabel] (el mismo mapeo a etiquetas en
/// español que ya usan la pantalla de finalización y la de cobro en
/// efectivo): no duplica etiquetas.
///
/// Acento ámbar/naranja de la identidad del conductor (mismo par
/// `amber` + `orangeDeep` que ya usa `_RideStatusHeader`), nunca el
/// verde del pasajero.
///
/// Devuelve [SizedBox.shrink] si el método llega vacío o nulo — nunca
/// inventa un "Efectivo" por defecto, igual criterio que el resto de
/// campos opcionales de la solicitud/viaje.
class DriverPaymentMethodChip extends StatelessWidget {
  const DriverPaymentMethodChip({
    required this.method,
    this.dense = false,
    super.key,
  });

  final String? method;

  /// Versión compacta para la tarjeta de solicitud entrante, donde el
  /// chip convive con nombre + tarifa + distancia + direcciones.
  final bool dense;

  /// Deja que los llamadores decidan el espaciado sin re-implementar
  /// la comprobación de "hay un método que mostrar".
  static bool hasMethod(String? method) => (method ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final raw = method?.trim() ?? '';

    if (raw.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 10 : 12,
          vertical: dense ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: DriverPalette.amber.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_wallet_outlined,
              size: 15,
              color: DriverPalette.orangeDeep,
            ),
            const SizedBox(width: 6),
            Text(
              'Pago: ${paymentMethodLabel(raw)}',
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w700,
                color: DriverPalette.orangeDeep,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
