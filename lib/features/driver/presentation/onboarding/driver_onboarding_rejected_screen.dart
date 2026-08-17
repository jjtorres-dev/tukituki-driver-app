import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../domain/driver_application.dart';
import 'driver_onboarding_scaffold.dart';

class DriverOnboardingRejectedScreen extends ConsumerWidget {
  const DriverOnboardingRejectedScreen({super.key, this.application});

  final DriverApplication? application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = application?.rejectionReason;

    return DriverOnboardingScaffold(
      icon: Icons.error_outline_rounded,
      title: 'Tu solicitud necesita correcciones',
      subtitle:
          'Revisamos tu solicitud de conductor y encontramos algo que '
          'necesitas corregir antes de continuar.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton(
              key: const Key('rejected-fix-button'),
              onPressed: () => context.go(DriverOnboardingRoutes.start),
              style: FilledButton.styleFrom(
                backgroundColor: DriverPalette.greenPrimary,
                foregroundColor: DriverPalette.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Corregir solicitud',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('rejected-logout-button'),
            onPressed: () => _logout(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: DriverPalette.orangeDeep,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
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
