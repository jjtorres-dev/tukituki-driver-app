import 'package:flutter/material.dart';

import '../../../core/theme/driver_palette.dart';
import '../domain/driver_cancellation_reason.dart';

/// Resultado de la selección del Driver: motivo + detalle opcional ya
/// validado. Nunca se construye antes de que el Driver confirme
/// explícitamente en el diálogo terminal.
class DriverCancelRideDraft {
  const DriverCancelRideDraft({required this.reason, this.reasonDetail});

  final DriverCancellationReason reason;

  /// `null` cuando el Driver dejó el campo vacío. Nunca una cadena
  /// vacía: el repositorio decide omitir `reasonDetail` del body
  /// exactamente con ese criterio.
  final String? reasonDetail;
}

/// Backend acepta `reasonDetail` de 5 a 500 caracteres si se envía.
/// La UI limita a 300: `RideCancellation.reasonDetail` sí guarda
/// hasta 500, pero la copia denormalizada `rides.cancellationReason`
/// (la que reemplaza al motivo cuando hay texto libre) es
/// `varchar(300)`. Decisión defensiva del cliente para no depender de
/// un truncamiento silencioso en Backend — no es un límite que
/// Backend exija en este endpoint.
const int driverCancelDetailMaxLength = 300;
const int _driverCancelDetailMinLength = 5;

/// Vacío es válido (el campo es opcional). Entre 1 y 4 caracteres no
/// lo es: Backend rechazaría un `reasonDetail` así de corto.
String? driverCancelDetailValidationError(String input) {
  final trimmed = input.trim();

  if (trimmed.isEmpty) {
    return null;
  }

  if (trimmed.length < _driverCancelDetailMinLength) {
    return 'Escribe al menos 5 caracteres o deja el campo vacío.';
  }

  return null;
}

/// Encadena selector de motivo → confirmación terminal. Devuelve
/// `null` en cualquier punto en el que el Driver se retracte (cerrar
/// el bottom sheet, tocar "Volver" en la confirmación); solo devuelve
/// un draft cuando el Driver confirmó explícitamente "Sí, cancelar
/// viaje". El request real nunca se dispara desde aquí.
Future<DriverCancelRideDraft?> showDriverCancelRideFlow({
  required BuildContext context,
}) async {
  final draft = await showDriverCancelReasonSheet(context: context);

  if (draft == null || !context.mounted) {
    return null;
  }

  final confirmed = await showDriverCancelConfirmationDialog(
    context: context,
    draft: draft,
  );

  if (confirmed != true) {
    return null;
  }

  return draft;
}

Future<DriverCancelRideDraft?> showDriverCancelReasonSheet({
  required BuildContext context,
}) {
  return showModalBottomSheet<DriverCancelRideDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _DriverCancelReasonSheet(),
  );
}

Future<bool?> showDriverCancelConfirmationDialog({
  required BuildContext context,
  required DriverCancelRideDraft draft,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('¿Cancelar este viaje?'),
        content: Text(
          'Esta acción finalizará el viaje actual.\n\n'
          'Motivo: ${draft.reason.label}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sí, cancelar viaje'),
          ),
        ],
      );
    },
  );
}

class _DriverCancelReasonSheet extends StatefulWidget {
  const _DriverCancelReasonSheet();

  @override
  State<_DriverCancelReasonSheet> createState() =>
      _DriverCancelReasonSheetState();
}

class _DriverCancelReasonSheetState extends State<_DriverCancelReasonSheet> {
  late final TextEditingController _detailController;

  DriverCancellationReason? _selectedReason;
  String? _detailError;

  @override
  void initState() {
    super.initState();
    _detailController = TextEditingController();
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  void _selectReason(DriverCancellationReason reason) {
    setState(() {
      _selectedReason = reason;
    });
  }

  void _continue() {
    final reason = _selectedReason;

    if (reason == null) {
      return;
    }

    final validationError = driverCancelDetailValidationError(
      _detailController.text,
    );

    if (validationError != null) {
      setState(() {
        _detailError = validationError;
      });

      return;
    }

    final trimmedDetail = _detailController.text.trim();

    Navigator.of(context).pop(
      DriverCancelRideDraft(
        reason: reason,
        reasonDetail: trimmedDetail.isEmpty ? null : trimmedDetail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedReason != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Selecciona un motivo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                '¿Por qué quieres cancelar?',
                style: TextStyle(color: DriverPalette.brown),
              ),
              const SizedBox(height: 12),
              ...DriverCancellationReason.values.map((reason) {
                final selected = reason == _selectedReason;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => _selectReason(reason),
                  leading: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected
                        ? DriverPalette.greenPrimary
                        : DriverPalette.brown,
                  ),
                  title: Text(reason.label),
                );
              }),
              const SizedBox(height: 8),
              TextField(
                key: const Key('driver-cancel-detail-field'),
                controller: _detailController,
                maxLength: driverCancelDetailMaxLength,
                maxLines: 3,
                minLines: 1,
                onChanged: (_) {
                  if (_detailError != null) {
                    setState(() {
                      _detailError = null;
                    });
                  }
                },
                decoration: InputDecoration(
                  labelText: 'Cuéntanos un poco más (opcional)',
                  errorText: _detailError,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: canContinue ? _continue : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
