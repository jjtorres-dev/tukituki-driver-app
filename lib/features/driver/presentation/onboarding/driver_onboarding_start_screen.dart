import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import 'driver_onboarding_progress.dart';
import 'driver_onboarding_scaffold.dart';

/// Foundation de DRAFT con vehículo ya registrado
/// (`DriverSessionKind.draftWithVehicle`): los pasos "Sobre ti" y "Tu
/// mototaxi" ya se completaron (`DRIVER-ONBOARDING-R3.4`/`R3.5`) — en
/// este checkpoint todavía no existen los pasos "Tus documentos"/
/// "Revisar y enviar", así que ese caso llega aquí como la siguiente
/// pantalla real disponible (ver `decisiones.md`, "no inventar
/// lastCompletedStep"). NO_PROFILE y DRAFT-sin-vehículo ya no llegan
/// aquí — van directo a sus pantallas reales ("Sobre ti"/"Tu
/// mototaxi").
class DriverOnboardingStartScreen extends ConsumerWidget {
  const DriverOnboardingStartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DriverOnboardingScaffold(
      icon: Icons.assignment_outlined,
      title: 'Completemos tu solicitud',
      subtitle:
          'Ya registraste los datos de tu mototaxi. El siguiente '
          'paso será agregar tus documentos.',
      footer: TextButton(
        key: const Key('onboarding-start-logout-button'),
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(foregroundColor: DriverPalette.orangeDeep),
        child: const Text('Cerrar sesión'),
      ),
      children: const [
        SizedBox(height: 4),
        DriverOnboardingProgress(currentStep: 4),
        SizedBox(height: 20),
        DriverOnboardingInfoCard(
          label: 'PRÓXIMOS PASOS',
          message:
              'Tus documentos y Revisar y enviar. Te avisaremos '
              'apenas puedas continuar.',
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(authRepositoryProvider);
    await repository.logout();

    if (context.mounted) {
      context.go(DriverOnboardingRoutes.login);
    }
  }
}
