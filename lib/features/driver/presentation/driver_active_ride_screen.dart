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
import 'driver_post_ride_presence.dart';
import 'driver_ride_completion_view.dart';

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
  final _codeFocusNode = FocusNode();

  DriverActiveRide? _ride;
  DriverRideCompletion? _completion;

  bool _loading = true;
  bool _changingStatus = false;
  bool _activityInFlight = false;

  String? _error;

  /// Último error real del PIN/GPS al intentar `start`. Vive solo en
  /// memoria de esta pantalla (nunca se persiste), y se limpia al
  /// empezar a editar un código nuevo.
  _PinSubmitError? _pinError;

  /// `true` únicamente cuando Backend confirmó 423 (código bloqueado
  /// por intentos). Deshabilita el submit hasta que el Ride cambie de
  /// estado por otra vía real (no hay regeneración desde Driver).
  bool _pinLocked = false;

  /// Último error real al intentar `complete`. Igual criterio que
  /// `_pinError`: solo memoria de esta pantalla, se limpia al iniciar
  /// un nuevo intento de finalización.
  _CompleteSubmitError? _completeError;

  Timer? _rideTimer;
  Timer? _activityTimer;

  /// Heartbeat presence-only (Checkpoint F1), activo únicamente
  /// mientras se muestra la vista "¡Viaje completado!" (después de
  /// `_activityTimer` cancelarse, justo antes de `complete`). Nunca
  /// coexiste con `_activityTimer`: uno reemplaza al otro según el
  /// Ride siga IN_PROGRESS o ya esté COMPLETED.
  DriverPostRidePresence? _postRidePresence;

  @visibleForTesting
  bool get debugPostRidePresenceActive => _postRidePresence != null;

  /// Última posición real conocida del propio Driver, solo para
  /// representarla en el mapa del ride activo (punto azul nativo) y
  /// para encuadrar la cámara junto al pickup. Nunca se fabrica: solo
  /// se llena cuando el GPS real responde.
  Position? _driverPosition;

  /// `true` en cuanto ya se emitió el encuadre inicial Driver+pickup,
  /// para no reencuadrar la cámara en cada poll/heartbeat.
  bool _cameraFramed = false;

  /// Igual que `_cameraFramed`, pero para el encuadre Driver+destino
  /// de IN_PROGRESS. Es un guard independiente: el viaje normalmente
  /// ya framó una vez hacia el pickup en un estado previo, y necesita
  /// un segundo encuadre real (uno solo) hacia el destino al entrar a
  /// IN_PROGRESS, sea por transición natural o por restore directo.
  bool _destinationCameraFramed = false;

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

    _codeController.addListener(_handleCodeChanged);

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
    _postRidePresence?.dispose();

    _codeController.removeListener(_handleCodeChanged);
    _codeController.dispose();
    _codeFocusNode.dispose();

    super.dispose();
  }

  /// El mensaje de error del PIN permanece visible hasta que el
  /// Driver empieza a escribir un código nuevo (decisión de UX
  /// documentada en el reporte del checkpoint): no desaparece solo,
  /// pero tampoco sobrevive a la siguiente edición real.
  void _handleCodeChanged() {
    if (_pinError != null && _codeController.text.isNotEmpty) {
      setState(() {
        _pinError = null;
      });
    }
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

  /// Punto de entrada único: decide qué encuadre corresponde según el
  /// estado real del ride. IN_PROGRESS usa Driver+destino; los demás
  /// estados pre-viaje usan Driver+pickup. Cada uno tiene su propio
  /// guard de "una sola vez" (`_cameraFramed`/`_destinationCameraFramed`),
  /// así que transicionar de un grupo al otro (p.ej. ARRIVED→IN_PROGRESS)
  /// sí produce un segundo encuadre real, pero nunca se repite dentro
  /// del mismo grupo en cada poll de 3s ni cada heartbeat de 10s.
  void _maybeFrameCamera() {
    if (!mounted) {
      return;
    }

    final ride = _ride;
    final position = _driverPosition;

    if (ride == null || position == null) {
      return;
    }

    if (ride.status == 'IN_PROGRESS') {
      _maybeFrameDestinationCamera(ride, position);

      return;
    }

    _maybeFramePickupCamera(ride, position);
  }

  /// Encuadra Driver + pickup real, solo mientras el estado siga
  /// siendo DRIVER_ASSIGNED/DRIVER_ARRIVING/DRIVER_ARRIVED. Incluir
  /// DRIVER_ARRIVED (Checkpoint B) cubre el restore directo a ese
  /// estado, que de otro modo nunca encuadraría la cámara en esta
  /// sesión.
  void _maybeFramePickupCamera(DriverActiveRide ride, Position position) {
    if (_cameraFramed) {
      return;
    }

    if (ride.status != 'DRIVER_ASSIGNED' &&
        ride.status != 'DRIVER_ARRIVING' &&
        ride.status != 'DRIVER_ARRIVED') {
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

  /// Encuadra Driver + destino real (Checkpoint C), una sola vez por
  /// instancia de esta pantalla — cubre tanto la transición natural
  /// ARRIVED→IN_PROGRESS como el restore directo a IN_PROGRESS.
  void _maybeFrameDestinationCamera(DriverActiveRide ride, Position position) {
    if (_destinationCameraFramed) {
      return;
    }

    final destinationLatitude = ride.destinationLatitude;
    final destinationLongitude = ride.destinationLongitude;

    if (destinationLatitude == null || destinationLongitude == null) {
      return;
    }

    _destinationCameraFramed = true;

    setState(() {
      _cameraRequest = DriverMapCameraRequest(
        id: ++_cameraRequestSequence,
        target: LatLng(position.latitude, position.longitude),
        secondaryTarget: LatLng(destinationLatitude, destinationLongitude),
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

    if (ride == null || _changingStatus || _pinLocked) {
      return;
    }

    if (!RegExp(r'^\d{4}$').hasMatch(code)) {
      // Guard defensivo: el CTA ya está deshabilitado con <4 dígitos,
      // esto nunca debería alcanzarse desde la UI real.
      return;
    }

    _codeFocusNode.unfocus();

    setState(() {
      _changingStatus = true;
      _pinError = null;
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

      // El PIN solo vive en memoria hasta este punto: nunca se
      // guarda en storage/telemetry, y se descarta explícitamente
      // apenas Backend confirma el inicio real del viaje.
      _codeController.clear();

      setState(() {
        _ride = updatedRide;
      });
    } on _DriverLocationFailure catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pinError = _PinSubmitError(_PinErrorKind.location, message: error.message);
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      final classified = _classifyStartRideError(error);

      setState(() {
        _pinError = classified;

        if (classified.kind == _PinErrorKind.incorrect ||
            classified.kind == _PinErrorKind.expired ||
            classified.kind == _PinErrorKind.locked) {
          _codeController.clear();
        }

        if (classified.kind == _PinErrorKind.locked) {
          _pinLocked = true;
        }
      });

      if (classified.kind == _PinErrorKind.conflict) {
        // El Ride cambió de estado por otra vía: reutilizamos la
        // recarga real en vez de inventar una transición local.
        unawaited(_loadRide(showLoading: false));
      }
    } finally {
      if (mounted) {
        setState(() {
          _changingStatus = false;
        });
      }
    }
  }

  /// Clasifica el 400 real de `start` en sus dos formas distintas
  /// (código incorrecto vs GPS/distancia) según los campos que
  /// Backend realmente incluye en cada caso — nunca asume que todo
  /// 400 es un PIN inválido. Ver `ride-start.service.ts`: el 400 de
  /// distancia trae `distanceToOriginMeters`/`maximumStartDistanceMeters`;
  /// el 400 de código incorrecto trae `remainingAttempts`; el 400 de
  /// calidad de GPS (ausente/vencido/impreciso) no trae ninguno de
  /// los dos, solo un `message` de texto plano.
  _PinSubmitError _classifyStartRideError(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;

    if (statusCode == 400) {
      final remainingAttempts = data is Map ? data['remainingAttempts'] : null;

      if (remainingAttempts is num) {
        return _PinSubmitError(
          _PinErrorKind.incorrect,
          remainingAttempts: remainingAttempts.round(),
        );
      }

      final distance = data is Map ? data['distanceToOriginMeters'] : null;
      final maxDistance = data is Map
          ? data['maximumStartDistanceMeters']
          : null;

      if (distance is num && maxDistance is num) {
        return _PinSubmitError(
          _PinErrorKind.location,
          message:
              'Estás a ${distance.round()} m del punto de recojo '
              '(máximo ${maxDistance.round()} m).',
        );
      }

      return const _PinSubmitError(
        _PinErrorKind.location,
        message: 'No pudimos validar tu ubicación en el punto de recojo.',
      );
    }

    if (statusCode == 409) {
      return const _PinSubmitError(_PinErrorKind.conflict);
    }

    if (statusCode == 410) {
      return const _PinSubmitError(_PinErrorKind.expired);
    }

    if (statusCode == 423) {
      return const _PinSubmitError(_PinErrorKind.locked);
    }

    return const _PinSubmitError(_PinErrorKind.network);
  }

  /// UI local previa al POST real: no cambia ningún status, solo
  /// pregunta. Backend nunca se llama hasta que el Driver confirme
  /// explícitamente "Sí, finalizar viaje".
  Future<void> _confirmAndCompleteRide() async {
    if (_ride == null || _changingStatus) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Finalizar el viaje?'),
          content: const Text(
            'Confirma que llegaste al destino del pasajero.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sí, finalizar viaje'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _completeRide();
  }

  Future<void> _completeRide() async {
    final ride = _ride;

    if (ride == null || _changingStatus) {
      return;
    }

    setState(() {
      _changingStatus = true;
      _completeError = null;
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

      // El Ride ya está COMPLETED: no hay más `_activityTimer`
      // (GPS+heartbeat) para este viaje. Mantenemos `lastSeenAt`
      // vivo mientras el Driver ve "¡Viaje completado!" y decide
      // cobrar, sin publicar ubicación ni decidir disponibilidad.
      _postRidePresence = DriverPostRidePresence(
        repository: ref.read(driverOperationsRepositoryProvider),
      );
    } on _DriverLocationFailure catch (error) {
      debugPrint(
        'DRIVER COMPLETE LOCATION ERROR '
        '${error.message}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _completeError = _CompleteSubmitError(
          _CompleteErrorKind.quality,
          message: error.message,
        );
      });

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

      final classified = _classifyCompleteError(error);

      setState(() {
        _completeError = classified;
      });

      if (classified.kind == _CompleteErrorKind.conflict) {
        // El Ride cambió de estado por otra vía: reutilizamos la
        // recarga real en vez de inventar una transición local.
        unawaited(_loadRide(showLoading: false));
      }

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

  /// Clasifica el 400 real de `complete` en sus dos formas distintas
  /// (distancia al destino vs calidad de GPS), igual criterio que
  /// `_classifyStartRideError`: nunca asume que todo 400 es lo mismo.
  /// Ver `ride-completion.service.ts`: el 400 de distancia trae
  /// `distanceToDestinationMeters`/`maximumCompletionDistanceMeters`;
  /// el 400 de calidad de GPS (ausente/vencido/impreciso) no trae
  /// ninguno de los dos, solo un `message` de texto plano.
  _CompleteSubmitError _classifyCompleteError(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;

    if (statusCode == 400) {
      final distance = data is Map ? data['distanceToDestinationMeters'] : null;
      final maxDistance = data is Map
          ? data['maximumCompletionDistanceMeters']
          : null;

      if (distance is num && maxDistance is num) {
        return _CompleteSubmitError(
          _CompleteErrorKind.distance,
          message:
              'Estás a ${distance.round()} m del destino '
              '(máximo ${maxDistance.round()} m).',
        );
      }

      return const _CompleteSubmitError(_CompleteErrorKind.quality);
    }

    if (statusCode == 409) {
      return const _CompleteSubmitError(_CompleteErrorKind.conflict);
    }

    return const _CompleteSubmitError(_CompleteErrorKind.network);
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

    if (ride.status == 'DRIVER_ARRIVED') {
      return _buildArrivedScreen(ride);
    }

    if (ride.status == 'IN_PROGRESS') {
      return _buildInProgressScreen(ride);
    }

    return _buildLegacyRideScreen(ride);
  }

  Widget _buildCompletionScreen(DriverRideCompletion completion) {
    final passenger = _ride?.passenger;

    return DriverRideCompletionView(
      passengerFirstName: passenger?.firstName,
      passengerPhotoUrl: passenger?.photoUrl,
      finalFare: completion.finalFare,
      actualDistanceMeters: completion.actualDistanceMeters,
      actualDurationSeconds: completion.actualDurationSeconds,
      paymentMethod: completion.paymentMethod,
      paymentStatus: completion.paymentStatus,
      onCollectCash: () {
        context.go('/cash-payment/${completion.rideId}');
      },
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

              const Icon(Icons.two_wheeler, size: 90),

              const SizedBox(height: 24),

              Text(
                ride.status,
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

  // ---------------------------------------------------------------------
  // DRIVER_ARRIVED + PIN — Checkpoint B
  // ---------------------------------------------------------------------

  Widget _buildArrivedScreen(DriverActiveRide ride) {
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
            final mapHeight = (constraints.maxHeight * 0.28).clamp(
              140.0,
              260.0,
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
                          _ArrivedStatusHeader(
                            passengerFirstName: ride.passenger?.firstName,
                          ),

                          const SizedBox(height: 16),

                          _FareCard(fare: ride.displayFare),

                          const SizedBox(height: 14),

                          _PassengerCard(passenger: ride.passenger),

                          const SizedBox(height: 14),

                          _RouteSummaryRow(
                            originAddress: ride.originAddress,
                            destinationAddress: ride.destinationAddress,
                          ),

                          const SizedBox(height: 18),

                          _PinCard(
                            controller: _codeController,
                            focusNode: _codeFocusNode,
                            enabled: !_changingStatus && !_pinLocked,
                            error: _pinError,
                          ),

                          const SizedBox(height: 18),

                          AnimatedBuilder(
                            animation: _codeController,
                            builder: (context, _) {
                              final pinComplete =
                                  _codeController.text.length == 4;
                              final canSubmit =
                                  pinComplete && !_changingStatus && !_pinLocked;

                              return FilledButton.icon(
                                onPressed: canSubmit ? _startRide : null,
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
                                    : const Icon(Icons.play_arrow),
                                label: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    _changingStatus
                                        ? 'Validando...'
                                        : 'Iniciar viaje',
                                  ),
                                ),
                              );
                            },
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

  // ---------------------------------------------------------------------
  // IN_PROGRESS — Checkpoint C
  // ---------------------------------------------------------------------

  Widget _buildInProgressScreen(DriverActiveRide ride) {
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
            // El mapa es protagonista en IN_PROGRESS (más alto que en
            // los estados previos a la llegada), pero sigue dejando
            // suficiente espacio de sheet scrollable para que
            // Passenger/tarifa/destino/CTA nunca queden inaccesibles
            // en 360×640.
            final mapHeight = (constraints.maxHeight * 0.48).clamp(
              220.0,
              380.0,
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
                    // Se reutiliza el mismo cálculo de Checkpoint A
                    // (pickup verde + destino naranja): el pickup se
                    // mantiene como contexto secundario real en vez
                    // de omitirse, ya que sigue siendo un dato válido
                    // y no cuesta nada adicional mostrarlo.
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
                          const _InProgressStatusHeader(),

                          const SizedBox(height: 16),

                          const _ProgressStageRow(),

                          const SizedBox(height: 16),

                          _FareCard(fare: ride.displayFare),

                          const SizedBox(height: 14),

                          _PassengerCard(passenger: ride.passenger),

                          const SizedBox(height: 14),

                          _DestinationCard(
                            destinationAddress: ride.destinationAddress,
                          ),

                          if (_completeError != null) ...[
                            const SizedBox(height: 14),
                            _CompleteErrorBanner(error: _completeError!),
                          ],

                          const SizedBox(height: 22),

                          FilledButton.icon(
                            onPressed: _changingStatus
                                ? null
                                : _confirmAndCompleteRide,
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
                                : const Icon(Icons.flag),
                            label: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                              ),
                              child: Text(
                                _changingStatus
                                    ? 'Finalizando...'
                                    : 'Llegué al destino y finalizar viaje',
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

// ---------------------------------------------------------------------
// DRIVER_ARRIVED + PIN — widgets de Checkpoint B
// ---------------------------------------------------------------------

class _ArrivedStatusHeader extends StatelessWidget {
  const _ArrivedStatusHeader({required this.passengerFirstName});

  final String? passengerFirstName;

  @override
  Widget build(BuildContext context) {
    final name = passengerFirstName;

    final subtitle = (name == null || name.isEmpty)
        ? 'Pide al pasajero su código de 4 dígitos'
        : 'Pide el código de 4 dígitos a $name';

    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: DriverPalette.greenAvailable.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle,
            color: DriverPalette.greenAvailable,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          '¡Llegaste!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: DriverPalette.brown),
        ),
      ],
    );
  }
}

/// Resumen compacto "✓ Recojo → Destino": el texto completo de cada
/// dirección sigue viviendo en el widget (accesible/seleccionable),
/// solo se trunca visualmente con ellipsis si no entra en una línea.
class _RouteSummaryRow extends StatelessWidget {
  const _RouteSummaryRow({
    required this.originAddress,
    required this.destinationAddress,
  });

  final String originAddress;
  final String destinationAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            size: 16,
            color: DriverPalette.greenAvailable,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              originAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DriverPalette.brown,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              Icons.arrow_forward,
              size: 14,
              color: DriverPalette.brown,
            ),
          ),
          Expanded(
            child: Text(
              destinationAddress,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DriverPalette.brown,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.error,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final _PinSubmitError? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _PinInput(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            hasError: error != null,
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            _PinErrorBanner(error: error!),
          ],
        ],
      ),
    );
  }
}

/// 4 cajas visuales controladas por un único `TextField` real,
/// invisible pero funcional (opción A del brief: "menos frágil" que
/// coordinar 4 campos por separado). El teclado numérico, el borrado,
/// el foco y el pegado de 4 dígitos son comportamiento nativo de
/// `TextField`: no se reimplementa nada de eso a mano.
class _PinInput extends StatelessWidget {
  const _PinInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.hasError,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool hasError;

  static const int _length = 4;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([controller, focusNode]),
            builder: (context, _) {
              final text = controller.text;
              final hasFocus = focusNode.hasFocus;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(_length, (index) {
                  final digit = index < text.length ? text[index] : '';
                  final isNextToFill = enabled && hasFocus && index == text.length;

                  return _PinBox(
                    key: ValueKey('pin-box-$index'),
                    digit: digit,
                    active: isNextToFill,
                    hasError: hasError,
                  );
                }),
              );
            },
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: Semantics(
                label: 'Código de 4 dígitos del pasajero',
                textField: true,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_length),
                  ],
                  showCursor: false,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    counterText: '',
                  ),
                  style: const TextStyle(color: Colors.transparent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinBox extends StatelessWidget {
  const _PinBox({
    super.key,
    required this.digit,
    required this.active,
    required this.hasError,
  });

  final String digit;
  final bool active;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final Color borderColor;
    final double borderWidth;

    if (hasError) {
      borderColor = DriverPalette.coral;
      borderWidth = 2;
    } else if (active) {
      borderColor = DriverPalette.amber;
      borderWidth = 2;
    } else {
      borderColor = DriverPalette.brown.withValues(alpha: 0.25);
      borderWidth = 1;
    }

    return Container(
      width: 56,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DriverPalette.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      // Sin ocultar el dígito: el pasajero ya lo está dictando en voz
      // alta, no es una contraseña que deba protegerse visualmente.
      child: Text(
        digit,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: DriverPalette.greenPrimary,
        ),
      ),
    );
  }
}

class _PinErrorBanner extends StatelessWidget {
  const _PinErrorBanner({required this.error});

  final _PinSubmitError error;

  @override
  Widget build(BuildContext context) {
    final title = _pinErrorTitle(error.kind);
    final subtitle = _pinErrorSubtitle(error);

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: DriverPalette.coral,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DriverPalette.coral, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

enum _PinErrorKind { incorrect, expired, locked, location, conflict, network }

/// Error real de `start` clasificado por tipo. `remainingAttempts`
/// solo se llena cuando Backend lo entrega en el 400 de código
/// incorrecto — nunca se agrega al modelo de Ride, vive únicamente
/// como estado local de esta pantalla.
class _PinSubmitError {
  const _PinSubmitError(this.kind, {this.remainingAttempts, this.message});

  final _PinErrorKind kind;
  final int? remainingAttempts;
  final String? message;
}

String _pinErrorTitle(_PinErrorKind kind) {
  switch (kind) {
    case _PinErrorKind.incorrect:
      return 'Código incorrecto';
    case _PinErrorKind.expired:
      return 'Código vencido';
    case _PinErrorKind.locked:
      return 'Código bloqueado';
    case _PinErrorKind.location:
      return 'No pudimos validar tu ubicación';
    case _PinErrorKind.conflict:
      return 'El viaje cambió de estado';
    case _PinErrorKind.network:
      return 'No pudimos iniciar el viaje';
  }
}

String? _pinErrorSubtitle(_PinSubmitError error) {
  switch (error.kind) {
    case _PinErrorKind.incorrect:
      final remaining = error.remainingAttempts;

      return remaining == null ? null : _attemptsLabel(remaining);
    case _PinErrorKind.expired:
      return 'El código del pasajero ya venció.';
    case _PinErrorKind.locked:
      return 'Se agotaron los intentos disponibles.';
    case _PinErrorKind.location:
      return error.message;
    case _PinErrorKind.conflict:
      return 'Actualizando...';
    case _PinErrorKind.network:
      return 'Inténtalo nuevamente.';
  }
}

/// Singular/plural real, nunca hardcodeado como "5 intentos": el
/// número siempre viene de Backend.
String _attemptsLabel(int remaining) {
  return remaining == 1
      ? '1 intento restante'
      : '$remaining intentos restantes';
}

// ---------------------------------------------------------------------
// IN_PROGRESS — widgets de Checkpoint C
// ---------------------------------------------------------------------

class _InProgressStatusHeader extends StatelessWidget {
  const _InProgressStatusHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: DriverPalette.greenAvailable.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.route,
            color: DriverPalette.greenAvailable,
            size: 30,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Viaje en curso',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Dirígete al destino del pasajero',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
      ],
    );
  }
}

/// Progreso puramente representacional (Backend no expone avance
/// real al Driver): RECOJO siempre aparece cumplido porque
/// IN_PROGRESS solo ocurre después de DRIVER_ARRIVED + PIN válido.
/// Nunca un porcentaje ni una distancia/tiempo restante inventados.
class _ProgressStageRow extends StatelessWidget {
  const _ProgressStageRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle,
          size: 18,
          color: DriverPalette.greenAvailable,
        ),
        const SizedBox(width: 6),
        const Text(
          'RECOJO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: DriverPalette.greenAvailable,
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            height: 2,
            color: DriverPalette.brown.withValues(alpha: 0.25),
          ),
        ),
        const Text(
          'DESTINO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: DriverPalette.brown,
          ),
        ),
        const SizedBox(width: 6),
        const Icon(Icons.location_on, size: 18, color: DriverPalette.orange),
      ],
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destinationAddress});

  final String destinationAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on, color: DriverPalette.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DESTINO DEL PASAJERO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: DriverPalette.brown,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  destinationAddress,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DriverPalette.greenPrimary,
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

