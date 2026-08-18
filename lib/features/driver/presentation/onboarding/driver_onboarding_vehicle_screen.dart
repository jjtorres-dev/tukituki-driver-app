import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_vehicle_repository.dart';
import '../../domain/driver_vehicle.dart';
import 'driver_onboarding_progress.dart';

final _maximumVehicleYear = DateTime.now().year + 1;

/// Datos para abrir "Tu mototaxi" en modo edición desde "Revisar y
/// enviar" (`DRIVER-ONBOARDING-R3.7`). Su sola presencia (`args !=
/// null`) es la única señal que la pantalla necesita para decidir
/// CREATE vs EDIT — sin booleanos adicionales.
class DriverOnboardingVehicleScreenArgs {
  const DriverOnboardingVehicleScreenArgs({required this.vehicle});

  final DriverVehicle vehicle;
}

/// Paso 3 del onboarding de Driver: "Tu mototaxi".
///
/// **Modo CREATE** (`args == null`): solo llega aquí
/// `DriverSessionKind.draftNoVehicle` (ver `driver_onboarding_routes.
/// dart`) — un `DriverVehicle` ya existente significa que este paso
/// ya se completó (relación 1:1 con `DriverProfile`, verificado en
/// `DRIVER-ONBOARDING-R3.5A`).
///
/// Nunca envía `vehicleType` (Backend lo fija a `MOTOTAXI`) ni
/// `engineNumber`/`chassisNumber` (el onboarding nuevo no los pide,
/// decisión ya cerrada) ni `driverProfileId` (Backend lo resuelve
/// por sesión).
///
/// **Modo EDIT** (`args != null`, `DRIVER-ONBOARDING-R3.7`): se abre
/// vía `context.push` desde "Editar" en "Revisar y enviar", con el
/// vehículo precargado. Usa `PATCH drivers/me/vehicle`
/// (`updateVehicle`) en vez de `POST`. Mismo criterio de
/// `Navigator.canPop()` que "Sobre ti" para distinguir el botón de
/// volver: nunca cierra sesión si llegó empujada desde Revisar y
/// enviar.
class DriverOnboardingVehicleScreen extends ConsumerStatefulWidget {
  const DriverOnboardingVehicleScreen({super.key, this.args});

  final DriverOnboardingVehicleScreenArgs? args;

  @override
  ConsumerState<DriverOnboardingVehicleScreen> createState() =>
      _DriverOnboardingVehicleScreenState();
}

