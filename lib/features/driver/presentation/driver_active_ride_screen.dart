import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_active_ride.dart';
import '../domain/driver_ride_completion.dart';

class _DriverLocationFailure implements Exception {
  const _DriverLocationFailure(this.message);

  final String message;
}

class DriverActiveRideScreen extends ConsumerStatefulWidget {
  const DriverActiveRideScreen({super.key});

  @override
  ConsumerState<DriverActiveRideScreen> createState() =>
      _DriverActiveRideScreenState();
}

class _DriverActiveRideScreenState
    extends ConsumerState<DriverActiveRideScreen> {
  final _codeController = TextEditingController();

  DriverActiveRide? _ride;
  DriverRideCompletion? _completion;

  bool _loading = true;
  bool _changingStatus = false;
  bool _activityInFlight = false;

  String? _error;

  Timer? _rideTimer;
  Timer? _activityTimer;

  @override
  void initState() {
    super.initState();

    unawaited(_loadRide());

    _rideTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadRide(showLoading: false));
    });

    _startActivityTimer();

    unawaited(_sendDriverActivity());
  }

  @override
  void dispose() {
    _rideTimer?.cancel();
    _activityTimer?.cancel();

    _codeController.dispose();

    super.dispose();
  }

  void _startActivityTimer() {
    _activityTimer?.cancel();

    _activityTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_sendDriverActivity());
    });
  }

  Future<Position> _getDriverPosition({required bool requestPermission}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw const _DriverLocationFailure(
        'Activa la ubicación del dispositivo para continuar.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const _DriverLocationFailure(
        'TukiTuki necesita permiso de ubicación para continuar.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const _DriverLocationFailure(
        'El permiso de ubicación está bloqueado. Actívalo desde Ajustes.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } on TimeoutException {
      throw const _DriverLocationFailure(
        'No se pudo obtener una ubicación GPS reciente.',
      );
    }
  }

  Future<void> _publishCurrentLocation({
    required bool requestPermission,
  }) async {
    final position = await _getDriverPosition(
      requestPermission: requestPermission,
    );

    await ref
        .read(driverOperationsRepositoryProvider)
        .updateLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          heading: position.heading,
          speed: position.speed,
          accuracy: position.accuracy,
        );

    debugPrint(
      'DRIVER ACTIVE LOCATION OK '
      'lat=${position.latitude.toStringAsFixed(6)} '
      'lon=${position.longitude.toStringAsFixed(6)} '
      'accuracy=${position.accuracy}',
    );
  }

  Future<void> _sendDriverActivity() async {
    if (_activityInFlight || _completion != null) {
      return;
    }

    _activityInFlight = true;

    try {
      final repository = ref.read(driverOperationsRepositoryProvider);

      await repository.heartbeat();

      await _publishCurrentLocation(requestPermission: false);

      debugPrint(
        'DRIVER ACTIVE ACTIVITY OK '
        'status=${_ride?.status}',
      );
    } on _DriverLocationFailure catch (error) {
      debugPrint(
        'DRIVER ACTIVE LOCATION ERROR '
        '${error.message}',
      );
    } on DioException catch (error) {
      debugPrint(
        'DRIVER ACTIVE ACTIVITY ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );
    } catch (error) {
      debugPrint('DRIVER ACTIVE ACTIVITY ERROR: $error');
    } finally {
      _activityInFlight = false;
    }
  }

  Future<void> _waitForActivityToFinish() async {
    var attempts = 0;

    while (_activityInFlight && attempts < 50) {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      attempts++;
    }
  }

  Future<void> _loadRide({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final ride = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (ride == null) {
        setState(() {
          _ride = null;
          _error = 'No encontramos un viaje activo.';
          _loading = false;
        });

        return;
      }

      setState(() {
        _ride = ride;
        _error = null;
        _loading = false;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER ACTIVE LOAD ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo actualizar el viaje.';
        _loading = false;
      });
    } catch (error) {
      debugPrint('DRIVER ACTIVE LOAD ERROR: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No se pudo actualizar el viaje.';
        _loading = false;
      });
    }
  }

  Future<void> _startArrival() async {
    final ride = _ride;

    if (ride == null || _changingStatus) {
      return;
    }

    setState(() {
      _changingStatus = true;
    });

    try {
      final updatedRide = await ref
          .read(driverRidesRepositoryProvider)
          .startArrival(ride.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _ride = updatedRide;
      });

      unawaited(_sendDriverActivity());
    } on DioException catch (error) {
      debugPrint(
        'START ARRIVAL ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo iniciar el trayecto '
            'hacia el pasajero.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  Future<void> _arrive() async {
    final ride = _ride;

    if (ride == null || _changingStatus) {
      return;
    }

    setState(() {
      _changingStatus = true;
    });

    try {
      final operationsRepository = ref.read(driverOperationsRepositoryProvider);

      await operationsRepository.heartbeat();

      await _publishCurrentLocation(requestPermission: true);

      final updatedRide = await ref
          .read(driverRidesRepositoryProvider)
          .arrive(ride.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _ride = updatedRide;
      });
    } on _DriverLocationFailure catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo registrar la llegada.';

      if (error.response?.statusCode == 400) {
        message =
            'El GPS no es válido o estás '
            'demasiado lejos del pasajero.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  Future<void> _startRide() async {
    final ride = _ride;

    final code = _codeController.text.trim();

    if (ride == null || _changingStatus) {
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el código de 4 dígitos.')),
      );

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _changingStatus = true;
    });

    try {
      final operationsRepository = ref.read(driverOperationsRepositoryProvider);

      // Marcamos explícitamente el punto
      // donde comienza el viaje.
      await operationsRepository.heartbeat();

      await _publishCurrentLocation(requestPermission: true);

      final updatedRide = await ref
          .read(driverRidesRepositoryProvider)
          .startRide(rideId: ride.id, code: code);

      if (!mounted) {
        return;
      }

      _codeController.clear();

      setState(() {
        _ride = updatedRide;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('¡Viaje iniciado!')));
    } on _DriverLocationFailure catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message = 'No se pudo iniciar el viaje.';

      if (error.response?.statusCode == 400) {
        message =
            'El código es incorrecto o '
            'el GPS no es válido.';
      } else if (error.response?.statusCode == 409) {
        message =
            'El viaje no está en un '
            'estado compatible.';
      } else if (error.response?.statusCode == 410) {
        message =
            'El código venció. '
            'Solicita uno nuevo.';
      } else if (error.response?.statusCode == 423) {
        message =
            'El código fue bloqueado por '
            'demasiados intentos.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  Future<void> _completeRide() async {
    final ride = _ride;

    if (ride == null || _changingStatus) {
      return;
    }

    setState(() {
      _changingStatus = true;
    });

    // MUY IMPORTANTE:
    //
    // Detenemos primero cualquier actualización
    // periódica para impedir que una ubicación
    // vieja del origen pise el destino.
    _activityTimer?.cancel();
    _activityTimer = null;

    try {
      await _waitForActivityToFinish();

      final operationsRepository = ref.read(driverOperationsRepositoryProvider);

      // Primero mantenemos la presencia viva.
      await operationsRepository.heartbeat();

      // Esta debe ser la ÚLTIMA ubicación enviada
      // antes de llamar /complete.
      await _publishCurrentLocation(requestPermission: true);

      debugPrint(
        'DRIVER COMPLETE - '
        'ubicación final enviada',
      );

      final completion = await ref
          .read(driverRidesRepositoryProvider)
          .completeRide(rideId: ride.id);

      if (!mounted) {
        return;
      }

      _rideTimer?.cancel();
      _activityTimer?.cancel();

      setState(() {
        _completion = completion;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('¡Viaje completado!')));
    } on _DriverLocationFailure catch (error) {
      debugPrint(
        'DRIVER COMPLETE LOCATION ERROR '
        '${error.message}',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));

      _startActivityTimer();
    } on DioException catch (error) {
      debugPrint(
        'DRIVER COMPLETE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      String message = 'No se pudo finalizar el viaje.';

      if (error.response?.statusCode == 400) {
        message =
            'El GPS no es válido o todavía '
            'estás lejos del destino.';
      } else if (error.response?.statusCode == 409) {
        message =
            'El viaje no está en un '
            'estado compatible.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));

      // Si falló completar, reanudamos
      // presencia para poder intentarlo otra vez.
      _startActivityTimer();
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  String _titleForStatus(String status) {
    switch (status) {
      case 'DRIVER_ASSIGNED':
        return 'Pasajero asignado';

      case 'DRIVER_ARRIVING':
        return 'En camino al pasajero';

      case 'DRIVER_ARRIVED':
        return '¡Llegaste!';

      case 'IN_PROGRESS':
        return 'Viaje en curso';

      default:
        return status;
    }
  }

  IconData _iconForStatus(String status) {
    switch (status) {
      case 'DRIVER_ASSIGNED':
        return Icons.person_pin_circle;

      case 'DRIVER_ARRIVING':
        return Icons.two_wheeler;

      case 'DRIVER_ARRIVED':
        return Icons.location_on;

      case 'IN_PROGRESS':
        return Icons.route;

      default:
        return Icons.two_wheeler;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final ride = _ride;
    final completion = _completion;

    if (completion != null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Viaje completado'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle, size: 100),

                const SizedBox(height: 24),

                const Text(
                  '¡Viaje completado!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 20),

                Text(
                  'Tarifa final',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                const SizedBox(height: 8),

                Text(
                  'S/ ${completion.passengerAmountDue}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 24),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          'Método de pago: '
                          '${completion.paymentMethod}',
                        ),

                        const SizedBox(height: 8),

                        Text(
                          'Estado del pago: '
                          '${completion.paymentStatus}',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: () {
                    context.go(
                      '/cash-payment/'
                      '${completion.rideId}',
                    );
                  },
                  icon: const Icon(Icons.payments),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Cobrar efectivo'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Viaje activo')),
        body: Center(child: Text(_error ?? 'No tienes un viaje activo.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Tu viaje'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              Icon(_iconForStatus(ride.status), size: 90),

              const SizedBox(height: 24),

              Text(
                _titleForStatus(ride.status),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'S/ ${ride.estimatedFare}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 28),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.my_location),
                        title: const Text('Recoger en'),
                        subtitle: Text(ride.originAddress),
                      ),

                      const Divider(),

                      ListTile(
                        leading: const Icon(Icons.location_on),
                        title: const Text('Destino'),
                        subtitle: Text(ride.destinationAddress),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              if (ride.status == 'DRIVER_ASSIGNED')
                FilledButton.icon(
                  onPressed: _changingStatus ? null : _startArrival,
                  icon: const Icon(Icons.two_wheeler),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Ir a recoger al pasajero'),
                  ),
                ),

              if (ride.status == 'DRIVER_ARRIVING')
                FilledButton.icon(
                  onPressed: _changingStatus ? null : _arrive,
                  icon: const Icon(Icons.location_on),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Ya llegué'),
                  ),
                ),

              if (ride.status == 'DRIVER_ARRIVED') ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text(
                          'Código del pasajero',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        const Text(
                          'Pídele al pasajero '
                          'su código de 4 dígitos.',
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 20),

                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 4,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 12,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0000',
                            border: OutlineInputBorder(),
                          ),
                        ),

                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _changingStatus ? null : _startRide,
                            icon: const Icon(Icons.play_arrow),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                _changingStatus
                                    ? 'Validando...'
                                    : 'Iniciar viaje',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (ride.status == 'IN_PROGRESS') ...[
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.route, size: 54),
                        SizedBox(height: 12),
                        Text(
                          'Viaje en curso',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Dirígete al destino '
                          'del pasajero.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                FilledButton.icon(
                  onPressed: _changingStatus ? null : _completeRide,
                  icon: const Icon(Icons.flag),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _changingStatus
                          ? 'Verificando destino...'
                          : 'Llegué al destino y '
                                'finalizar viaje',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
