import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/driver_onboarding_routes.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.login(
        phoneE164: '+51$phone',
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      /*
       * Ya NO se decide aquí si la cuenta "es conductor": una
       * cuenta PASSENGER-only puede loguearse y postular (decisión
       * de producto). El routing real (onboarding/home/suspendida/
       * etc.) lo resuelve Splash releyendo la sesión recién creada
       * con la misma lógica que usa al reabrir la app.
       */
      context.go(DriverOnboardingRoutes.splash);
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo iniciar sesión.';

      final statusCode = error.response?.statusCode;

      if (statusCode == 401) {
        message = 'Teléfono o contraseña incorrectos.';
      } else if (statusCode == 403) {
        message = 'La cuenta no está habilitada.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      } else if (statusCode != null && statusCode >= 500) {
        message =
            'TukiTuki no está disponible '
            'temporalmente. Intenta nuevamente.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      debugPrint('Error inesperado durante login Driver: $error');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos completar el inicio de sesión. '
            'Intenta nuevamente.',
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

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardOpen = mediaQuery.viewInsets.bottom > 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF9EC),
        body: SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 700;

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LoginHero(
                          compact: compact,
                          keyboardOpen: keyboardOpen,
                        ),
                        Transform.translate(
                          offset: const Offset(0, -1),
                          child: ClipPath(
                            clipper: const _CreamPanelClipper(),
                            child: Container(
                              color: const Color(0xFFFFF9EC),
                              padding: EdgeInsets.fromLTRB(
                                24,
                                compact || keyboardOpen ? 34 : 44,
                                24,
                                24 + mediaQuery.viewPadding.bottom,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                    key: const Key('login-phone-field'),
                                    controller: _phoneController,
                                    enabled: !_loading,
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9),
                                    ],
                                    decoration: _inputDecoration(
                                      label: 'Número de celular',
                                      prefixIcon: Icons.phone_android_rounded,
                                      prefixText: '+51  ',
                                    ),
                                    validator: (value) {
                                      final phone =
                                          value?.replaceAll(' ', '').trim() ??
                                          '';

                                      if (!RegExp(
                                        r'^[0-9]{9}$',
                                      ).hasMatch(phone)) {
                                        return 'Ingresa un número válido '
                                            'de 9 dígitos';
                                      }

                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const Key('login-password-field'),
                                    controller: _passwordController,
                                    enabled: !_loading,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _login(),
                                    decoration:
                                        _inputDecoration(
                                          label: 'Contraseña',
                                          prefixIcon:
                                              Icons.lock_outline_rounded,
                                        ).copyWith(
                                          suffixIcon: IconButton(
                                            key: const Key(
                                              'password-visibility-button',
                                            ),
                                            tooltip: _obscurePassword
                                                ? 'Mostrar contraseña'
                                                : 'Ocultar contraseña',
                                            onPressed: _loading
                                                ? null
                                                : () {
                                                    setState(() {
                                                      _obscurePassword =
                                                          !_obscurePassword;
                                                    });
                                                  },
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                              color: const Color(0xFF1F7A3E),
                                            ),
                                          ),
                                        ),
                                    validator: (value) {
                                      if (value == null || value.length < 8) {
                                        return 'Ingresa tu contraseña';
                                      }

                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '¿Olvidaste tu contraseña?',
                                      style: TextStyle(
                                        color: Color(0xFFC97313),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  SizedBox(
                                    height: 54,
                                    child: FilledButton(
                                      key: const Key('login-submit-button'),
                                      onPressed: _loading ? null : _login,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF123B26,
                                        ),
                                        foregroundColor: const Color(
                                          0xFFFFF9EC,
                                        ),
                                        disabledBackgroundColor: const Color(
                                          0xFF123B26,
                                        ).withValues(alpha: 0.7),
                                        disabledForegroundColor: const Color(
                                          0xFFFFF9EC,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            17,
                                          ),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: _loading
                                            ? const Row(
                                                key: ValueKey('login-loading'),
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Color(
                                                            0xFFFFF9EC,
                                                          ),
                                                        ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Iniciando sesión...',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : const Text(
                                                'Iniciar sesión',
                                                key: ValueKey('login-ready'),
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  const _DriverPartnerCard(),
                                  const SizedBox(height: 20),
                                  const _PassengerAppNote(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
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
        color: Color(0xFF1F7A3E),
        fontWeight: FontWeight.w700,
      ),
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        color: Color(0xFF123B26),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF1F7A3E)),
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
        borderSide: BorderSide(color: Color(0xFF1F7A3E), width: 1.8),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFC97313)),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFC97313), width: 1.8),
      ),
    );
  }
}

