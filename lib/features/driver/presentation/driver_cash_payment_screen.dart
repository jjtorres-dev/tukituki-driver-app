import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/driver_palette.dart';
import '../data/driver_payments_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_money.dart';
import '../domain/driver_ride_payment.dart';
import 'driver_ride_completion_view.dart' show paymentMethodLabel;

class DriverCashPaymentScreen extends ConsumerStatefulWidget {
  const DriverCashPaymentScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<DriverCashPaymentScreen> createState() =>
      _DriverCashPaymentScreenState();
}

enum _CashConfirmErrorKind { insufficient, notFound, conflict, network }

class _CashConfirmError {
  const _CashConfirmError(this.kind);

  final _CashConfirmErrorKind kind;
}

class _DriverCashPaymentScreenState
    extends ConsumerState<DriverCashPaymentScreen> {
  final _cashController = TextEditingController();

  DriverRidePayment? _payment;

  /// Best-effort: solo se llena si `getRide` responde con Passenger
  /// real. Un fallo aquí nunca bloquea el cobro, solo deja el
  /// subtítulo neutral.
  String? _passengerFirstName;

  bool _loading = true;
  bool _confirming = false;

  int? _cashCents;

  String? _loadError;
  _CashConfirmError? _confirmError;

  @override
  void initState() {
    super.initState();

    _cashController.addListener(_handleCashChanged);

    unawaited(_loadPayment());
  }

  @override
  void dispose() {
    _cashController.removeListener(_handleCashChanged);
    _cashController.dispose();
    super.dispose();
  }

  void _handleCashChanged() {
    final normalized = _cashController.text.trim().replaceAll(',', '.');

    setState(() {
      _cashCents = parseAmountToCents(normalized);
    });
  }

  int get _dueCents {
    final payment = _payment;

    if (payment == null) {
      return 0;
    }

    return parseAmountToCents(payment.amountDue) ?? 0;
  }

  Future<void> _loadPayment() async {
    try {
      final payment = await ref
          .read(driverPaymentsRepositoryProvider)
          .getPayment(widget.rideId);

      if (!mounted) {
        return;
      }

      setState(() {
        _payment = payment;
        _loading = false;
        _loadError = null;
      });

      unawaited(_loadPassengerFirstName());
    } catch (error) {
      debugPrint('Error consultando pago: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = 'No se pudo consultar el pago del viaje.';
      });
    }
  }

  Future<void> _loadPassengerFirstName() async {
    try {
      final ride = await ref
          .read(driverRidesRepositoryProvider)
          .getRide(widget.rideId);

      if (!mounted) {
        return;
      }

      final firstName = ride.passenger?.firstName;

      if (firstName != null && firstName.isNotEmpty) {
        setState(() {
          _passengerFirstName = firstName;
        });
      }
    } catch (error) {
      // Puramente informativo para el subtítulo: nunca bloquea el
      // flujo de cobro si falla.
      debugPrint('DRIVER CASH PASSENGER LOOKUP ERROR: $error');
    }
  }

  void _applyQuickAmount(int cents) {
    if (_confirming) {
      return;
    }

    final formatted = formatCentsAsDecimal(cents);

    _cashController.text = formatted;
    _cashController.selection = TextSelection.collapsed(
      offset: formatted.length,
    );
  }

  Future<void> _confirmAndSubmit() async {
    final payment = _payment;
    final cents = _cashCents;

    if (payment == null || cents == null || cents < _dueCents || _confirming) {
      return;
    }

    final changeCents = cents - _dueCents;

    FocusScope.of(context).unfocus();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Confirmar pago recibido?'),
          content: Text(
            'El pasajero entregó S/ ${formatCentsAsDecimal(cents)}.\n'
            'Vuelto a entregar: S/ ${formatCentsAsDecimal(changeCents)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sí, confirmar pago'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _submitConfirmCash(cents);
  }

  Future<void> _submitConfirmCash(int cents) async {
    if (_confirming) {
      return;
    }

    setState(() {
      _confirming = true;
      _confirmError = null;
    });

    try {
      final confirmed = await ref
          .read(driverPaymentsRepositoryProvider)
          .confirmCashPayment(
            rideId: widget.rideId,
            cashReceived: formatCentsAsDecimal(cents),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _payment = confirmed;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER CASH CONFIRM ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _confirmError = _classifyConfirmError(error);
      });
    } catch (error) {
      debugPrint('DRIVER CASH CONFIRM ERROR: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _confirmError = const _CashConfirmError(_CashConfirmErrorKind.network);
      });
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
        });
      }
    }
  }

  _CashConfirmError _classifyConfirmError(DioException error) {
    final statusCode = error.response?.statusCode;

    if (statusCode == 400) {
      return const _CashConfirmError(_CashConfirmErrorKind.insufficient);
    }

    if (statusCode == 404) {
      return const _CashConfirmError(_CashConfirmErrorKind.notFound);
    }

    if (statusCode == 409) {
      return const _CashConfirmError(_CashConfirmErrorKind.conflict);
    }

    return const _CashConfirmError(_CashConfirmErrorKind.network);
  }

  String _confirmErrorMessage(_CashConfirmErrorKind kind) {
    switch (kind) {
      case _CashConfirmErrorKind.insufficient:
        return 'El efectivo no cubre el monto a cobrar.';
      case _CashConfirmErrorKind.notFound:
        return 'No encontramos el pago de este viaje.';
      case _CashConfirmErrorKind.conflict:
        return 'Este pago ya no puede confirmarse.';
      case _CashConfirmErrorKind.network:
        return 'No se pudo conectar con TukiTuki. Inténtalo nuevamente.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final payment = _payment;

    if (payment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cobrar viaje')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _loadError ?? 'No se pudo consultar el pago.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final paid = payment.status == 'PAID';

    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        automaticallyImplyLeading: false,
        foregroundColor: DriverPalette.greenPrimary,
        title: Text(paid ? 'Pago confirmado' : 'Cobrar viaje'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              if (paid) ...[
                _PaidHeroCard(amountDue: payment.amountDue),

                const SizedBox(height: 24),

                _PaidReceiptCard(payment: payment),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: () {
                    context.go('/home');
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: DriverPalette.greenPrimary,
                  ),
                  icon: const Icon(Icons.home),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Volver al inicio'),
                  ),
                ),
              ] else ...[
                const Icon(
                  Icons.payments,
                  size: 72,
                  color: DriverPalette.amber,
                ),

                const SizedBox(height: 20),

                const Text(
                  'Cobro en efectivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: DriverPalette.greenPrimary,
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  _passengerFirstName != null
                      ? 'Ingresa el monto que te entregó '
                            '$_passengerFirstName'
                      : 'Ingresa el monto que te entregó el pasajero',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DriverPalette.brown),
                ),

                const SizedBox(height: 24),

                _TotalDueCard(amountDue: payment.amountDue),

                const SizedBox(height: 24),

                TextField(
                  controller: _cashController,
                  enabled: !_confirming,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*[.,]?\d{0,2}'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Efectivo recibido',
                    prefixText: 'S/ ',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                _QuickAmountsRow(
                  amountsCents: quickAmountsForDueCents(_dueCents),
                  enabled: !_confirming,
                  onSelected: _applyQuickAmount,
                ),

                if (_cashCents != null) ...[
                  const SizedBox(height: 18),
                  _ChangePreviewCard(
                    cashCents: _cashCents!,
                    dueCents: _dueCents,
                  ),
                ],

                if (_confirmError != null) ...[
                  const SizedBox(height: 14),
                  _ErrorBanner(
                    message: _confirmErrorMessage(_confirmError!.kind),
                  ),
                ],

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed:
                      (_cashCents != null &&
                          _cashCents! >= _dueCents &&
                          !_confirming)
                      ? _confirmAndSubmit
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: DriverPalette.greenPrimary,
                  ),
                  icon: _confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _confirming ? 'Confirmando...' : 'Confirmar pago',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta principal del recibo PAID: check amarillo sobre verde
/// oscuro, "¡Pago recibido!" y el TOTAL COBRADO real
/// (`payment.amountDue`, el monto que el pasajero terminó pagando).
class _PaidHeroCard extends StatelessWidget {
  const _PaidHeroCard({required this.amountDue});

  final String amountDue;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: DriverPalette.greenPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DriverPalette.amber.withValues(alpha: 0.24),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              color: DriverPalette.amber,
              size: 36,
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            '¡Pago recibido!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'TOTAL COBRADO',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DriverPalette.amberLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'S/ $amountDue',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Comprobante final del cobro. `finalFare` del Ride no está
/// disponible de forma segura en esta pantalla (`getPayment` solo
/// expone `DriverRidePayment`; `getRide` es best-effort y solo se usa
/// para el nombre del Passenger), así que la fila usa el contrato
/// real de esta pantalla: `payment.amountDue`, con una etiqueta
/// neutral ("Monto del viaje") en vez de asumir que es la tarifa
/// final exacta del Ride.
class _PaidReceiptCard extends StatelessWidget {
  const _PaidReceiptCard({required this.payment});

  final DriverRidePayment payment;

  @override
  Widget build(BuildContext context) {
    final cashReceived = payment.cashReceived;
    final changeGiven = payment.changeGiven;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _PaymentRow(
            label: 'Monto del viaje',
            value: 'S/ ${payment.amountDue}',
          ),

          const Divider(),

          _PaymentRow(
            label: 'Método de pago',
            value: paymentMethodLabel(payment.method),
          ),

          if (cashReceived != null) ...[
            const Divider(),
            _PaymentRow(
              label: 'Efectivo recibido',
              value: 'S/ $cashReceived',
            ),
          ],

          if (changeGiven != null) ...[
            const Divider(),
            _PaymentRow(label: 'Vuelto entregado', value: 'S/ $changeGiven'),
          ],

          const Divider(),

          _PaidStatusRow(status: payment.status),
        ],
      ),
    );
  }
}

