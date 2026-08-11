import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'
    show BitmapDescriptor, LatLng, Marker, MarkerId;

import '../../../core/theme/driver_palette.dart';
import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_active_ride.dart';
import '../domain/driver_assigned_passenger.dart';
import '../domain/driver_ride_completion.dart';
import 'driver_home_map.dart';

class _DriverLocationFailure implements Exception {
  const _DriverLocationFailure(this.message);

  final String message;
}

typedef DriverActiveRidePositionFetcher =
    Future<Position> Function({required bool requestPermission});

/// Punto de inyección mínimo para pruebas, igual que
/// `driverHomeGpsFetcherOverride` en Home: reemplaza la obtención
/// real de GPS sin acoplar la pantalla a Geolocator dentro de los
/// tests. Nombre distinto a propósito para evitar cualquier colisión
/// si algún test llegara a importar ambas pantallas a la vez.
@visibleForTesting
DriverActiveRidePositionFetcher? driverActiveRideGpsFetcherOverride;

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

  /// Última posición real conocida del propio Driver, solo para
  /// representarla en el mapa del ride activo (punto azul nativo) y
  /// para encuadrar la cámara junto al pickup. Nunca se fabrica: solo
  /// se llena cuando el GPS real responde.
  Position? _driverPosition;

  /// `true` en cuanto ya se emitió el encuadre inicial Driver+pickup,
  /// para no reencuadrar la cámara en cada poll/heartbeat.
  bool _cameraFramed = false;

  DriverMapCameraRequest? _cameraRequest;
  int _cameraRequestSequence = 0;

  @visibleForTesting
  Position? get debugDriverPosition => _driverPosition;

  @visibleForTesting
  DriverMapCameraRequest? get debugCameraRequest => _cameraRequest;

  @visibleForTesting
  DriverActiveRide? get debugRide => _ride;

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

  Future<Position> _getDriverPosition({required bool requestPermission}) {
    final override = driverActiveRideGpsFetcherOverride;

    if (override != null) {
      return override(requestPermission: requestPermission);
    }

    return _getDriverPositionFromDevice(requestPermission: requestPermission);
  }

  Future<Position> _getDriverPositionFromDevice({
    required bool requestPermission,
  }) async {
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

    if (mounted) {
      setState(() {
        _driverPosition = position;
      });

      _maybeFrameCamera();
    }

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

      _maybeFrameCamera();
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

  /// Encuadra la cámara UNA sola vez por instancia de esta pantalla
  /// (Driver + pickup real), solo mientras el estado siga siendo
  /// DRIVER_ASSIGNED/DRIVER_ARRIVING y solo cuando ya tenemos ambos
  /// puntos reales. No vuelve a dispararse en cada poll de 3s ni en
  /// cada heartbeat de 10s: por eso el guard `_cameraFramed`.
  void _maybeFrameCamera() {
    if (_cameraFramed || !mounted) {
      return;
    }

    final ride = _ride;
    final position = _driverPosition;

    if (ride == null || position == null) {
      return;
    }

    if (ride.status != 'DRIVER_ASSIGNED' && ride.status != 'DRIVER_ARRIVING') {
      return;
    }

    final originLatitude = ride.originLatitude;
    final originLongitude = ride.originLongitude;

    if (originLatitude == null || originLongitude == null) {
      return;
    }

    _cameraFramed = true;

    setState(() {
      _cameraRequest = DriverMapCameraRequest(
        id: ++_cameraRequestSequence,
        target: LatLng(position.latitude, position.longitude),
        secondaryTarget: LatLng(originLatitude, originLongitude),
      );
    });
  }

  Set<Marker> _rideMarkers(DriverActiveRide ride) {
    final markers = <Marker>{};

    final originLatitude = ride.originLatitude;
    final originLongitude = ride.originLongitude;

    if (originLatitude != null && originLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('active-ride-origin'),
          position: LatLng(originLatitude, originLongitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
    }

    final destinationLatitude = ride.destinationLatitude;
    final destinationLongitude = ride.destinationLongitude;

    if (destinationLatitude != null && destinationLongitude != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('active-ride-destination'),
          position: LatLng(destinationLatitude, destinationLongitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    return markers;
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_arriveErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  /// Mejora mínima y acotada: si Backend devuelve la distancia real
  /// en el 400 (`distanceToOriginMeters`/`maximumArrivalDistanceMeters`),
  /// se usa para un mensaje concreto en vez del genérico. Sin crear
  /// una arquitectura de errores nueva: cualquier otro caso conserva
  /// el mensaje que ya existía.
  String _arriveErrorMessage(DioException error) {
    if (error.response?.statusCode == 400) {
      final data = error.response?.data;

      final distance = data is Map ? data['distanceToOriginMeters'] : null;
      final maxDistance = data is Map
          ? data['maximumArrivalDistanceMeters']
          : null;

      if (distance is num && maxDistance is num) {
        return 'Estás a ${distance.round()} m del pasajero '
            '(máximo ${maxDistance.round()} m).';
      }

      return 'El GPS no es válido o estás '
          'demasiado lejos del pasajero.';
    }

    if (error.response == null) {
      return 'No se pudo conectar con TukiTuki.';
    }

    return 'No se pudo registrar la llegada.';
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
      return _buildCompletionScreen(completion);
    }

    if (ride == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Viaje activo')),
        body: Center(child: Text(_error ?? 'No tienes un viaje activo.')),
      );
    }

    if (ride.status == 'DRIVER_ASSIGNED' || ride.status == 'DRIVER_ARRIVING') {
      return _buildAssignedOrArrivingScreen(ride);
    }

    return _buildLegacyRideScreen(ride);
  }

  Widget _buildCompletionScreen(DriverRideCompletion completion) {
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

  Widget _buildLegacyRideScreen(DriverActiveRide ride) {
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
                'S/ ${ride.displayFare}',
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

  // ---------------------------------------------------------------------
  // DRIVER_ASSIGNED / DRIVER_ARRIVING — Checkpoint A
  // ---------------------------------------------------------------------

  Widget _buildAssignedOrArrivingScreen(DriverActiveRide ride) {
    final isArriving = ride.status == 'DRIVER_ARRIVING';
    final distanceLabel = _formatDistanceToOrigin(ride.distanceToOriginMeters);

    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        automaticallyImplyLeading: false,
        foregroundColor: DriverPalette.greenPrimary,
        title: const Text(
          'Tu viaje',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final mapHeight = (constraints.maxHeight * 0.36).clamp(
              180.0,
              320.0,
            );

            return Column(
              children: [
                SizedBox(
                  height: mapHeight,
                  width: double.infinity,
                  child: DriverHomeMap(
                    position: _driverPosition,
                    myLocationEnabled: _driverPosition != null,
                    cameraRequest: _cameraRequest,
                    markers: _rideMarkers(ride),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: DriverPalette.cream,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 14,
                          offset: Offset(0, -3),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _RideStatusHeader(isArriving: isArriving),

                          const SizedBox(height: 18),

                          _FareCard(fare: ride.displayFare),

                          const SizedBox(height: 14),

                          _PassengerCard(passenger: ride.passenger),

                          const SizedBox(height: 14),

                          _RouteCard(
                            originAddress: ride.originAddress,
                            destinationAddress: ride.destinationAddress,
                          ),

                          if (distanceLabel != null) ...[
                            const SizedBox(height: 12),
                            _DistanceChip(label: distanceLabel),
                          ],

                          const SizedBox(height: 22),

                          FilledButton.icon(
                            onPressed: _changingStatus
                                ? null
                                : (isArriving ? _arrive : _startArrival),
                            style: FilledButton.styleFrom(
                              backgroundColor: DriverPalette.greenPrimary,
                            ),
                            icon: _changingStatus
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    isArriving
                                        ? Icons.location_on
                                        : Icons.two_wheeler,
                                  ),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              child: Text(
                                _changingStatus
                                    ? 'Actualizando...'
                                    : isArriving
                                        ? 'Llegué al punto de recojo'
                                        : 'Ir a recoger al pasajero',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// `< 1000 m`: metros redondeados. `>= 1000 m`: km con 1 decimal.
/// Exactamente 0 (o cualquier redondeo <= 0): "En el punto de
/// recojo", de forma determinista y sin inventar un valor distinto
/// al que Backend calculó. `null`: no se muestra nada (sin ETA ni
/// distancia inventada).
String? _formatDistanceToOrigin(num? meters) {
  if (meters == null) {
    return null;
  }

  final rounded = meters.round();

  if (rounded <= 0) {
    return 'En el punto de recojo';
  }

  if (rounded < 1000) {
    return '$rounded m al recojo';
  }

  final kilometers = rounded / 1000;

  return '${kilometers.toStringAsFixed(1)} km al recojo';
}

class _RideStatusHeader extends StatelessWidget {
  const _RideStatusHeader({required this.isArriving});

  final bool isArriving;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: DriverPalette.amber.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isArriving ? Icons.two_wheeler : Icons.person_pin_circle,
            color: DriverPalette.orangeDeep,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isArriving ? 'En camino al pasajero' : 'Pasajero asignado',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isArriving
              ? 'Sigue la ubicación del punto de recojo.'
              : 'Dirígete al punto de recojo',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DriverPalette.brown),
        ),
      ],
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.fare});

  final String fare;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'TARIFA ACORDADA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: DriverPalette.brown,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'S/ $fare',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: DriverPalette.greenPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({required this.passenger});

  final AssignedPassenger? passenger;

  @override
  Widget build(BuildContext context) {
    final currentPassenger = passenger;

    if (currentPassenger == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_outline, color: DriverPalette.brown),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Información del pasajero no disponible',
                style: TextStyle(color: DriverPalette.brown),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _PassengerAvatar(passenger: currentPassenger),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentPassenger.firstName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DriverPalette.greenPrimary,
                  ),
                ),
                if (currentPassenger.hasRating) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⭐ ${_formatRatingAverage(currentPassenger.ratingAverage)} '
                    '· ${currentPassenger.ratingCount} calificaciones',
                    style: const TextStyle(
                      fontSize: 13,
                      color: DriverPalette.brown,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatRatingAverage(String raw) {
  final value = double.tryParse(raw);

  return value == null ? raw : value.toStringAsFixed(1);
}

class _PassengerAvatar extends StatelessWidget {
  const _PassengerAvatar({required this.passenger});

  final AssignedPassenger passenger;

  @override
  Widget build(BuildContext context) {
    final photoUrl = passenger.photoUrl;

    if (photoUrl == null || photoUrl.isEmpty) {
      return _InitialAvatar(firstName: passenger.firstName);
    }

    return ClipOval(
      child: Image.network(
        photoUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _InitialAvatar(firstName: passenger.firstName);
        },
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.firstName});

  final String firstName;

  @override
  Widget build(BuildContext context) {
    final initial = firstName.isNotEmpty ? firstName[0].toUpperCase() : '?';

    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: DriverPalette.greenPrimary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: DriverPalette.amber,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.originAddress,
    required this.destinationAddress,
  });

  final String originAddress;
  final String destinationAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.my_location,
              color: DriverPalette.greenAvailable,
            ),
            title: const Text('Punto de recojo'),
            subtitle: Text(originAddress),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.location_on, color: DriverPalette.orange),
            title: const Text('Destino'),
            subtitle: Text(destinationAddress),
          ),
        ],
      ),
    );
  }
}

class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DriverPalette.greenAvailable.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.social_distance,
              size: 14,
              color: DriverPalette.greenAvailable,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DriverPalette.greenAvailable,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