class _CompleteErrorBanner extends StatelessWidget {
  const _CompleteErrorBanner({required this.error});

  final _CompleteSubmitError error;

  @override
  Widget build(BuildContext context) {
    final title = _completeErrorTitle(error.kind);
    final subtitle = _completeErrorSubtitle(error);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DriverPalette.coral,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: DriverPalette.coral, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

enum _CompleteErrorKind { distance, quality, conflict, network }

/// Error real de `complete` clasificado por tipo. `message` solo se
/// llena con datos reales de Backend (o del propio GPS del
/// dispositivo); nunca se fabrica una distancia.
class _CompleteSubmitError {
  const _CompleteSubmitError(this.kind, {this.message});

  final _CompleteErrorKind kind;
  final String? message;
}

String _completeErrorTitle(_CompleteErrorKind kind) {
  switch (kind) {
    case _CompleteErrorKind.distance:
      return 'Aún estás lejos del destino';
    case _CompleteErrorKind.quality:
      return 'No pudimos validar tu ubicación';
    case _CompleteErrorKind.conflict:
      return 'El viaje cambió de estado';
    case _CompleteErrorKind.network:
      return 'No pudimos finalizar el viaje';
  }
}

String? _completeErrorSubtitle(_CompleteSubmitError error) {
  switch (error.kind) {
    case _CompleteErrorKind.distance:
      return error.message;
    case _CompleteErrorKind.quality:
      return error.message ?? 'Verifica tu GPS e inténtalo nuevamente.';
    case _CompleteErrorKind.conflict:
      return 'Actualizando...';
    case _CompleteErrorKind.network:
      return 'Inténtalo nuevamente.';
  }
}