class _DriverOnboardingVehicleScreenState
    extends ConsumerState<DriverOnboardingVehicleScreen> {
  final _formKey = GlobalKey<FormState>();

  final _plateController = TextEditingController();
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _colorController = TextEditingController();

  VehicleOwnership? _ownership;
  String? _ownershipError;
  String? _plateError;

  bool _submitting = false;

  bool get _isEditMode => widget.args != null;

  @override
  void initState() {
    super.initState();

    final vehicle = widget.args?.vehicle;

    if (vehicle != null) {
      _plateController.text = vehicle.plate;
      _brandController.text = vehicle.brand;
      _modelController.text = vehicle.model;
      _yearController.text = vehicle.year.toString();
      _colorController.text = vehicle.color;
      _ownership = vehicle.ownership == VehicleOwnership.unknown
          ? null
          : vehicle.ownership;
    }
  }

  @override
  void dispose() {
    _plateController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final formValid = _formKey.currentState?.validate() ?? false;
    final ownership = _ownership;

    setState(() {
      _ownershipError = ownership == null
          ? 'Indica si el mototaxi es propio o alquilado.'
          : null;
    });

    if (!formValid || ownership == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _plateError = null;
    });

    final authRepository = ref.read(authRepositoryProvider);
    final vehicleRepository = ref.read(driverVehicleRepositoryProvider);

    try {
      if (_isEditMode) {
        await vehicleRepository.updateVehicle(
          plate: _plateController.text.trim().toUpperCase(),
          brand: _brandController.text.trim(),
          model: _modelController.text.trim(),
          year: int.parse(_yearController.text.trim()),
          color: _colorController.text.trim(),
          ownership: ownership,
        );
      } else {
        await vehicleRepository.createVehicle(
          plate: _plateController.text.trim().toUpperCase(),
          brand: _brandController.text.trim(),
          model: _modelController.text.trim(),
          year: int.parse(_yearController.text.trim()),
          color: _colorController.text.trim(),
          ownership: ownership,
        );
      }

      if (!mounted) {
        return;
      }

      final freshState = await authRepository.resolveSessionState();

      if (!mounted) {
        return;
      }

      goToDriverSessionRoute(context, freshState);
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      await _handleSubmitError(authRepository, error);
    } catch (error) {
      debugPrint('Error inesperado guardando vehículo Driver: $error');

      if (!mounted) {
        return;
      }

      _showError(
        'No pudimos guardar los datos de tu mototaxi. Inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  /// Un 409 puede significar dos cosas muy distintas en Backend
  /// (`getUniqueConstraintException` en `driver-vehicles.service.ts`):
  /// placa duplicada (error del campo Placa) o — solo en modo CREATE —
  /// el conductor ya tiene un vehículo registrado (se resuelve
  /// consultando el estado real antes de tratarlo como error fatal —
  /// nunca se oculta una inconsistencia en silencio).
  Future<void> _handleSubmitError(
    AuthRepository authRepository,
    DioException error,
  ) async {
    final statusCode = error.response?.statusCode;
    final responseData = error.response?.data;
    final backendMessage = responseData is Map
        ? responseData['message']?.toString()
        : null;

    if (statusCode == 409 && backendMessage == 'La placa ya está registrada') {
      setState(() {
        _plateError = 'Esta placa ya está registrada.';
      });
      return;
    }

    if (statusCode == 409 && !_isEditMode) {
      DriverVehicle? existingVehicle;

      try {
        existingVehicle = await authRepository.getVehicle();
      } on DioException {
        existingVehicle = null;
      }

      if (existingVehicle != null) {
        if (!mounted) {
          return;
        }

        final freshState = await authRepository.resolveSessionState();

        if (!mounted) {
          return;
        }

        goToDriverSessionRoute(context, freshState);
        return;
      }
    }

    _showError(
      'No pudimos guardar los datos de tu mototaxi. Inténtalo nuevamente.',
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Modo EDIT (llegó empujada desde "Revisar y enviar", con pila de
  /// navegación real): solo vuelve atrás, nunca cierra sesión. Modo
  /// CREATE (llegó vía el routing normal con `context.go`, sin pila):
  /// mismo comportamiento de siempre.
  Future<void> _handleBack() async {
    if (_submitting) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }

    await _exitToLogin();
  }

  Future<void> _exitToLogin() async {
    if (_submitting) {
      return;
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.logout();
    } catch (error) {
      debugPrint('Error cerrando sesión desde Tu mototaxi: $error');
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
          key: const Key('vehicle-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _submitting ? null : _handleBack,
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DriverOnboardingProgress(currentStep: 3),
                const SizedBox(height: 24),
                const Text(
                  'Tu mototaxi',
                  style: TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cuéntanos sobre el vehículo que usarás para realizar '
                  'tus viajes.',
                  style: TextStyle(
                    color: DriverPalette.brown,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('vehicle-plate-field'),
                  controller: _plateController,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_plateError != null) {
                      setState(() {
                        _plateError = null;
                      });
                    }
                  },
                  decoration: _decoration(
                    label: 'Placa',
                    errorText: _plateError,
                  ),
                  validator: _plateValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('vehicle-brand-field'),
                  controller: _brandController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(label: 'Marca'),
                  validator: _brandValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('vehicle-model-field'),
                  controller: _modelController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(label: 'Modelo'),
                  validator: _modelValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('vehicle-year-field'),
                  controller: _yearController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: _decoration(label: 'Año'),
                  validator: _yearValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('vehicle-color-field'),
                  controller: _colorController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration(label: 'Color'),
                  validator: _colorValidator,
                ),
                const SizedBox(height: 20),
                const Text(
                  'El mototaxi es',
                  style: TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<VehicleOwnership>(
                  key: const Key('vehicle-ownership-field'),
                  emptySelectionAllowed: true,
                  segments: const [
                    ButtonSegment(
                      value: VehicleOwnership.owned,
                      label: Text('Propio'),
                    ),
                    ButtonSegment(
                      value: VehicleOwnership.rented,
                      label: Text('Alquilado'),
                    ),
                  ],
                  selected: _ownership == null ? const {} : {_ownership!},
                  onSelectionChanged: _submitting
                      ? null
                      : (selection) {
                          setState(() {
                            _ownership = selection.isEmpty
                                ? null
                                : selection.first;
                            _ownershipError = null;
                          });
                        },
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: DriverPalette.greenPrimary,
                    selectedForegroundColor: DriverPalette.cream,
                  ),
                ),
                if (_ownershipError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _ownershipError!,
                    key: const Key('vehicle-ownership-error'),
                    style: const TextStyle(
                      color: DriverPalette.coral,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    key: const Key('vehicle-submit-button'),
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriverPalette.greenPrimary,
                      foregroundColor: DriverPalette.cream,
                      disabledBackgroundColor: DriverPalette.greenPrimary
                          .withValues(alpha: 0.7),
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
                              key: ValueKey('vehicle-loading'),
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
                                  'Guardando...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _isEditMode ? 'Guardar cambios' : 'Continuar',
                              key: const ValueKey('vehicle-ready'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _plateValidator(String? value) {
    final text = value?.trim().toUpperCase() ?? '';

    if (!RegExp(r'^[A-Z0-9-]{5,15}$').hasMatch(text)) {
      return 'Ingresa una placa válida (5 a 15 caracteres)';
    }

    return null;
  }

  String? _brandValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.length < 2 || text.length > 80) {
      return 'Ingresa la marca (2 a 80 caracteres)';
    }

    return null;
  }

  String? _modelValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty || text.length > 80) {
      return 'Ingresa el modelo';
    }

    return null;
  }

  String? _yearValidator(String? value) {
    final year = int.tryParse(value?.trim() ?? '');

    if (year == null || year < 1980 || year > _maximumVehicleYear) {
      return 'Ingresa un año válido (1980–$_maximumVehicleYear)';
    }

    return null;
  }

  String? _colorValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.length < 2 || text.length > 50) {
      return 'Ingresa el color (2 a 50 caracteres)';
    }

    return null;
  }

  InputDecoration _decoration({required String label, String? errorText}) {
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return InputDecoration(
      labelText: label,
      errorText: errorText,
      labelStyle: const TextStyle(
        color: Color(0xFF7C8A79),
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: DriverPalette.greenAvailable,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFFFBF7EA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE7E0CB)),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE7E0CB)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.greenAvailable, width: 1.8),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.orangeDeep),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.orangeDeep, width: 1.8),
      ),
    );
  }
}
