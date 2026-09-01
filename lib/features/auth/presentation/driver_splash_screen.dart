import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/driver_onboarding_routes.dart';
import '../../notifications/data/push_message_handler.dart';
import '../../notifications/data/push_registration_coordinator.dart';
import '../data/auth_repository.dart';

class DriverSplashScreen extends ConsumerStatefulWidget {
  const DriverSplashScreen({super.key});

  @override
  ConsumerState<DriverSplashScreen> createState() => _DriverSplashScreenState();
}

class _DriverSplashScreenState extends ConsumerState<DriverSplashScreen>
    with SingleTickerProviderStateMixin {
  static const _darkGreen = Color(0xFF123B26);
  static const _brown = Color(0xFF6B4E14);

  bool _checking = true;
  String? _errorMessage;

  Timer? _initialDelayTimer;
  Completer<void>? _initialDelayCompleter;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    unawaited(_checkSession());
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;

    final completer = _initialDelayCompleter;
    _initialDelayCompleter = null;

    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }

    super.dispose();
  }

  Future<void> _waitInitialDelay() {
    _initialDelayTimer?.cancel();

    final completer = Completer<void>();
    _initialDelayCompleter = completer;

    _initialDelayTimer = Timer(const Duration(milliseconds: 800), () {
      _initialDelayTimer = null;

      if (!completer.isCompleted) {
        completer.complete();
      }

      if (identical(_initialDelayCompleter, completer)) {
        _initialDelayCompleter = null;
      }
    });

    return completer.future;
  }

  Future<void> _checkSession({bool initialDelay = true}) async {
    if (mounted) {
      setState(() {
        _checking = true;
        _errorMessage = null;
      });
    }

    if (initialDelay) {
      await _waitInitialDelay();

      if (!mounted) {
        return;
      }
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      final hasSession = await repository.hasSession();

      if (!mounted) {
        return;
      }

      if (!hasSession) {
        await repository.clearSession();

        if (!mounted) {
          return;
        }

        context.go(DriverOnboardingRoutes.login);
        return;
      }

      final state = await repository.resolveSessionState();

      if (!mounted) {
        return;
      }

      goToDriverSessionRoute(context, state);

      // DRIVER-PUSH-R1 (Etapa 1): registro del dispositivo push, solo
      // con sesión válida. Best-effort y sin `await` — no debe demorar
      // ni condicionar la navegación. El coordinador es provider-scoped
      // (no vive en el `State` de esta pantalla), así que un fallo o
      // demora aquí es inofensivo. El `.catchError` es defensa extra
      // por si algún cambio futuro rompe el contrato "nunca lanza" del
      // coordinador (hoy ya envuelve todo en un try/catch interno).
      unawaited(
        ref
            .read(pushRegistrationCoordinatorProvider)
            .syncDeviceRegistration()
            .catchError((Object error) {
              debugPrint(
                'DRIVER PUSH - syncDeviceRegistration inesperado: $error',
              );
            }),
      );

      // DRIVER-PUSH-R1 (Etapa 2): arranca el handler que muestra el
      // aviso local cuando llega una propuesta con la app en
      // foreground. `start()` es una suscripción síncrona a un stream
      // (no retorna Future), por eso no lleva `unawaited`. Es
      // idempotente y best-effort; el try/catch es defensa extra por
      // si algún cambio futuro rompe el contrato "nunca lanza".
      try {
        ref.read(pushMessageHandlerProvider).start();
      } catch (error) {
        debugPrint(
          'DRIVER PUSH - PushMessageHandler.start() falló: $error',
        );
      }
    } on DioException catch (error) {
      debugPrint(
        'Error HTTP restaurando sesión Driver: '
        '${error.response?.statusCode} '
        '${error.requestOptions.path} '
        '${error.type}',
      );

      if (error.response?.statusCode == 401) {
        await repository.clearSession();

        if (!mounted) {
          return;
        }

        context.go(DriverOnboardingRoutes.login);
        return;
      }

      _showRecoverableError(_messageForDioError(error));
    } catch (error) {
      debugPrint('Error restaurando sesión Driver: $error');

      // Un fallo temporal o inesperado no demuestra
      // que la sesión haya dejado de ser válida.
      _showRecoverableError(
        'No pudimos recuperar tu sesión en este momento. '
        'Intenta nuevamente.',
      );
    }
  }

  void _showRecoverableError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _checking = false;
      _errorMessage = message;
    });
  }

  String _messageForDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TukiTuki está tardando más de lo esperado. '
            'Tu sesión se mantiene guardada.';

      case DioExceptionType.connectionError:
        return 'No pudimos conectarnos con TukiTuki. '
            'Revisa tu conexión e intenta nuevamente.';

      default:
        final statusCode = error.response?.statusCode;

        if (statusCode != null && statusCode >= 500) {
          return 'El servidor de TukiTuki no está disponible '
              'temporalmente. Tu sesión se mantiene guardada.';
        }

        return 'No pudimos recuperar tu sesión en este momento. '
            'Intenta nuevamente.';
    }
  }

  Future<void> _goToLogin() async {
    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.clearSession();
    } catch (error) {
      debugPrint('Error limpiando sesión Driver: $error');
    }

    if (!mounted) {
      return;
    }

    context.go(DriverOnboardingRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFDD6B),
                Color(0xFFFFC72C),
                Color(0xFFE8951A),
                Color(0xFFC97313),
              ],
              stops: [0, 0.4, 0.74, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned(
                top: -100,
                right: -80,
                child: _SplashHalo(size: 280),
              ),
              const Positioned(
                bottom: -120,
                left: -100,
                child: _SplashHalo(size: 320),
              ),
              const CustomPaint(painter: _SplashBackgroundPainter()),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 700;

                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 12 : 24,
                        24,
                        compact ? 14 : 22,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const _DriverModeBadge(),
                                    SizedBox(height: compact ? 10 : 18),
                                    _AnimatedDriverLogo(
                                      animation: _pulseController,
                                      compact: compact,
                                    ),
                                    SizedBox(height: compact ? 8 : 14),
                                    const Text(
                                      'TukiTuki',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _darkGreen,
                                        fontSize: 29,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    const Text(
                                      'Conductor',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _darkGreen,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 12 : 20),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      child: _checking
                                          ? _SessionLoading(
                                              animation: _pulseController,
                                            )
                                          : _SplashError(
                                              message:
                                                  _errorMessage ??
                                                  'No pudimos recuperar tu sesión.',
                                              onRetry: () => unawaited(
                                                _checkSession(
                                                  initialDelay: false,
                                                ),
                                              ),
                                              onGoToLogin: _goToLogin,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Prepara tu mototaxi, ya casi estás en línea',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _brown,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverModeBadge extends StatelessWidget {
  const _DriverModeBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Modo conductor',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF123B26).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: const Color(0xFFFFDD6B).withValues(alpha: 0.8),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF123B26).withValues(alpha: 0.2),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_taxi_rounded, size: 16, color: Color(0xFFFFC72C)),
            SizedBox(width: 7),
            Text(
              'MODO CONDUCTOR',
              style: TextStyle(
                color: Color(0xFFFFF9EC),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDriverLogo extends StatelessWidget {
  const _AnimatedDriverLogo({required this.animation, required this.compact});

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final extent = compact ? 170.0 : 220.0;
    final logoWidth = compact ? 150.0 : 184.0;

    return SizedBox(
      width: extent,
      height: extent * 0.72,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final pulse = animation.value;
          final secondaryPulse = (pulse + 0.48) % 1;

          return Stack(
            alignment: Alignment.center,
            children: [
              _PulseRing(progress: pulse, diameter: extent * 0.68),
              _PulseRing(progress: secondaryPulse, diameter: extent * 0.58),
              Transform.scale(
                scale: 0.985 + (0.015 * (1 - (pulse - 0.5).abs() * 2)),
                child: child,
              ),
            ],
          );
        },
        child: Container(
          width: logoWidth,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6B4E14).withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/tukituki_driver_logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress, required this.diameter});

  final double progress;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (1 - progress) * 0.24,
      child: Transform.scale(
        scale: 0.82 + (progress * 0.58),
        child: Container(
          width: diameter,
          height: diameter,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF123B26), width: 1.4),
          ),
        ),
      ),
    );
  }
}

