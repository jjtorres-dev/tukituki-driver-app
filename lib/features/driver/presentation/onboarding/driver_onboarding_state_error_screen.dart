import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import 'driver_onboarding_scaffold.dart';

/// Última barrera de seguridad para dos casos que nunca deben
/// entrar a Home en silencio:
///
/// - `DriverProfile.status == APPROVED` pero la cuenta todavía no
///   tiene el rol `DRIVER` (inconsistencia entre Backend y el rol
///   de la cuenta).
/// - Un `status` de solicitud que este cliente no reconoce.
///
/// Ninguno de los dos es un error de red: son estados de datos que
/// este checkpoint no puede resolver localmente, así que solo
/// ofrece reintentar o cerrar sesión.
class DriverOnboardingStateErrorScreen extends ConsumerStatefulWidget {
  const DriverOnboardingStateErrorScreen({super.key});

  @override
  ConsumerState<DriverOnboardingStateErrorScreen> createState() =>
      _DriverOnboardingStateErrorScreenState();
}

class _DriverOnboardingStateErrorScreenState
    extends ConsumerState<DriverOnboardingStateErrorScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) {
      return;
    }

    setState(() {
      _checking = true;
    });

    final repository = ref.read(authRepositoryProvider);

    try {
      final state = await repository.resolveSessionState();

      if (!mounted) {
        return;
      }

      goToDriverSessionRoute(context, state);
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final repository = ref.read(authRepositoryProvider);
    await repository.logout();

    if (!mounted) {
      return;
    }

    context.go(DriverOnboardingRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return DriverOnboardingScaffold(
      icon: Icons.report_gmailerrorred_rounded,
      title: 'No pudimos continuar',
      subtitle:
          'Hay una inconsistencia con el estado de tu cuenta que no '
          'podemos resolver desde la app. Intenta nuevamente o '
          'contacta a TukiTuki.',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton(
              key: const Key('state-error-retry-button'),
              onPressed: _checking ? null : _retry,
              style: FilledButton.styleFrom(
                backgroundColor: DriverPalette.greenPrimary,
                foregroundColor: DriverPalette.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                elevation: 0,
              ),
              child: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DriverPalette.cream,
                      ),
                    )
                  : const Text(
                      'Reintentar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('state-error-logout-button'),
            onPressed: _logout,
            style: TextButton.styleFrom(
              foregroundColor: DriverPalette.orangeDeep,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
      children: const [],
    );
  }
}
