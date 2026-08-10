import 'package:flutter/material.dart';

class DriverCounterOfferValidation {
  const DriverCounterOfferValidation._({this.proposedFare, this.errorMessage});

  const DriverCounterOfferValidation.valid(String proposedFare)
    : this._(proposedFare: proposedFare);

  const DriverCounterOfferValidation.invalid(String errorMessage)
    : this._(errorMessage: errorMessage);

  final String? proposedFare;
  final String? errorMessage;

  bool get isValid => proposedFare != null;
}

DriverCounterOfferValidation validateDriverCounterOfferInput(String input) {
  final normalized = input.trim().replaceAll(',', '.');
  final value = double.tryParse(normalized);

  if (value == null || !value.isFinite || value <= 0) {
    return const DriverCounterOfferValidation.invalid(
      'Ingresa un monto válido.',
    );
  }

  final decimalFormat = RegExp(r'^(?:\d+(?:\.\d{0,2})?|\.\d{1,2})$');
  if (!decimalFormat.hasMatch(normalized)) {
    return const DriverCounterOfferValidation.invalid(
      'Usa como máximo 2 decimales.',
    );
  }

  if (value > 9999.99) {
    return const DriverCounterOfferValidation.invalid(
      'El monto es demasiado alto.',
    );
  }

  return DriverCounterOfferValidation.valid(value.toStringAsFixed(2));
}

String driverCounterOfferErrorMessage({
  required int? statusCode,
  required bool hasResponse,
}) {
  if (statusCode == 409) {
    return 'Esta solicitud ya venció o ya no está disponible.';
  }
  if (!hasResponse) {
    return 'No se pudo conectar con el servidor.';
  }
  if (statusCode == 400) {
    return 'La contraoferta no es válida.';
  }
  return 'No se pudo enviar la contraoferta.';
}

Future<String?> showDriverCounterOfferDialog({
  required BuildContext context,
  required String passengerOfferFare,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return _DriverCounterOfferDialog(passengerOfferFare: passengerOfferFare);
    },
  );

  final result = await navigator.push<String>(route);
  await route.completed;
  return result;
}

class _DriverCounterOfferDialog extends StatefulWidget {
  const _DriverCounterOfferDialog({required this.passengerOfferFare});

  final String passengerOfferFare;

  @override
  State<_DriverCounterOfferDialog> createState() =>
      _DriverCounterOfferDialogState();
}

class _DriverCounterOfferDialogState extends State<_DriverCounterOfferDialog> {
  late final TextEditingController _controller;
  String? _validationError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    if (_submitting) return;
    Navigator.of(context).pop();
  }

  void _submit() {
    if (_submitting) return;

    final validation = validateDriverCounterOfferInput(_controller.text);
    if (!validation.isValid) {
      setState(() {
        _validationError = validation.errorMessage;
      });
      return;
    }

    setState(() {
      _submitting = true;
      _validationError = null;
    });
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(validation.proposedFare);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Hacer contraoferta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('El pasajero ofrece S/ ${widget.passengerOfferFare}'),
          const SizedBox(height: 12),
          const Text('Ingresa el precio que propones para este viaje.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_submitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tu contraoferta',
              prefixText: 'S/ ',
              helperText: 'Máximo 2 decimales.',
              errorText: _validationError,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _cancel,
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