class _SessionLoading extends StatelessWidget {
  const _SessionLoading({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('session-loading'),
      children: [
        const Text(
          'Recuperando tu sesión...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6B4E14),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 13),
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = (animation.value - (index * 0.16)) % 1;
                final emphasis = 1 - ((phase - 0.5).abs() * 2);
                return Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFF123B26,
                    ).withValues(alpha: 0.35 + (emphasis * 0.65)),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

class _SplashError extends StatelessWidget {
  const _SplashError({
    required this.message,
    required this.onRetry,
    required this.onGoToLogin,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onGoToLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('session-error'),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9EC).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E0CB)),
      ),
      child: Column(
        children: [
          const Text(
            'No pudimos continuar',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF123B26),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6B4E14),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF123B26),
                foregroundColor: const Color(0xFFFFF9EC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Reintentar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          TextButton(
            onPressed: onGoToLogin,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC97313),
            ),
            child: const Text('Ir al inicio de sesión'),
          ),
        ],
      ),
    );
  }
}

class _SplashHalo extends StatelessWidget {
  const _SplashHalo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFFFFF9EC).withValues(alpha: 0.3),
            const Color(0xFFFFF9EC).withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}

class _SplashBackgroundPainter extends CustomPainter {
  const _SplashBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF123B26).withValues(alpha: 0.055)
      ..strokeWidth = 1.2;

    for (double offset = -size.height; offset < size.width; offset += 64) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height * 0.7, 0),
        linePaint,
      );
    }

    final dotPaint = Paint()
      ..color = const Color(0xFF123B26).withValues(alpha: 0.13);
    final dots = [
      Offset(size.width * 0.1, size.height * 0.2),
      Offset(size.width * 0.86, size.height * 0.28),
      Offset(size.width * 0.16, size.height * 0.72),
      Offset(size.width * 0.82, size.height * 0.79),
      Offset(size.width * 0.7, size.height * 0.1),
    ];
    for (final dot in dots) {
      canvas.drawCircle(dot, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
