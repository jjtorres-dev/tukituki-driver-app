import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/driver_onboarding_routes.dart';
import '../../../core/theme/driver_palette.dart';
import '../../driver/presentation/onboarding/driver_onboarding_progress.dart';
import '../data/auth_repository.dart';

/// Paso 1 del onboarding de Driver: "Tu cuenta".
///
/// Internamente reutiliza `POST auth/register/passenger` (decisión
/// de producto: no existe `POST auth/register/driver`) y nunca
/// muestra al usuario final la palabra "Passenger". Tras registrar,
/// hace login real con las mismas credenciales (el registro NO
/// devuelve sesión) y navega según `resolveSessionState()`.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  /// El registro ya tuvo éxito pero el login posterior falló (p.ej.
  /// por red). Al reintentar, no debemos volver a registrar el
  /// mismo teléfono (Backend respondería 409).
  bool _registered = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
    });

    final phone = _phoneController.text.replaceAll(' ', '').trim();
    final phoneE164 = '+51$phone';
    final repository = ref.read(authRepositoryProvider);

    try {
      if (!_registered) {
        await repository.registerPassenger(
          phoneE164: phoneE164,
          password: _passwordController.text,
        );

        _registered = true;
      }

      await repository.login(
        phoneE164: phoneE164,
        password: _passwordController.text,
      );

      final state = await repository.resolveSessionState();

      if (!mounted) {
        return;
      }

      goToDriverSessionRoute(context, state);
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final isDuplicatePhone = !_registered && error.response?.statusCode == 409;

      if (isDuplicatePhone) {
        // No se espera aquí a propósito: el `finally` de abajo debe
        // apagar el loading ANTES de que el modal quede visible, en
        // vez de quedar bloqueado detrás de él.
        unawaited(_showDuplicatePhoneDialog());
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_messageForError(error))));
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Error inesperado creando cuenta Driver: $error');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos completar el registro. Intenta nuevamente.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Modal centrado exclusivo para "teléfono ya registrado" (409).
  /// Nunca se usa para otros errores (red, validación, inesperados)
  /// — esos siguen mostrándose con el `SnackBar` de siempre.
  Future<void> _showDuplicatePhoneDialog() async {
    final shouldGoToLogin = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => const _DuplicatePhoneDialog(),
    );

    if (shouldGoToLogin == true && mounted) {
      context.go(DriverOnboardingRoutes.login);
    }
  }

  /// Mensaje para el `SnackBar` genérico. El caso 409 (teléfono
  /// duplicado) nunca llega aquí — se maneja aparte con
  /// [_showDuplicatePhoneDialog], antes de que este método se llame.
  String _messageForError(DioException error) {
    final statusCode = error.response?.statusCode;

    if (error.response == null) {
      return 'No se pudo conectar con TukiTuki. Revisa tu conexión.';
    }

    if (statusCode == 400) {
      return 'Revisa los datos ingresados e intenta nuevamente.';
    }

    if (statusCode != null && statusCode >= 500) {
      return 'TukiTuki no está disponible temporalmente. Intenta nuevamente.';
    }

    return 'No pudimos completar el registro. Intenta nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        leading: IconButton(
          key: const Key('create-account-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _loading
              ? null
              : () => context.go(DriverOnboardingRoutes.login),
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
                const DriverOnboardingProgress(currentStep: 1),
                const SizedBox(height: 24),
                const Text(
                  'Tu cuenta',
                  style: TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Crea tu cuenta TukiTuki con tu celular y una '
                  'contraseña. La usarás para iniciar sesión.',
                  style: TextStyle(
                    color: DriverPalette.brown,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('create-account-phone-field'),
                  controller: _phoneController,
                  enabled: !_loading,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  decoration: _decoration(
                    label: 'Número de celular',
                    prefixIcon: Icons.phone_android_rounded,
                    prefixText: '+51  ',
                  ),
                  validator: (value) {
                    final phone = value?.replaceAll(' ', '').trim() ?? '';

                    if (!RegExp(r'^[0-9]{9}$').hasMatch(phone)) {
                      return 'Ingresa un número válido de 9 dígitos';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('create-account-password-field'),
                  controller: _passwordController,
                  enabled: !_loading,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration:
                      _decoration(
                        label: 'Contraseña',
                        prefixIcon: Icons.lock_outline_rounded,
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _obscurePassword = !_obscurePassword;
                                }),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: DriverPalette.greenAvailable,
                          ),
                        ),
                      ),
                  validator: _passwordValidator,
                ),
                const SizedBox(height: 8),
                const Text(
                  '8 a 64 caracteres, con una mayúscula, una '
                  'minúscula y un número.',
                  style: TextStyle(
                    color: Color(0xFF7C8A79),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('create-account-confirm-password-field'),
                  controller: _confirmPasswordController,
                  enabled: !_loading,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration:
                      _decoration(
                        label: 'Confirmar contraseña',
                        prefixIcon: Icons.lock_outline_rounded,
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                }),
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: DriverPalette.greenAvailable,
                          ),
                        ),
                      ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Las contraseñas no coinciden';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    key: const Key('create-account-submit-button'),
                    onPressed: _loading ? null : _submit,
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
                      child: _loading
                          ? const Row(
                              key: ValueKey('create-account-loading'),
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
                                  'Creando cuenta...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Crear cuenta',
                              key: ValueKey('create-account-ready'),
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
          ),
        ),
      ),
    );
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';

    if (password.length < 8 || password.length > 64) {
      return 'Debe tener entre 8 y 64 caracteres';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Incluye al menos una minúscula';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Incluye al menos una mayúscula';
    }

    if (!RegExp(r'\d').hasMatch(password)) {
      return 'Incluye al menos un número';
    }

    return null;
  }

  InputDecoration _decoration({
    required String label,
    required IconData prefixIcon,
    String? prefixText,
  }) {
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: Color(0xFF7C8A79),
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: DriverPalette.greenAvailable,
        fontWeight: FontWeight.w700,
      ),
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        color: DriverPalette.greenPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(prefixIcon, color: DriverPalette.greenAvailable),
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

/// Modal centrado para "número ya registrado" (409 en
/// `auth/register/passenger`), en reemplazo del `SnackBar` anterior
/// (checkpoint `DRIVER-ONBOARDING-R3.3.2`, feedback físico de
/// JuanJo: el SnackBar era invasivo).
///
/// Cierra sin navegar (X o back de Android) o navega a Login (CTA)
/// — nunca reenvía el registro ni toca datos de Backend.
class _DuplicatePhoneDialog extends StatelessWidget {
  const _DuplicatePhoneDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        decoration: BoxDecoration(
          color: DriverPalette.cream,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: DriverPalette.greenPrimary.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('duplicate-phone-dialog-close-button'),
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(
                  Icons.close_rounded,
                  color: DriverPalette.brown,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: 'Cerrar',
              ),
            ),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DriverPalette.greenPrimary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.person_search_rounded,
                color: DriverPalette.amber,
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Número ya registrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DriverPalette.greenPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Este número de celular ya tiene una cuenta en '
              'TukiTuki.\n\nPuedes iniciar sesión para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DriverPalette.brown,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                key: const Key('duplicate-phone-dialog-login-button'),
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: DriverPalette.greenPrimary,
                  foregroundColor: DriverPalette.cream,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Iniciar sesión',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
