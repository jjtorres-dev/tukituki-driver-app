import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';

class DriverSplashScreen extends ConsumerStatefulWidget {
  const DriverSplashScreen({super.key});

  @override
  ConsumerState<DriverSplashScreen> createState() => _DriverSplashScreenState();
}

class _DriverSplashScreenState extends ConsumerState<DriverSplashScreen> {
  bool _checking = true;
  String? _errorMessage;

  Timer? _initialDelayTimer;
  Completer<void>? _initialDelayCompleter;

  @override
  void initState() {
    super.initState();
    unawaited(_checkSession());
  }

  @override
  void dispose() {
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

        context.go('/login');
        return;
      }

      final isDriver = await repository.isDriver();

      if (!mounted) {
        return;
      }

      if (!isDriver) {
        await repository.clearSession();

        if (!mounted) {
          return;
        }

        context.go('/login');
        return;
      }

      context.go('/home');
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

        context.go('/login');
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

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.two_wheeler, size: 84),
                const SizedBox(height: 20),
                const Text(
                  'TukiTuki Conductor',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _checking
                      ? 'Recuperando tu sesión...'
                      : 'No pudimos continuar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                if (_checking)
                  const CircularProgressIndicator()
                else ...[
                  Text(
                    _errorMessage ?? 'No pudimos recuperar tu sesión.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      unawaited(_checkSession(initialDelay: false));
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _goToLogin,
                    child: const Text('Ir al inicio de sesión'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
