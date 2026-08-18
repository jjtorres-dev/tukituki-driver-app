import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/driver_session_state.dart';
import '../../domain/driver_application.dart';
import '../../domain/driver_document.dart';
import '../../domain/driver_vehicle.dart';
import 'driver_onboarding_about_you_screen.dart';
import 'driver_onboarding_documents_screen.dart';
import 'driver_onboarding_progress.dart';
import 'driver_onboarding_vehicle_screen.dart';

String _titleForDocumentType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return 'Licencia de conducir';
    case DriverDocumentType.soat:
      return 'SOAT';
    case DriverDocumentType.vehicleRegistration:
      return 'Tarjeta de propiedad / TIV';
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return '';
  }
}

String _slugForDocumentType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return 'license';
    case DriverDocumentType.soat:
      return 'soat';
    case DriverDocumentType.vehicleRegistration:
      return 'vehicle-registration';
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return 'unknown';
  }
}

/// "Correcciones requeridas" (`DRIVER-ONBOARDING-R3.8`), único destino
/// de `DriverSessionKind.correctionsRequired` mientras haya al menos
/// una observación pendiente — reemplaza por completo a la antigua
/// `DriverOnboardingRejectedScreen`.
///
/// Decisiones acordadas con JuanJo (`decisiones.md`):
/// - B: siempre muestra las 5 secciones (Sobre ti, Tu mototaxi,
///   Licencia, SOAT, TIV) — las observadas con el texto exacto del
///   admin + "Corregir"; el resto "Sin observaciones", sin acción.
/// - C: no se puede editar una sección NO observada desde aquí.
/// - D: "Corregir" en un documento abre Paso 4 enfocado directamente
///   en ese documento (`DriverOnboardingDocumentsScreenArgs`).
/// - E: "Revisar y reenviar" está deshabilitado mientras
///   `hasPendingDriverCorrections` sea `true`.
/// - F: el reenvío reutiliza `DriverOnboardingSubmitReviewScreen` en
///   modo resubmission — esta pantalla no duplica esa UI.
///
/// Mismo patrón `initState`/`didUpdateWidget` que
/// `DriverOnboardingSubmitReviewScreen` (lección `R3.7.2`): las
/// pantallas de corrección navegan de vuelta aquí con `context.push`
/// + `pop`, así que en la práctica siempre se recarga vía
/// `_loadFresh()` al volver — `didUpdateWidget` cubre además el caso
/// de que GoRouter reutilice el `State` si se reabre por `context.go`.
class DriverOnboardingCorrectionsScreen extends ConsumerStatefulWidget {
  const DriverOnboardingCorrectionsScreen({super.key, this.initialState});

  final DriverSessionState? initialState;

  @override
  ConsumerState<DriverOnboardingCorrectionsScreen> createState() =>
      _DriverOnboardingCorrectionsScreenState();
}

