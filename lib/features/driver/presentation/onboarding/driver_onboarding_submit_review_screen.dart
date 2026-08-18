import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/domain/driver_session_state.dart';
import '../../data/driver_profile_repository.dart';
import '../../domain/driver_application.dart';
import '../../domain/driver_document.dart';
import '../../domain/driver_vehicle.dart';
import 'driver_onboarding_about_you_screen.dart';
import 'driver_onboarding_progress.dart';
import 'driver_onboarding_vehicle_screen.dart';

String _formatIsoDateDisplay(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) {
    return '';
  }

  final parts = isoDate.split('-');

  if (parts.length != 3) {
    return '';
  }

  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

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

enum _SubmitErrorAction { none, profile, vehicle, documents }

/// Paso 5 del onboarding de Driver: "Revisar y enviar"
/// (`DRIVER-ONBOARDING-R3.7`).
///
/// Nombrada `...SubmitReviewScreen` (no `...ReviewScreen`) a propósito
/// para no colisionar con `DriverOnboardingReviewScreen`
/// (`driver_onboarding_review_screen.dart`), la pantalla ya existente
/// de "Solicitud en revisión" para `PENDING_REVIEW` — son conceptos
/// distintos que casi comparten nombre.
///
/// Solo llega aquí `DriverSessionKind.draftDocumentsComplete` (ver
/// `driver_onboarding_routes.dart`). `initialState` llega ya resuelto
/// vía `extra` (mismo `DriverSessionState` que `resolveSessionState()`
/// calculó para decidir el routing) — evita 3 GETs redundantes
/// (`drivers/me`, `drivers/me/vehicle`, `drivers/me/documents`). Si
/// llega `null` (ruta abierta directamente, o después de una edición)
/// o su `kind` ya no es `draftDocumentsComplete`, resuelve de nuevo y
/// se autocorrige navegando a donde corresponda.
class DriverOnboardingSubmitReviewScreen extends ConsumerStatefulWidget {
  const DriverOnboardingSubmitReviewScreen({super.key, this.initialState});

  final DriverSessionState? initialState;

  @override
  ConsumerState<DriverOnboardingSubmitReviewScreen> createState() =>
      _DriverOnboardingSubmitReviewScreenState();
}

