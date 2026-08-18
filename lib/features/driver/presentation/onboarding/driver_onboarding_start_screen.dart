import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import 'driver_onboarding_progress.dart';
import 'driver_onboarding_scaffold.dart';

/// Foundation de DRAFT con documentos ya completos
/// (`DriverSessionKind.draftDocumentsComplete`): "Sobre ti", "Tu
/// mototaxi" y "Tus documentos" ya se completaron
/// (`DRIVER-ONBOARDING-R3.4`/`R3.5`/`R3.6`) — en este checkpoint
/// todavía no existe el paso "Revisar y enviar", así que ese caso
/// llega aquí como la siguiente pantalla real disponible (ver
/// `decisiones.md`, "no inventar lastCompletedStep"). NO_PROFILE,
/// DRAFT-sin-vehículo y DRAFT-con-documentos-incompletos ya no llegan
/// aquí — van directo a sus pantallas reales ("Sobre ti"/"Tu
/// mototaxi"/"Tus documentos").
class DriverOnboardingStartScreen extends ConsumerWidget {
  const DriverOnboardingStartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DriverOnboardingScaffold(
      icon: Icons.assignment_outlined,
      title: 'Completemos tu solicitud',
      subtitle:
          'Ya completaste tus datos, tu mototaxi y tus documentos. '
          'En el siguiente paso podrás revisar toda tu información '
          'antes de enviar tu solicitud.',
      footer: TextButton(
        key: const Key('onboarding-start-logout-button'),
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(foregroundColor: DriverPalette.orangeDeep),
        child: const Text('Cerrar sesión'),
      ),
      children: const [
        SizedBox(height: 4),
        DriverOnboardingProgress(currentStep: 5),
        SizedBox(height: 20),
        DriverOnboardingInfoCard(
          label: 'PRÓXIMO PASO',
          message:
              'Revisar y enviar. Te avisaremos apenas puedas '
              'continuar.',
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