class _PaidStatusRow extends StatelessWidget {
  const _PaidStatusRow({required this.status});

  /// Solo se renderiza el badge "PAGADO" cuando el contrato real es
  /// `PAID`. Un valor inesperado (defensivo: este widget solo se usa
  /// dentro de la rama ya validada `paid == true`) cae al raw status
  /// en vez de afirmar "PAGADO" sin soporte real.
  final String status;

  @override
  Widget build(BuildContext context) {
    if (status != 'PAID') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Estado'),
            Text(status, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Estado'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: DriverPalette.greenAvailable.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle,
                  size: 14,
                  color: DriverPalette.greenAvailable,
                ),
                SizedBox(width: 4),
                Text(
                  'PAGADO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: DriverPalette.greenAvailable,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalDueCard extends StatelessWidget {
  const _TotalDueCard({required this.amountDue});

  final String amountDue;

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
            'TOTAL A COBRAR',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DriverPalette.brown,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'S/ $amountDue',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: DriverPalette.greenPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAmountsRow extends StatelessWidget {
  const _QuickAmountsRow({
    required this.amountsCents,
    required this.enabled,
    required this.onSelected,
  });

  final List<int> amountsCents;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < amountsCents.length; index++) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              key: ValueKey('quick-amount-$index'),
              onPressed: enabled
                  ? () => onSelected(amountsCents[index])
                  : null,
              child: Text('S/ ${formatCentsAsDecimal(amountsCents[index])}'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChangePreviewCard extends StatelessWidget {
  const _ChangePreviewCard({required this.cashCents, required this.dueCents});

  final int cashCents;
  final int dueCents;

  @override
  Widget build(BuildContext context) {
    final sufficient = cashCents >= dueCents;

    if (sufficient) {
      final changeCents = cashCents - dueCents;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            const Text(
              'VUELTO A ENTREGAR',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: DriverPalette.brown,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'S/ ${formatCentsAsDecimal(changeCents)}',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: DriverPalette.greenPrimary,
              ),
            ),
          ],
        ),
      );
    }

    final shortfallCents = dueCents - cashCents;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: DriverPalette.coral.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'Monto insuficiente',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DriverPalette.coral,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Faltan S/ ${formatCentsAsDecimal(shortfallCents)}',
            style: const TextStyle(color: DriverPalette.coral),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

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
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: DriverPalette.coral,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