class _DriverOnboardingSubmitReviewScreenState
    extends ConsumerState<DriverOnboardingSubmitReviewScreen> {
  DriverApplication? _application;
  DriverVehicle? _vehicle;
  List<DriverDocument>? _documents;

  bool _loading = true;
  bool _loadError = false;
  bool _submitting = false;

  String? _submitErrorMessage;
  _SubmitErrorAction _submitErrorAction = _SubmitErrorAction.none;

  @override
  void initState() {
    super.initState();

    if (_isUsable(widget.initialState)) {
      _assignFromState(widget.initialState!);
    } else {
      _loadFresh();
    }
  }

  /// `DRIVER-ONBOARDING-R3.7.2` (hotfix stale-review-after-edit): esta
  /// pantalla se reabre navegando a la misma ruta (`context.go(review,
  /// extra: freshState)` desde las pantallas de edición) — GoRouter
  /// puede reutilizar el `State` existente para esa ruta en vez de
  /// recrearlo, así que `initState()` no vuelve a ejecutarse y
  /// `widget.initialState` cambia sin que nadie lo consuma. Sin este
  /// `didUpdateWidget`, la pantalla seguía mostrando los datos con los
  /// que se abrió originalmente (confirmado por prueba física de
  /// JuanJo y reproducido en tests antes de este fix).
  @override
  void didUpdateWidget(covariant DriverOnboardingSubmitReviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.initialState, oldWidget.initialState) &&
        _isUsable(widget.initialState)) {
      setState(() {
        _assignFromState(widget.initialState!);
      });
    }
  }

  bool _isUsable(DriverSessionState? state) {
    return state != null &&
        state.kind == DriverSessionKind.draftDocumentsComplete;
  }

  /// Reemplaza los tres campos juntos desde la misma fuente — nunca
  /// conserva datos parciales de un `state` anterior. Llamador
  /// responsable de envolver en `setState` cuando corresponda (nunca
  /// dentro de `initState`, donde alcanza con asignar directamente).
  void _assignFromState(DriverSessionState state) {
    _application = state.application;
    _vehicle = state.vehicle;
    _documents = state.documents;
    _loading = false;
    _loadError = false;
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

      if (state.kind != DriverSessionKind.draftDocumentsComplete) {
        goToDriverSessionRoute(context, state);
        return;
      }

      setState(() {
        _application = state.application;
        _vehicle = state.vehicle;
        _documents = state.documents;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Error cargando resumen Driver: $error');

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

  Future<void> _editProfile() async {
    if (_submitting) {
      return;
    }

    final application = _application;

    if (application == null) {
      return;
    }

    await context.push(
      DriverOnboardingRoutes.aboutYou,
      extra: DriverOnboardingAboutYouScreenArgs(profile: application),
    );

    if (!mounted) {
      return;
    }

    await _loadFresh();
  }

  Future<void> _editVehicle() async {
    if (_submitting) {
      return;
    }

    final vehicle = _vehicle;

    if (vehicle == null) {
      return;
    }

    await context.push(
      DriverOnboardingRoutes.vehicle,
      extra: DriverOnboardingVehicleScreenArgs(vehicle: vehicle),
    );

    if (!mounted) {
      return;
    }

    await _loadFresh();
  }

  Future<void> _editDocuments() async {
    if (_submitting) {
      return;
    }

    await context.push(DriverOnboardingRoutes.documents);

    if (!mounted) {
      return;
    }

    await _loadFresh();
  }

  void _onSubmitErrorAction() {
    switch (_submitErrorAction) {
      case _SubmitErrorAction.profile:
        unawaited(_editProfile());
      case _SubmitErrorAction.vehicle:
        unawaited(_editVehicle());
      case _SubmitErrorAction.documents:
        unawaited(_editDocuments());
      case _SubmitErrorAction.none:
        break;
    }
  }

  Future<void> _confirmAndSubmit() async {
    if (_submitting) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _SubmitConfirmationDialog(),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _submit();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
      _submitErrorMessage = null;
      _submitErrorAction = _SubmitErrorAction.none;
    });

    final profileRepository = ref.read(driverProfileRepositoryProvider);
    final authRepository = ref.read(authRepositoryProvider);

    try {
      final result = await profileRepository.submitApplication();

      if (!mounted) {
        return;
      }

      if (result.status == DriverApplicationStatus.pendingReview) {
        context.go(DriverOnboardingRoutes.reviewStatus);
        return;
      }

      setState(() {
        _submitErrorMessage = _genericSubmitErrorMessage;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      await _handleSubmitFailure(authRepository, error);
    } catch (error) {
      debugPrint('Error inesperado enviando solicitud Driver: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _submitErrorMessage = _genericSubmitErrorMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _handleSubmitFailure(
    AuthRepository authRepository,
    DioException error,
  ) async {
    final statusCode = error.response?.statusCode;

    if (statusCode == 401) {
      await authRepository.clearSession();

      if (!mounted) {
        return;
      }

      context.go(DriverOnboardingRoutes.login);
      return;
    }

    if (statusCode == 400) {
      final requirements = _stringListFromResponse(
        error.response?.data,
        'missingRequirements',
      );

      if (requirements.isNotEmpty) {
        final (message, action) = _forMissingRequirements(requirements);

        setState(() {
          _submitErrorMessage = message;
          _submitErrorAction = action;
        });
        return;
      }

      final invalid = _stringListFromResponse(
        error.response?.data,
        'invalidRequirements',
      );

      if (invalid.isNotEmpty) {
        final (message, action) = _forInvalidRequirements(invalid);

        setState(() {
          _submitErrorMessage = message;
          _submitErrorAction = action;
        });
        return;
      }

      /*
       * Un 400 sin arrays estructurados solo puede ser
       * `assertProfileCanBeSubmitted` (la solicitud ya no está en
       * DRAFT/REJECTED) — típicamente una carrera de doble-submit.
       * Confirmar el estado real antes de mostrar cualquier error.
       */
      await _recoverAfterAmbiguousFailure(authRepository);
      return;
    }

    /*
     * Errores de red/timeout/5xx: no hay forma de saber si el submit
     * ya ocurrió en Backend. Confirmar vía GET antes de asumir éxito
     * o fracaso.
     */
    await _recoverAfterAmbiguousFailure(authRepository);
  }

  Future<void> _recoverAfterAmbiguousFailure(
    AuthRepository authRepository,
  ) async {
    try {
      final application = await authRepository.getDriverProfile();

      if (!mounted) {
        return;
      }

      if (application?.status == DriverApplicationStatus.pendingReview) {
        context.go(DriverOnboardingRoutes.reviewStatus);
        return;
      }

      setState(() {
        _submitErrorMessage =
            'No pudimos confirmar el envío de tu solicitud. '
            'Revisa tu conexión e inténtalo nuevamente.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitErrorMessage =
            'No pudimos confirmar el envío de tu solicitud. '
            'Revisa tu conexión e inténtalo nuevamente.';
      });
    }
  }

  Future<void> _exitToLogin() async {
    if (_submitting) {
      return;
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.logout();
    } catch (error) {
      debugPrint('Error cerrando sesión desde Revisar y enviar: $error');
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
          key: const Key('review-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _submitting ? null : _exitToLogin,
        ),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('review-loading'),
        child: CircularProgressIndicator(color: DriverPalette.greenPrimary),
      );
    }

    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('review-load-error'),
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
                key: const Key('review-retry-button'),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DriverOnboardingProgress(currentStep: 5),
          const SizedBox(height: 24),
          const Text(
            'Revisar y enviar',
            style: TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Verifica que tu información esté correcta antes de enviar '
            'tu solicitud.',
            style: TextStyle(
              color: DriverPalette.brown,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _buildProfileSection(application),
          const SizedBox(height: 16),
          _buildVehicleSection(vehicle),
          const SizedBox(height: 16),
          _buildDocumentsSection(),
          const SizedBox(height: 20),
          const Text(
            'Al enviar, tu solicitud será revisada por el equipo '
            'TukiTuki.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DriverPalette.brown,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_submitErrorMessage != null) ...[
            const SizedBox(height: 16),
            _SubmitErrorBanner(
              message: _submitErrorMessage!,
              actionLabel: _labelForSubmitAction(_submitErrorAction),
              onAction: _submitErrorAction == _SubmitErrorAction.none
                  ? null
                  : _onSubmitErrorAction,
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: FilledButton(
              key: const Key('review-submit-button'),
              onPressed: _submitting ? null : _confirmAndSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: DriverPalette.greenPrimary,
                foregroundColor: DriverPalette.cream,
                disabledBackgroundColor: DriverPalette.greenPrimary.withValues(
                  alpha: 0.7,
                ),
                disabledForegroundColor: DriverPalette.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                elevation: 0,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _submitting
                    ? const Row(
                        key: ValueKey('review-submitting'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: DriverPalette.cream,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Enviando...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Enviar solicitud',
                        key: ValueKey('review-ready'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(DriverApplication application) {
    final email = application.email;
    final hasEmail = email != null && email.isNotEmpty;

    return _ReviewSectionCard(
      title: 'Sobre ti',
      editKey: const Key('review-profile-edit-button'),
      onEdit: _editProfile,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _ProfilePhotoPreview(photoUrl: application.photoUrl)),
          const SizedBox(height: 14),
          Text(
            '${application.firstName} ${application.lastName}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _ReviewField(
            label: application.documentType.label,
            value: application.documentNumber ?? '',
          ),
          _ReviewField(
            label: 'Fecha de nacimiento',
            value: _formatIsoDateDisplay(application.birthDate),
          ),
          _ReviewField(
            label: 'Correo',
            value: hasEmail ? email : 'No registrado',
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleSection(DriverVehicle vehicle) {
    return _ReviewSectionCard(
      title: 'Tu mototaxi',
      editKey: const Key('review-vehicle-edit-button'),
      onEdit: _editVehicle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ReviewField(label: 'Placa', value: vehicle.plate),
          _ReviewField(
            label: 'Marca / Modelo',
            value: '${vehicle.brand} · ${vehicle.model}',
          ),
          _ReviewField(label: 'Año', value: vehicle.year.toString()),
          _ReviewField(label: 'Color', value: vehicle.color),
          _ReviewField(label: 'Propiedad', value: vehicle.ownership.label),
        ],
      ),
    );
  }

  Widget _buildDocumentsSection() {
    return _ReviewSectionCard(
      title: 'Tus documentos',
      editKey: const Key('review-documents-edit-button'),
      onEdit: _editDocuments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final type in requiredDriverOnboardingDocumentTypes)
            _buildDocumentRow(type),
        ],
      ),
    );
  }

  Widget _buildDocumentRow(DriverDocumentType type) {
    final document = _documentOfType(type);
    final needsExpiry =
        type == DriverDocumentType.driverLicense ||
        type == DriverDocumentType.soat;

    final subtitle = needsExpiry
        ? 'N.º ${document?.documentNumber ?? ''} · vence '
              '${_formatIsoDateDisplay(document?.expiresAt)}'
        : 'N.º ${document?.documentNumber ?? ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.check_circle,
            color: DriverPalette.greenAvailable,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titleForDocumentType(type),
                  style: const TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: DriverPalette.brown,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _genericSubmitErrorMessage =
    'No pudimos enviar tu solicitud. Inténtalo nuevamente.';

String _labelForSubmitAction(_SubmitErrorAction action) {
  switch (action) {
    case _SubmitErrorAction.profile:
      return 'Revisar datos personales';
    case _SubmitErrorAction.vehicle:
      return 'Revisar mototaxi';
    case _SubmitErrorAction.documents:
      return 'Revisar documentos';
    case _SubmitErrorAction.none:
      return '';
  }
}

/// Códigos reales de `getMissingRequirements`
/// (`driver-application-submission.service.ts`).
(String, _SubmitErrorAction) _forMissingRequirements(
  List<String> requirements,
) {
  if (requirements.contains('DRIVER_PROFILE_PHOTO')) {
    return (
      'Falta información en tus datos personales.',
      _SubmitErrorAction.profile,
    );
  }

  if (requirements.contains('DRIVER_VEHICLE')) {
    return ('Falta información de tu mototaxi.', _SubmitErrorAction.vehicle);
  }

  return ('Falta información en tus documentos.', _SubmitErrorAction.documents);
}

/// Códigos reales de `getInvalidRequirements`/`validateDocument`/
/// `validateExpiringDocument` (mismo archivo que arriba).
(String, _SubmitErrorAction) _forInvalidRequirements(
  List<String> requirements,
) {
  if (requirements.contains('DRIVER_LICENSE_EXPIRED')) {
    return (
      'Tu licencia de conducir venció. Actualízala antes de enviar tu '
          'solicitud.',
      _SubmitErrorAction.documents,
    );
  }

  if (requirements.contains('SOAT_EXPIRED')) {
    return (
      'Tu SOAT venció. Actualízalo antes de enviar tu solicitud.',
      _SubmitErrorAction.documents,
    );
  }

  if (requirements.any((r) => r.startsWith('DRIVER_VEHICLE'))) {
    return (
      'Revisa los datos de tu mototaxi antes de enviar la solicitud.',
      _SubmitErrorAction.vehicle,
    );
  }

  final documentPrefixes = ['DRIVER_LICENSE', 'SOAT', 'VEHICLE_REGISTRATION'];

  if (requirements.any(
    (r) => documentPrefixes.any((prefix) => r.startsWith(prefix)),
  )) {
    return (
      'Revisa tus documentos antes de enviar la solicitud.',
      _SubmitErrorAction.documents,
    );
  }

  return (
    'Revisa tus datos personales antes de enviar la solicitud.',
    _SubmitErrorAction.profile,
  );
}

List<String> _stringListFromResponse(Object? data, String key) {
  if (data is! Map) {
    return const [];
  }

  final value = data[key];

  if (value is! List) {
    return const [];
  }

  return value.map((item) => item.toString()).toList();
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7C8A79),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewSectionCard extends StatelessWidget {
  const _ReviewSectionCard({
    required this.title,
    required this.editKey,
    required this.onEdit,
    required this.child,
  });

  final String title;
  final Key editKey;
  final VoidCallback onEdit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E0CB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              TextButton(
                key: editKey,
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: DriverPalette.greenAvailable,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Editar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ProfilePhotoPreview extends StatelessWidget {
  const _ProfilePhotoPreview({required this.photoUrl});

  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final hasUrl = photoUrl != null && photoUrl!.isNotEmpty;

    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: DriverPalette.greenPrimary, width: 2),
          ),
          child: hasUrl
              ? ClipOval(
                  child: Image.network(
                    photoUrl!,
                    key: const Key('review-profile-photo'),
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.person_rounded,
                        color: DriverPalette.greenPrimary,
                        size: 32,
                      );
                    },
                  ),
                )
              : const Icon(
                  Icons.person_rounded,
                  color: DriverPalette.greenPrimary,
                  size: 32,
                ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Foto cargada',
          style: TextStyle(
            color: Color(0xFF7C8A79),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SubmitErrorBanner extends StatelessWidget {
  const _SubmitErrorBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('review-submit-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DriverPalette.coral),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              color: DriverPalette.coral,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 8),
            TextButton(
              key: const Key('review-submit-error-action'),
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: DriverPalette.orangeDeep,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
              ),
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubmitConfirmationDialog extends StatelessWidget {
  const _SubmitConfirmationDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Enviar tu solicitud?'),
      content: const Text(
        'Tu información será enviada al equipo TukiTuki para revisión.'
        '\n\n'
        'Mientras tu solicitud esté en revisión no podrás modificar '
        'tus datos.',
      ),
      actions: [
        TextButton(
          key: const Key('review-confirm-cancel-button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('review-confirm-submit-button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Enviar solicitud'),
        ),
      ],
    );
  }
}
