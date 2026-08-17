import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import 'driver_onboarding_scaffold.dart';

/// `DriverProfile.status == PENDING_REVIEW`.
///
/// Copy deliberadamente sin plazos ("24 horas", "hoy mismo", etc.):
/// no existe ningún SLA real documentado que respaldarlo.
class DriverOnboardingReviewScreen extends ConsumerWidget {
  const DriverOnboardingReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DriverOnboardingScaffold(
      icon: Icons.hourglass_top_rounded,
      title: 'Solicitud en revisión',
      subtitle:
          'Recibimos tu solicitud de conductor. El equipo TukiTuki '
          'la está revisando y te avisaremos apenas tengamos una '
          'respuesta.',
      footer: TextButton(
        key: const Key('review-logout-button'),
        onPressed: () => _logout(context, ref),
        style: TextButton.styleFrom(foregroundColor: DriverPalette.orangeDeep),
        child: const Text('Cerrar sesión'),
      ),
      children: const [
        DriverOnboardingInfoCard(
          label: 'ESTADO ACTUAL',
          message:
              'Tu expediente ya fue enviado y está pendiente de '
              'aprobación administrativa.',
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
