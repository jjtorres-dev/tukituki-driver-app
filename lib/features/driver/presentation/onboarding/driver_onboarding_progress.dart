import 'package:flutter/material.dart';

import '../../../../core/theme/driver_palette.dart';

/// Los 5 pasos del formulario de onboarding de Driver (decisión de
/// producto ya cerrada). "Solicitud en revisión" ocurre después del
/// envío y deliberadamente no es un paso numerado más — ver
/// `estado-proyecto.md` sección 8.
const List<String> driverOnboardingStepLabels = [
  'Tu cuenta',
  'Sobre ti',
  'Tu mototaxi',
  'Tus documentos',
  'Revisar y enviar',
];

/// Foundation visual reutilizable del progreso del onboarding.
///
/// `currentStep` es 1-based (1 = "Tu cuenta"). Pasos anteriores se
/// muestran completados, el actual resaltado, los siguientes en
/// gris — sin implicar que ya sean navegables: en este checkpoint
/// solo el paso 1 tiene pantalla real.
class DriverOnboardingProgress extends StatelessWidget {
  const DriverOnboardingProgress({super.key, required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(driverOnboardingStepLabels.length, (index) {
        final stepNumber = index + 1;
        final isDone = stepNumber < currentStep;
        final isCurrent = stepNumber == currentStep;
        final isLast = index == driverOnboardingStepLabels.length - 1;

        final dotColor = isDone || isCurrent
            ? DriverPalette.greenPrimary
            : const Color(0xFFE7E0CB);

        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                    child: isDone
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : Text(
                            '$stepNumber',
                            style: TextStyle(
                              color: isCurrent
                                  ? Colors.white
                                  : const Color(0xFF9A8F6E),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: isDone
                        ? DriverPalette.greenPrimary
                        : const Color(0xFFE7E0CB),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}
