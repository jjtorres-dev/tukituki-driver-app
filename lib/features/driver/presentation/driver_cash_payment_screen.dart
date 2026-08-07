import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/driver_payments_repository.dart';
import '../domain/driver_ride_payment.dart';

class DriverCashPaymentScreen
    extends ConsumerStatefulWidget {
  const DriverCashPaymentScreen({
    required this.rideId,
    super.key,
  });

  final String rideId;

  @override
  ConsumerState<DriverCashPaymentScreen> createState() =>
      _DriverCashPaymentScreenState();
}

class _DriverCashPaymentScreenState
    extends ConsumerState<DriverCashPaymentScreen> {
  final _cashController = TextEditingController();

  DriverRidePayment? _payment;

  bool _loading = true;
  bool _confirming = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _loadPayment();
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
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
        _error = null;
      });
    } catch (error) {
      debugPrint(
        'Error consultando pago: $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error =
            'No se pudo consultar el pago del viaje.';
      });
    }
  }

  Future<void> _confirmCashPayment() async {
    final payment = _payment;

    if (payment == null || _confirming) {
      return;
    }

    final rawValue = _cashController.text
        .trim()
        .replaceAll(',', '.');

    final cashValue =
        double.tryParse(rawValue);

    if (cashValue == null || cashValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ingresa un monto válido.',
          ),
        ),
      );

      return;
    }

    final amountDue =
        double.tryParse(payment.amountDue) ?? 0;

    if (cashValue < amountDue) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El efectivo debe cubrir al menos '
            'S/ ${payment.amountDue}.',
          ),
        ),
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _confirming = true;
    });

    try {
      final confirmed = await ref
          .read(driverPaymentsRepositoryProvider)
          .confirmCashPayment(
            rideId: payment.rideId,
            cashReceived:
                cashValue.toStringAsFixed(2),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _payment = confirmed;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '¡Pago confirmado!',
          ),
        ),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo confirmar el pago.';

      if (error.response?.statusCode == 400) {
        message =
            'El efectivo recibido no cubre '
            'la tarifa final.';
      } else if (error.response?.statusCode == 409) {
        message =
            'Este pago ya fue confirmado '
            'o ya no puede modificarse.';
      } else if (error.response?.statusCode == 404) {
        message =
            'No encontramos el pago del viaje.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final payment = _payment;

    if (payment == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Cobro del viaje',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ??
                  'No se pudo consultar el pago.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final paid = payment.status == 'PAID';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          paid
              ? 'Pago confirmado'
              : 'Cobrar viaje',
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              Icon(
                paid
                    ? Icons.check_circle
                    : Icons.payments,
                size: 90,
              ),

              const SizedBox(height: 24),

              Text(
                paid
                    ? '¡Pago recibido!'
                    : 'Cobro en efectivo',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Total a cobrar',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              Text(
                'S/ ${payment.amountDue}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 32),

              if (!paid) ...[
                TextField(
                  controller: _cashController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
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
                    helperText:
                        'Ejemplo: 10.00',
                  ),
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _confirming
                      ? null
                      : _confirmCashPayment,
                  icon: _confirming
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.check,
                        ),
                  label: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    child: Text(
                      _confirming
                          ? 'Confirmando...'
                          : 'Confirmar pago',
                    ),
                  ),
                ),
              ],

              if (paid) ...[
                Card(
                  child: Padding(
                    padding:
                        const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        _PaymentRow(
                          label:
                              'Tarifa del viaje',
                          value:
                              'S/ ${payment.amountDue}',
                        ),

                        const Divider(),

                        _PaymentRow(
                          label:
                              'Efectivo recibido',
                          value:
                              'S/ ${payment.cashReceived ?? '0.00'}',
                        ),

                        const Divider(),

                        _PaymentRow(
                          label:
                              'Vuelto',
                          value:
                              'S/ ${payment.changeGiven ?? '0.00'}',
                        ),

                        const Divider(),

                        _PaymentRow(
                          label:
                              'Estado',
                          value:
                              payment.status,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: () {
                    context.go('/home');
                  },
                  icon: const Icon(
                    Icons.home,
                  ),
                  label: const Padding(
                    padding:
                        EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                    child: Text(
                      'Finalizar',
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}