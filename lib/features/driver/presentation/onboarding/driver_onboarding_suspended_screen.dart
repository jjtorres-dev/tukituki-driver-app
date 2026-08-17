import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../domain/driver_application.dart';
import 'driver_onboarding_scaffold.dart';

/// `DriverProfile.status == SUSPENDED`. No permite Home,
/// Solicitudes, Ingresos ni ninguna operación de Driver — solo
/// cerrar sesión. Sin canal de apelación todavía (no inventado).
class DriverOnboardingSuspendedScreen extends ConsumerWidget {
  const DriverOnboardingSuspendedScreen({super.key, this.application});

  final DriverApplication? application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = application?.suspensionReason;

    return DriverOnboardingScaffold(
      icon: Icons.block_rounded,
      title: 'Cuenta de conductor suspendida',
      subtitle:
          'Tu cuenta de conductor está suspendida temporalmente. No '
          'puedes recibir ni aceptar viajes mientras esté en este '
          'estado.',
      footer: TextButton(
        key: const Key('suspended-logout-button'),
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(foregroundColor: DriverPalette.orangeDeep),
        child: const Text('Cerrar sesión'),
      ),
      children: [
        if (reason != null && reason.isNotEmpty)
          DriverOnboardingInfoCard(
            label: 'MOTIVO INDICADO POR TUKITUKI',
            message: reason,
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