class _DriverOnboardingCorrectionsScreenState
    extends ConsumerState<DriverOnboardingCorrectionsScreen> {
  DriverApplication? _application;
  DriverVehicle? _vehicle;
  List<DriverDocument>? _documents;

  bool _loading = true;
  bool _loadError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    if (_isUsable(widget.initialState)) {
      _assignFromState(widget.initialState!);
    } else {
      _loadFresh();
    }
  }

  @override
  void didUpdateWidget(covariant DriverOnboardingCorrectionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.initialState, oldWidget.initialState) &&
        _isUsable(widget.initialState)) {
      setState(() {
        _assignFromState(widget.initialState!);
      });
    }
  }

  bool _isUsable(DriverSessionState? state) {
    return state != null && state.kind == DriverSessionKind.correctionsRequired;
  }

  /// `DRIVER-ONBOARDING-R3.8.2` (hotfix, hallazgo físico): [_busy] se
  /// resetea aquí, junto con los datos — no solo en la continuación de
  /// `_correctProfile`/`_correctVehicle`/`_correctDocument` tras el
  /// `await context.push(...)`. Las pantallas de corrección (Sobre ti/
  /// Tu mototaxi/Documentos) vuelven llamando `goToDriverSessionRoute`
  /// (`context.go`, mismo patrón que `R3.7`), no un `pop()` imperativo
  /// — cuando el destino es esta misma ruta, `context.go` reconstruye
  /// el widget con un `initialState` fresco (consumido por
  /// `didUpdateWidget`) sin que eso garantice, ni con qué prontitud,
  /// que el `Future` de `context.push(...)` originalmente esperado
  /// vaya a completarse. Antes de este fix, `_busy` solo se apagaba en
  /// esa continuación: si nunca llegaba a tiempo, "Revisar y reenviar"
  /// quedaba deshabilitado a pesar de que las tarjetas ya mostraban
  /// datos frescos — reproducido primero con un test que falla contra
  /// el código sin corregir, confirmado físicamente por JuanJo (tuvo
  /// que cerrar y reabrir la app para que se habilitara). Recibir un
  /// estado fresco y usable es, por definición, prueba de que ya no
  /// hay ninguna navegación de corrección en curso.
  void _assignFromState(DriverSessionState state) {
    _application = state.application;
    _vehicle = state.vehicle;
    _documents = state.documents;
    _loading = false;
    _loadError = false;
    _busy = false;
  }

  Future<void> _loadFresh() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });

    final authRepository = ref.read(authRepositoryProvider);

    try {
      final state = await authRepository.resolveSessionState();

      if (!mounted) {
        return;
      }

      if (!_isUsable(state)) {
        goToDriverSessionRoute(context, state);
        return;
      }

      setState(() {
        _assignFromState(state);
      });
    } catch (error) {
      debugPrint('Error cargando correcciones Driver: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  DriverDocument? _documentOfType(DriverDocumentType type) {
    final documents = _documents;

    if (documents == null) {
      return null;
    }

    for (final document in documents) {
      if (document.type == type) {
        return document;
      }
    }

    return null;
  }

  bool get _hasPendingCorrections => hasPendingDriverCorrections(
    application: _application,
    vehicle: _vehicle,
    documents: _documents,
  );

  Future<void> _correctProfile() async {
    if (_busy) {
      return;
    }

    final application = _application;

    if (application == null) {
      return;
    }

    setState(() => _busy = true);

    await context.push(
      DriverOnboardingRoutes.aboutYou,
      extra: DriverOnboardingAboutYouScreenArgs(profile: application),
    );

    if (!mounted) {
      return;
    }

    setState(() => _busy = false);
    await _loadFresh();
  }

  Future<void> _correctVehicle() async {
    if (_busy) {
      return;
    }

    final vehicle = _vehicle;

    if (vehicle == null) {
      return;
    }

    setState(() => _busy = true);

    await context.push(
      DriverOnboardingRoutes.vehicle,
      extra: DriverOnboardingVehicleScreenArgs(vehicle: vehicle),
    );

    if (!mounted) {
      return;
    }

    setState(() => _busy = false);
    await _loadFresh();
  }

  Future<void> _correctDocument(DriverDocumentType type) async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    await context.push(
      DriverOnboardingRoutes.documents,
      extra: DriverOnboardingDocumentsScreenArgs(
        focusDocumentType: type,
        editableDocumentTypes: {type},
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() => _busy = false);
    await _loadFresh();
  }

  /// Vuelve a resolver el estado real (nunca confía en el snapshot
  /// local) antes de navegar a "Revisar y reenviar" — solo así se
  /// respeta la decisión E (gate de reenvío no negociable) incluso si
  /// Backend cambió entre el último `_loadFresh()` y este tap.
  Future<void> _reviewAndResend() async {
    if (_busy || _hasPendingCorrections) {
      return;
    }

    setState(() => _busy = true);

    final authRepository = ref.read(authRepositoryProvider);

    try {
      final state = await authRepository.resolveSessionState();

      if (!mounted) {
        return;
      }

      final stillPending = hasPendingDriverCorrections(
        application: state.application,
        vehicle: state.vehicle,
        documents: state.documents,
      );

      if (state.kind != DriverSessionKind.correctionsRequired || stillPending) {
        goToDriverSessionRoute(context, state);
        return;
      }

      context.go(DriverOnboardingRoutes.review, extra: state);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _exitToLogin() async {
    if (_busy) {
      return;
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.logout();
    } catch (error) {
      debugPrint('Error cerrando sesión desde Correcciones requeridas: $error');
    }

    if (!mounted) {
      return;
    }

    context.go(DriverOnboardingRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        leading: IconButton(
          key: const Key('corrections-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _busy ? null : _exitToLogin,
        ),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('corrections-loading'),
        child: CircularProgressIndicator(color: DriverPalette.greenPrimary),
      );
    }

    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('corrections-load-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No pudimos cargar tu solicitud.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DriverPalette.greenPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('corrections-retry-button'),
                onPressed: _loadFresh,
                style: FilledButton.styleFrom(
                  backgroundColor: DriverPalette.greenPrimary,
                  foregroundColor: DriverPalette.cream,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final application = _application;
    final vehicle = _vehicle;

    if (application == null || vehicle == null) {
      return const SizedBox.shrink();
    }

    final pending = _hasPendingCorrections;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DriverOnboardingProgress(currentStep: 5),
          const SizedBox(height: 24),
          const Text(
            'Correcciones requeridas',
            style: TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            pending
                ? 'El equipo TukiTuki encontró algo que necesitas '
                      'corregir antes de reenviar tu solicitud.'
                : 'Ya corregiste todas las observaciones. Revisa tu '
                      'información y reenvía tu solicitud.',
            style: const TextStyle(
              color: DriverPalette.brown,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _buildProfileSection(application),
          const SizedBox(height: 12),
          _buildVehicleSection(vehicle),
          const SizedBox(height: 12),
          for (final type in requiredDriverOnboardingDocumentTypes) ...[
            _buildDocumentSection(type),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: FilledButton(
              key: const Key('corrections-resend-button'),
              onPressed: (!pending && !_busy) ? _reviewAndResend : null,
              style: FilledButton.styleFrom(
                backgroundColor: DriverPalette.greenPrimary,
                foregroundColor: DriverPalette.cream,
                disabledBackgroundColor: DriverPalette.greenPrimary.withValues(
                  alpha: 0.4,
                ),
                disabledForegroundColor: DriverPalette.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Revisar y reenviar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(DriverApplication application) {
    final reason = application.rejectionReason?.trim();
    final observed = reason != null && reason.isNotEmpty;

    return _CorrectionSectionCard(
      title: 'Sobre ti',
      observed: observed,
      reason: reason,
      correctKey: const Key('corrections-profile-correct-button'),
      onCorrect: _busy ? null : _correctProfile,
    );
  }

  Widget _buildVehicleSection(DriverVehicle vehicle) {
    final observed = vehicle.status == VehicleStatus.rejected;
    final reason = vehicle.rejectionReason?.trim();

    return _CorrectionSectionCard(
      title: 'Tu mototaxi',
      observed: observed,
      reason: reason,
      correctKey: const Key('corrections-vehicle-correct-button'),
      onCorrect: _busy ? null : _correctVehicle,
    );
  }

  Widget _buildDocumentSection(DriverDocumentType type) {
    final document = _documentOfType(type);
    final observed = document?.status == DriverDocumentStatus.rejected;
    final reason = document?.rejectionReason?.trim();
    final slug = _slugForDocumentType(type);

    return _CorrectionSectionCard(
      title: _titleForDocumentType(type),
      observed: observed,
      reason: reason,
      correctKey: Key('corrections-$slug-correct-button'),
      onCorrect: _busy ? null : () => _correctDocument(type),
    );
  }
}

class _CorrectionSectionCard extends StatelessWidget {
  const _CorrectionSectionCard({
    required this.title,
    required this.observed,
    required this.reason,
    required this.correctKey,
    required this.onCorrect,
  });

  final String title;
  final bool observed;
  final String? reason;
  final Key correctKey;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: observed ? DriverPalette.coral : const Color(0xFFE7E0CB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                observed ? Icons.error_outline_rounded : Icons.check_circle,
                color: observed
                    ? DriverPalette.coral
                    : DriverPalette.greenAvailable,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (observed) ...[
            const SizedBox(height: 8),
            Text(
              (reason == null || reason!.isEmpty)
                  ? 'El equipo TukiTuki solicitó una corrección.'
                  : reason!,
              style: const TextStyle(
                color: DriverPalette.brown,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: correctKey,
                onPressed: onCorrect,
                style: FilledButton.styleFrom(
                  backgroundColor: DriverPalette.orangeDeep,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Corregir',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Sin observaciones',
              style: TextStyle(
                color: DriverPalette.brown,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