class _LoginHero extends StatelessWidget {
  const _LoginHero({required this.compact, required this.keyboardOpen});

  final bool compact;
  final bool keyboardOpen;

  @override
  Widget build(BuildContext context) {
    final logoWidth = keyboardOpen ? 92.0 : (compact ? 120.0 : 146.0);
    final verticalGap = keyboardOpen ? 7.0 : (compact ? 10.0 : 13.0);

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFDD6B), Color(0xFFFFC72C), Color(0xFFE8951A)],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LoginHeroPainter()),
          ),
          Positioned(
            top: -76,
            right: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFFF9EC).withValues(alpha: 0.32),
                    const Color(0xFFFFF9EC).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              keyboardOpen ? 8 : 16,
              24,
              keyboardOpen ? 23 : 34,
            ),
            child: Column(
              children: [
                const Center(child: _LoginDriverModeBadge()),
                SizedBox(height: verticalGap),
                Image.asset(
                  'assets/images/tukituki_driver_logo.png',
                  key: const Key('login-driver-logo'),
                  width: logoWidth,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
                SizedBox(height: keyboardOpen ? 5 : 8),
                Text(
                  'TukiTuki Conductor',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF123B26),
                    fontSize: keyboardOpen ? 24 : 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Inicia sesión para avanzar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6B4E14),
                    fontSize: 15,
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

class _LoginDriverModeBadge extends StatelessWidget {
  const _LoginDriverModeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF123B26).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFFFDD6B).withValues(alpha: 0.8),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_taxi_rounded, size: 15, color: Color(0xFFFFC72C)),
          SizedBox(width: 7),
          Text(
            'MODO CONDUCTOR',
            style: TextStyle(
              color: Color(0xFFFFF9EC),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverPartnerCard extends StatelessWidget {
  const _DriverPartnerCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFFDD6B).withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('login-create-account-link'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go(DriverOnboardingRoutes.account),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE7E0CB)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFC72C),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: EdgeInsets.all(9),
                  child: Icon(
                    Icons.handshake_outlined,
                    size: 20,
                    color: Color(0xFF123B26),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: Color(0xFF6B4E14),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: '¿Aún no eres socio conductor?\n',
                        style: TextStyle(
                          color: Color(0xFF123B26),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: 'Crea tu cuenta',
                        style: TextStyle(
                          color: Color(0xFFC97313),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' y empieza a generar ingresos con tu mototaxi.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassengerAppNote extends StatelessWidget {
  const _PassengerAppNote();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(
        style: TextStyle(
          color: Color(0xFF7C8A79),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(text: '¿Eres pasajero? '),
          TextSpan(
            text: 'Ir a TukiTuki App',
            style: TextStyle(
              color: Color(0xFF1F7A3E),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _CreamPanelClipper extends CustomClipper<Path> {
  const _CreamPanelClipper();

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, 24)
      ..quadraticBezierTo(size.width * 0.26, 0, size.width * 0.52, 14)
      ..quadraticBezierTo(size.width * 0.78, 28, size.width, 6)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _LoginHeroPainter extends CustomPainter {
  const _LoginHeroPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF123B26).withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double offset = -size.height; offset < size.width; offset += 58) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height * 0.72, 0),
        linePaint,
      );
    }

    final dotPaint = Paint()
      ..color = const Color(0xFF123B26).withValues(alpha: 0.13);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.3), 3, dotPaint);
    canvas.drawCircle(
      Offset(size.width * 0.87, size.height * 0.66),
      3,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.74, size.height * 0.17),
      2.4,
      dotPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
