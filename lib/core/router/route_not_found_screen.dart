import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/driver/presentation/onboarding/driver_onboarding_scaffold.dart';
import '../theme/driver_palette.dart';
import 'driver_onboarding_routes.dart';

/// Red de seguridad del router: se muestra ante cualquier ruta que
/// `go_router` no logra resolver (via `errorBuilder`).
///
/// Reemplaza al `ErrorScreen` por defecto de go_router, cuyo botón
/// "Home" navega a `/` — una ruta que no existe en esta app y dejaba
/// al usuario sin salida (fue exactamente lo que pasó cuando una
/// notificación push abría la app cerrada con una ruta inválida).
///
/// El único botón navega a `/splash`, el resolver de sesión: siempre
/// existe y decide el destino real (Home si hay conductor aprobado con
/// sesión, Login si no, el paso de onboarding que corresponda, etc.).
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DriverOnboardingScaffold(
      icon: Icons.explore_off_rounded,
      title: 'Pantalla no encontrada',
      subtitle:
          'La pantalla que intentabas abrir no está disponible. '
          'Volvamos al inicio para continuar.',
      footer: SizedBox(
        height: 54,
        width: double.infinity,
        child: FilledButton(
          key: const Key('route-not-found-home-button'),
          onPressed: () => context.go(DriverOnboardingRoutes.splash),
          style: FilledButton.styleFrom(
            backgroundColor: DriverPalette.greenPrimary,
            foregroundColor: DriverPalette.cream,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
            elevation: 0,
          ),
          child: const Text(
            'Volver al inicio',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      children: const [],
    );
  }
}
