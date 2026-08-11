import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/storage/secure_storage.dart';
import '../../../core/theme/driver_palette.dart';
import '../../auth/data/auth_repository.dart';
import '../data/driver_offers_repository.dart';
import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_daily_stats.dart';
import '../domain/driver_operational_state.dart';
import '../domain/driver_pending_proposal.dart';
import '../domain/driver_ride_offer.dart';
import 'driver_counter_offer_dialog.dart';
import 'driver_home_map.dart';

/// Estado explícito del Home, independiente del bool `_online`
/// que ya no alcanza para representar todos los casos reales
/// que devuelve Backend.
enum DriverHomeStatus {
  /// Todavía recuperando active ride + operational status.
  restoring,

  offline,

  available,

  /// Backend dice BUSY pero no encontramos active ride.
  /// Es una inconsistencia recuperable: NO es OFFLINE.
  busyRecovery,

  /// Error de red/inesperado durante restore o reconciliación.
  /// NO se convierte silenciosamente en OFFLINE.
  error,
}

/// Estado observable del GPS del conductor.
enum DriverGpsStatus {
  unknown,
  active,
  stale,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  acquireError,
  publishError,
}

typedef DriverPositionFetcher =
    Future<Position> Function({required bool requestPermission});

/// Punto de inyección mínimo para pruebas: permite reemplazar
/// la obtención real de GPS sin acoplar Home a Geolocator
/// dentro de los tests ni agregar paquetes nuevos.
@visibleForTesting
DriverPositionFetcher? driverHomeGpsFetcherOverride;

typedef DriverLocationAccuracyFetcher =
    Future<LocationAccuracyStatus> Function();

/// Punto de inyección mínimo para pruebas del diagnóstico
/// precise/reduced, con el mismo criterio que [driverHomeGpsFetcherOverride].
@visibleForTesting
DriverLocationAccuracyFetcher? driverHomeLocationAccuracyFetcherOverride;

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with WidgetsBindingObserver {
  DriverHomeStatus _status = DriverHomeStatus.restoring;

  bool _loading = false;
  bool _accepting = false;
  bool _restoreInFlight = false;
  bool _loggingOut = false;

  bool _refreshingPresence = false;
  bool _loadingOffers = false;
  bool _loadingStats = false;
  bool _navigatingToRide = false;
  bool _counterDialogOpen = false;
  bool _sessionInvalidHandled = false;

  DriverOperationalState? _operationalState;
  DriverDailyStats? _dailyStats;
  String? _errorMessage;

  DriverRideOffer? _offer;
  List<DriverPendingProposal> _pendingProposals = const [];

  String? _locationStatusMessage;
  Position? _lastPosition;
  DateTime? _lastPositionAt;
  DriverGpsStatus _gpsStatus = DriverGpsStatus.unknown;

  /// Diagnóstico precise/reduced de Android/iOS. Solo informativo:
  /// no bloquea ni cambia el flujo de conexión/publicación.
  LocationAccuracyStatus _locationAccuracyStatus =
      LocationAccuracyStatus.unknown;

  bool _recentering = false;

  /// Pedido de cámara declarativo vigente para `DriverHomeMap`. Home
  /// NUNCA guarda un `GoogleMapController`: solo emite pedidos con un
  /// `id` creciente (conectar/reconectar, tap en recentrar) y es el
  /// propio `DriverHomeMap` quien decide cómo y cuándo ejecutarlos
  /// con SU controller, siempre vivo mientras exista esa instancia.
  DriverMapCameraRequest? _cameraRequest;
  int _cameraRequestSequence = 0;

  Timer? _heartbeatTimer;
  Timer? _offersTimer;

  /// Solo refresca la UI (duración "en línea"). No es fuente de
  /// verdad: `connectedAt` de Backend sigue siendo la autoridad.
  Timer? _connectedAtTimer;

  /// Expuesto para pruebas y para el próximo checkpoint (rediseño
  /// visual), que mostrará connectedAt/lastSeenAt en el Home.
  @visibleForTesting
  DriverOperationalState? get debugOperationalState => _operationalState;

  @visibleForTesting
  DriverHomeStatus get debugStatus => _status;

  @visibleForTesting
  DriverRideOffer? get debugOffer => _offer;

  @visibleForTesting
  List<DriverPendingProposal> get debugPendingProposals => _pendingProposals;

  @visibleForTesting
  Position? get debugLastPosition => _lastPosition;

  @visibleForTesting
  DriverGpsStatus get debugGpsStatus => _effectiveGpsStatus;

  /// El estado GPS "problemático" (permissionDenied, deniedForever,
  /// serviceDisabled) solo se alcanza en un dispositivo real, a
  /// través de la excepción privada de Geolocator. Este setter
  /// mínimo permite ejercitar esos casos en tests sin exponer ni
  /// alterar esa lógica interna.
  @visibleForTesting
  void debugSetGpsStatus(DriverGpsStatus value) {
    setState(() {
      _gpsStatus = value;
    });
  }

  @visibleForTesting
  LocationAccuracyStatus get debugLocationAccuracyStatus =>
      _locationAccuracyStatus;

  @visibleForTesting
  bool get debugMyLocationSafe => _myLocationSafe;

  /// Último pedido de cámara emitido hacia `DriverHomeMap`. Expuesto
  /// para que los tests verifiquen la arquitectura declarativa sin
  /// necesitar (ni poder) acceder a un `GoogleMapController` real.
  @visibleForTesting
  DriverMapCameraRequest? get debugCameraRequest => _cameraRequest;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    unawaited(_restoreState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _stopOnlineWorkers();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _status == DriverHomeStatus.available &&
        !_navigatingToRide) {
      debugPrint('DRIVER APP RESUMED - refrescando presencia');

      unawaited(_refreshDriverPresence());
      unawaited(_loadOffers());
    }
  }

  // ---------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------

  Future<void> _restoreState() async {
    if (_restoreInFlight) {
      return;
    }

    _restoreInFlight = true;

    if (mounted) {
      setState(() {
        _status = DriverHomeStatus.restoring;
        _errorMessage = null;
      });
    }

    var redirected = false;

    try {
      final ridesRepository = ref.read(driverRidesRepositoryProvider);
      final operationsRepository = ref.read(driverOperationsRepositoryProvider);

      debugPrint('DRIVER RESTORE - verificando viaje activo...');

      final activeRide = await ridesRepository.getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        debugPrint('DRIVER RESTORE - viaje activo encontrado');

        redirected = true;
        _goToActiveRide();

        return;
      }

      // Las stats no bloquean la recuperación crítica: se cargan
      // en paralelo y su fallo no debe afectar el operational status.
      unawaited(_loadDailyStats());

      debugPrint('DRIVER RESTORE - consultando estado operativo...');

      final state = await operationsRepository.getStatus();

      debugPrint('DRIVER RESTORE - status=${state.rawStatus}');

      if (!mounted) {
        return;
      }

      redirected = await _applyRestoredState(state);
    } on DioException catch (error) {
      debugPrint(
        'DRIVER RESTORE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (mounted) {
        setState(() {
          _status = DriverHomeStatus.error;
          _errorMessage = _restoreErrorMessage(error);
        });
      }
    } catch (error) {
      debugPrint('DRIVER RESTORE ERROR inesperado: $error');

      if (mounted) {
        setState(() {
          _status = DriverHomeStatus.error;
          _errorMessage = 'Ocurrió un error inesperado al recuperar tu estado.';
        });
      }
    } finally {
      _restoreInFlight = false;
    }

    if (redirected) {
      return;
    }
  }

  /// Aplica el operational status recuperado y decide el estado
  /// explícito de Home. Devuelve `true` si navegó fuera de Home.
  Future<bool> _applyRestoredState(DriverOperationalState state) async {
    switch (state.status) {
      case DriverOperationalStatus.available:
        if (mounted) {
          setState(() {
            _status = DriverHomeStatus.available;
            _operationalState = state;
          });
        }

        /*
         * Backend conserva AVAILABLE entre aperturas.
         *
         * Recuperamos inmediatamente heartbeat + ubicación real
         * para volver a publicar al Driver correctamente en
         * Redis GEO. No solicitamos nuevamente permiso aquí:
         * solo comprobamos el permiso existente.
         */
        final publishedLocation = await _refreshDriverPresence();

        if (!mounted) {
          return false;
        }

        if (_status == DriverHomeStatus.available) {
          // Primera vez que el mapa se activa en esta apertura de
          // Home (restore mientras ya estaba AVAILABLE): lo centramos
          // una vez, igual que un connect explícito.
          final restoredPosition = _lastPosition;

          if (publishedLocation && restoredPosition != null) {
            _requestCameraCenter(restoredPosition);
          }

          _startOnlineWorkers();

          await _loadOffers();
        }

        return false;

      case DriverOperationalStatus.busy:
        final ride = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return false;
        }

        if (ride != null) {
          _goToActiveRide();

          return true;
        }

        if (mounted) {
          setState(() {
            _status = DriverHomeStatus.busyRecovery;
            _operationalState = state;
          });
        }

        return false;

      case DriverOperationalStatus.offline:
        if (mounted) {
          setState(() {
            _status = DriverHomeStatus.offline;
            _operationalState = state;
          });
        }

        return false;

      case DriverOperationalStatus.unknown:
        if (mounted) {
          setState(() {
            _status = DriverHomeStatus.error;
            _operationalState = state;
            _errorMessage = 'No pudimos interpretar tu estado operativo.';
          });
        }

        return false;
    }
  }

  String _restoreErrorMessage(DioException error) {
    if (error.response == null) {
      return 'No se pudo conectar con TukiTuki. Intenta nuevamente.';
    }

    final statusCode = error.response?.statusCode;

    if (statusCode != null && statusCode >= 500) {
      return 'El servidor de TukiTuki no está disponible temporalmente.';
    }

    return 'No se pudo recuperar tu estado. Intenta nuevamente.';
  }

  // ---------------------------------------------------------------------
  // Sesión inválida (401 definitivo)
  // ---------------------------------------------------------------------

  /// Señal más segura disponible sin duplicar el sistema de
  /// autenticación: ApiClient (AuthInterceptor) solo elimina el
  /// accessToken cuando un 401 no pudo resolverse con refresh.
  /// Errores temporales (timeout, red, 5xx) nunca tocan los tokens.
  Future<bool> _hasValidSession() async {
    final accessToken = await ref
        .read(secureStorageProvider)
        .read(key: StorageKeys.accessToken);

    return accessToken != null && accessToken.isNotEmpty;
  }

  /// Si la sesión ya fue invalidada definitivamente, detiene los
  /// workers y navega a login una sola vez, incluso si varios
  /// requests fallan al mismo tiempo (heartbeat + offers + restore).
  ///
  /// Devuelve `true` si el llamador debe abandonar su flujo actual
  /// (ya se navegó o se está navegando a /login).
  Future<bool> _handleSessionInvalidatedIfNeeded() async {
    if (_sessionInvalidHandled) {
      return true;
    }

    final hasSession = await _hasValidSession();

    if (hasSession) {
      return false;
    }

    if (_sessionInvalidHandled) {
      return true;
    }

    _sessionInvalidHandled = true;

    _stopOnlineWorkers();

    if (!mounted) {
      return true;
    }

    context.go('/login');

    return true;
  }

  // ---------------------------------------------------------------------
  // Daily stats
  // ---------------------------------------------------------------------

  Future<void> _loadDailyStats() async {
    if (_loadingStats) {
      return;
    }

    _loadingStats = true;

    try {
      final stats = await ref
          .read(driverOperationsRepositoryProvider)
          .getDailyStats();

      if (!mounted) {
        return;
      }

      setState(() {
        _dailyStats = stats;
      });
    } catch (error) {
      // Las stats fallidas quedan como "—" en el sheet (sección 18):
      // no se muestra un S/ 0.00 falso ni se rompe Home.
      debugPrint('DRIVER STATS ERROR: $error');
    } finally {
      _loadingStats = false;
    }
  }

  // ---------------------------------------------------------------------
  // Online / offline
  // ---------------------------------------------------------------------

  Future<void> _goOnline() async {
    if (_loading || _navigatingToRide) {
      return;
    }

    setState(() {
      _loading = true;
      _locationStatusMessage = null;
    });

    try {
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        _goToActiveRide();
        return;
      }

      /*
       * Antes de marcar AVAILABLE en Backend, comprobamos que
       * realmente podamos obtener una posición. Así evitamos:
       *
       * AVAILABLE en PostgreSQL pero sin ubicación en Redis GEO.
       */
      final initialPosition = await _getDriverPosition(requestPermission: true);

      if (!mounted) {
        return;
      }

      final repository = ref.read(driverOperationsRepositoryProvider);

      debugPrint('DRIVER ONLINE - conectando...');

      final state = await repository.goOnline();

      debugPrint('DRIVER ONLINE - backend status=${state.rawStatus}');

      if (state.status == DriverOperationalStatus.busy) {
        final ride = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return;
        }

        if (ride != null) {
          _goToActiveRide();
          return;
        }
      }

      if (state.status != DriverOperationalStatus.available) {
        if (!mounted) {
          return;
        }

        setState(() {
          _status = state.status == DriverOperationalStatus.busy
              ? DriverHomeStatus.busyRecovery
              : DriverHomeStatus.offline;
          _operationalState = state;
        });

        _showMessage('El backend no dejó al conductor disponible.');

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _status = DriverHomeStatus.available;
        _operationalState = state;
      });

      /*
       * Ya tenemos la ubicación adquirida antes de llamar ONLINE.
       * La reutilizamos para evitar pedir dos posiciones seguidas
       * al GPS.
       */
      await _refreshDriverPresence(knownPosition: initialPosition);

      if (!mounted) {
        return;
      }

      if (_status == DriverHomeStatus.available) {
        /*
         * Centra la cámara UNA VEZ por conexión (incluida una
         * reconexión tras haber estado OFFLINE con el mapa ya vivo).
         * No se repite en cada heartbeat: _goOnline() solo corre acá,
         * nunca en el timer periódico.
         */
        _requestCameraCenter(initialPosition);

        /*
         * Los workers ya NO vuelven a ejecutar otro refresh
         * inmediatamente. Evitamos el doble heartbeat/location
         * detectado en la auditoría.
         */
        _startOnlineWorkers();

        await _loadOffers();
      }
    } on _DriverLocationException catch (error) {
      debugPrint('DRIVER GPS ERROR - ${error.message}');

      if (!mounted) {
        return;
      }

      setState(() {
        _locationStatusMessage = error.message;
        _gpsStatus = error.status;
      });

      _showMessage(error.message);
    } on DioException catch (error) {
      debugPrint(
        'DRIVER ONLINE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (!mounted) {
        return;
      }

      if (error.response?.statusCode == 400) {
        try {
          final activeRide = await ref
              .read(driverRidesRepositoryProvider)
              .getActiveRide();

          if (!mounted) {
            return;
          }

          if (activeRide != null) {
            _goToActiveRide();
            return;
          }
        } catch (secondaryError) {
          debugPrint(
            'DRIVER ONLINE - error comprobando viaje activo: $secondaryError',
          );
        }
      }

      String message = 'No se pudo conectar como conductor.';

      if (error.response?.statusCode == 400) {
        message = 'No se pudo cambiar el estado del conductor.';
      } else if (error.response?.statusCode == 403) {
        message = 'El conductor todavía no está aprobado.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);
    } catch (error) {
      debugPrint('DRIVER ONLINE ERROR inesperado: $error');

      if (!mounted) {
        return;
      }

      _showMessage('No se pudo completar la conexión del conductor.');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _goOffline() async {
    if (_loading || _navigatingToRide) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        _goToActiveRide();
        return;
      }

      final state = await ref
          .read(driverOperationsRepositoryProvider)
          .goOffline();

      debugPrint('DRIVER OFFLINE OK status=${state.rawStatus}');

      if (state.status != DriverOperationalStatus.offline) {
        _showMessage('El backend no confirmó la desconexión.');

        return;
      }

      _stopOnlineWorkers();

      if (!mounted) {
        return;
      }

      setState(() {
        _status = DriverHomeStatus.offline;
        _operationalState = state;
        _offer = null;
        _pendingProposals = const [];
        _locationStatusMessage = null;
        _gpsStatus = DriverGpsStatus.unknown;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFLINE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (!mounted) {
        return;
      }

      if (error.response?.statusCode == 400) {
        try {
          final activeRide = await ref
              .read(driverRidesRepositoryProvider)
              .getActiveRide();

          if (!mounted) {
            return;
          }

          if (activeRide != null) {
            _goToActiveRide();
            return;
          }
        } catch (secondaryError) {
          debugPrint(
            'DRIVER OFFLINE - error comprobando viaje: $secondaryError',
          );
        }
      }

      _showMessage('No se pudo desconectar al conductor.');
    } finally {
      if (mounted && !_navigatingToRide) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------
  // GPS
  // ---------------------------------------------------------------------

  Future<Position> _getDriverPosition({required bool requestPermission}) {
    final override = driverHomeGpsFetcherOverride;

    if (override != null) {
      return override(requestPermission: requestPermission);
    }

    return _getDriverPositionFromDevice(requestPermission: requestPermission);
  }

  /// Diagnóstico precise/reduced. Puramente informativo: un fallo aquí
  /// nunca debe afectar el flujo real de ubicación/publicación.
  Future<LocationAccuracyStatus> _getLocationAccuracyStatus() async {
    try {
      final override = driverHomeLocationAccuracyFetcherOverride;

      if (override != null) {
        return await override();
      }

      return await Geolocator.getLocationAccuracy();
    } catch (error) {
      debugPrint('DRIVER LOCATION ACCURACY - no se pudo consultar: $error');

      return LocationAccuracyStatus.unknown;
    }
  }

  Future<Position> _getDriverPositionFromDevice({
    required bool requestPermission,
  }) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw const _DriverLocationException(
          'Activa la ubicación del dispositivo '
          'para conectarte como conductor.',
          DriverGpsStatus.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        throw const _DriverLocationException(
          'TukiTuki necesita permiso de ubicación '
          'para publicar tu posición y recibir viajes.',
          DriverGpsStatus.permissionDenied,
        );
      }

      if (permission == LocationPermission.deniedForever) {
        throw const _DriverLocationException(
          'El permiso de ubicación está bloqueado. '
          'Actívalo desde Ajustes del dispositivo.',
          DriverGpsStatus.permissionDeniedForever,
        );
      }

      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const _DriverLocationException(
          'No fue posible obtener permiso de ubicación.',
          DriverGpsStatus.permissionDenied,
        );
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        throw const _DriverLocationException(
          'El GPS está tardando demasiado en obtener tu ubicación. '
          'Intenta nuevamente.',
          DriverGpsStatus.acquireError,
        );
      }
    } on _DriverLocationException {
      rethrow;
    } catch (error) {
      debugPrint('DRIVER GPS - error obteniendo posición: $error');

      throw const _DriverLocationException(
        'No se pudo obtener tu ubicación GPS.',
        DriverGpsStatus.acquireError,
      );
    }
  }

  Future<void> _publishDriverLocation(
    DriverOperationsRepository repository,
    Position position,
  ) async {
    await repository.updateLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      heading: position.heading,
      speed: position.speed,
      accuracy: position.accuracy,
    );

    // No se registran coordenadas exactas en logs.
    debugPrint(
      'DRIVER LOCATION OK accuracy=${position.accuracy.toStringAsFixed(1)}',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _locationStatusMessage = null;
      _lastPosition = position;
      _lastPositionAt = DateTime.now();
      _gpsStatus = DriverGpsStatus.active;
    });

    _refreshLocationAccuracyStatus();
  }

  /// Fire-and-forget a propósito: es puramente informativo y NUNCA
  /// debe retrasar ni afectar el flujo real de ubicación/publicación
  /// que la llama (heartbeat, goOnline, recenter).
  void _refreshLocationAccuracyStatus() {
    unawaited(
      _getLocationAccuracyStatus().then((status) {
        if (!mounted) {
          return;
        }

        setState(() {
          _locationAccuracyStatus = status;
        });
      }),
    );
  }

  bool get _isPositionFresh {
    final publishedAt = _lastPositionAt;

    if (publishedAt == null) {
      return false;
    }

    return DateTime.now().difference(publishedAt) <=
        const Duration(seconds: 25);
  }

  DriverGpsStatus get _effectiveGpsStatus {
    if (_gpsStatus == DriverGpsStatus.active && !_isPositionFresh) {
      return DriverGpsStatus.stale;
    }

    return _gpsStatus;
  }

  // ---------------------------------------------------------------------
  // Workers
  // ---------------------------------------------------------------------

  void _startOnlineWorkers() {
    _stopOnlineWorkers();

    if (_status != DriverHomeStatus.available || _navigatingToRide) {
      return;
    }

    debugPrint('DRIVER WORKERS - iniciados');

    /*
     * Ya hicimos presencia y ofertas antes de entrar aquí.
     * Por eso NO ejecutamos nuevamente heartbeat/location
     * de inmediato.
     */

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshDriverPresence());
    });

    _offersTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_loadOffers());
    });

    // Solo repinta la duración "en línea"; no vuelve a consultar Backend.
    _connectedAtTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopOnlineWorkers() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();
    _connectedAtTimer?.cancel();

    _heartbeatTimer = null;
    _offersTimer = null;
    _connectedAtTimer = null;
  }

  Future<bool> _refreshDriverPresence({Position? knownPosition}) async {
    if (_status != DriverHomeStatus.available ||
        _refreshingPresence ||
        _navigatingToRide) {
      return false;
    }

    _refreshingPresence = true;

    try {
      final repository = ref.read(driverOperationsRepositoryProvider);

      /*
       * Heartbeat primero. Backend confirma que seguimos en un
       * estado operativo válido.
       */
      final heartbeatState = await repository.heartbeat();

      debugPrint('DRIVER HEARTBEAT OK status=${heartbeatState.rawStatus}');

      if (heartbeatState.status == DriverOperationalStatus.busy) {
        final activeRide = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return false;
        }

        if (activeRide != null) {
          debugPrint('DRIVER HEARTBEAT - viaje activo detectado');

          _goToActiveRide();
          return false;
        }

        // BUSY sin active ride es una inconsistencia recuperable,
        // no un OFFLINE encubierto.
        _stopOnlineWorkers();

        if (mounted) {
          setState(() {
            _status = DriverHomeStatus.busyRecovery;
            _operationalState = heartbeatState;
          });
        }

        return false;
      }

      if (heartbeatState.status != DriverOperationalStatus.available) {
        await _reconcileOperationalStatus();

        return false;
      }

      if (mounted) {
        setState(() {
          _operationalState = heartbeatState;
        });
      }

      /*
       * Durante los ticks periódicos NO volvemos a pedir permiso
       * al usuario. Solo comprobamos el permiso existente.
       */
      final position =
          knownPosition ?? await _getDriverPosition(requestPermission: false);

      await _publishDriverLocation(repository, position);

      return true;
    } on _DriverLocationException catch (error) {
      debugPrint('DRIVER PRESENCE GPS ERROR - ${error.message}');

      if (mounted) {
        setState(() {
          _locationStatusMessage =
              '${error.message} '
              'Tu ubicación no puede actualizarse hasta resolverlo.';
          _gpsStatus = error.status;
        });
      }

      /*
       * No pedimos permiso repetidamente ni mostramos SnackBar
       * cada 10 segundos. El worker seguirá intentando y
       * recuperará automáticamente la publicación si vuelve
       * el GPS.
       */
      return false;
    } on DioException catch (error) {
      debugPrint(
        'DRIVER PRESENCE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type} '
        'message=${error.message}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return false;
      }

      if (error.response?.statusCode == 400) {
        await _reconcileOperationalStatus();
      } else if (error.response?.statusCode == 503) {
        if (mounted) {
          setState(() {
            _locationStatusMessage =
                'La ubicación no pudo publicarse para recibir viajes. '
                'TukiTuki volverá a intentarlo.';
            _gpsStatus = DriverGpsStatus.publishError;
          });
        }
      }

      return false;
    } catch (error) {
      debugPrint('DRIVER PRESENCE ERROR inesperado: $error');

      return false;
    } finally {
      _refreshingPresence = false;
    }
  }

  Future<void> _reconcileOperationalStatus() async {
    try {
      final state = await ref
          .read(driverOperationsRepositoryProvider)
          .getStatus();

      debugPrint('DRIVER PRESENCE - status real=${state.rawStatus}');

      if (!mounted) {
        return;
      }

      if (state.status == DriverOperationalStatus.busy) {
        final activeRide = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return;
        }

        if (activeRide != null) {
          debugPrint('DRIVER PRESENCE - conductor seleccionado por pasajero');

          _goToActiveRide();

          return;
        }

        _stopOnlineWorkers();

        setState(() {
          _status = DriverHomeStatus.busyRecovery;
          _operationalState = state;
        });

        return;
      }

      if (state.status != DriverOperationalStatus.available) {
        _stopOnlineWorkers();

        setState(() {
          _status = state.status == DriverOperationalStatus.offline
              ? DriverHomeStatus.offline
              : DriverHomeStatus.error;
          _operationalState = state;
          _offer = null;
          _pendingProposals = const [];
        });

        if (state.status == DriverOperationalStatus.offline) {
          _showMessage(
            'El conductor dejó de estar disponible. '
            'Pulsa Conectarme nuevamente.',
          );
        }

        return;
      }

      setState(() {
        _operationalState = state;
      });
    } catch (statusError) {
      debugPrint('DRIVER PRESENCE - no se pudo consultar status: $statusError');

      if (statusError is DioException) {
        await _handleSessionInvalidatedIfNeeded();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Offers & proposals
  // ---------------------------------------------------------------------

  Future<void> _loadOffers() async {
    if (_status != DriverHomeStatus.available ||
        _accepting ||
        _counterDialogOpen ||
        _loadingOffers ||
        _navigatingToRide) {
      return;
    }

    _loadingOffers = true;

    try {
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        debugPrint('DRIVER OFFERS - viaje activo detectado');

        _goToActiveRide();
        return;
      }

      final hadPendingProposals = _pendingProposals.isNotEmpty;

      final proposals = await ref
          .read(driverOffersRepositoryProvider)
          .getPendingProposals();

      if (!mounted) {
        return;
      }

      debugPrint('DRIVER PENDING PROPOSALS - cantidad=${proposals.length}');

      if (proposals.isNotEmpty) {
        if (!_counterDialogOpen && !_navigatingToRide) {
          setState(() {
            _pendingProposals = proposals;
            _offer = null;
          });
        }

        return;
      }

      if (hadPendingProposals) {
        setState(() {
          _pendingProposals = const [];
        });

        _showMessage(
          'La solicitud terminó o el pasajero eligió otra propuesta.',
        );
      }

      if (_counterDialogOpen || _navigatingToRide) {
        return;
      }

      final offers = await ref
          .read(driverOffersRepositoryProvider)
          .getActiveOffers();

      debugPrint('DRIVER OFFERS OK - cantidad=${offers.length}');

      if (!mounted || _counterDialogOpen || _navigatingToRide) {
        return;
      }

      setState(() {
        _offer = offers.isEmpty ? null : offers.first;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFERS ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type} '
        'message=${error.message}',
      );

      await _handleSessionInvalidatedIfNeeded();
    } catch (error) {
      debugPrint('DRIVER OFFERS ERROR inesperado: $error');
    } finally {
      _loadingOffers = false;
    }
  }

  DriverPendingProposal _proposalFromOffer(
    DriverRideOffer offer, {
    String? fallbackFare,
  }) {
    return DriverPendingProposal(
      offerId: offer.id,
      rideId: offer.rideId,
      status: offer.status,
      proposedFare: offer.proposedFare ?? fallbackFare,
      passengerOfferFare: offer.passengerOfferFare,
      estimatedFare: offer.estimatedFare,
      currency: offer.currency,
      expiresAt: offer.expiresAt,
      originAddress: offer.originAddress,
      destinationAddress: offer.destinationAddress,
      distanceToOriginMeters: offer.distanceToOriginMeters,
    );
  }

  Future<void> _acceptOffer() async {
    final offer = _offer;

    if (offer == null || _accepting || _navigatingToRide) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      debugPrint('DRIVER OFFER PROPOSAL - enviando...');

      final proposed = await ref
          .read(driverOffersRepositoryProvider)
          .acceptOffer(offer.id);

      debugPrint('DRIVER OFFER PROPOSAL OK status=${proposed.status}');

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
        _pendingProposals = [
          _proposalFromOffer(proposed, fallbackFare: offer.passengerOfferFare),
        ];
      });

      _showMessage('Propuesta enviada al pasajero.');
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFER ACCEPT ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (!mounted) {
        return;
      }

      String message = 'No se pudo enviar la propuesta.';

      if (error.response?.statusCode == 409) {
        message = 'La oferta ya venció o fue asignada.';
      } else if (error.response?.statusCode == 404) {
        message = 'La oferta ya no está disponible.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);

      await _loadOffers();
    } finally {
      if (mounted && !_navigatingToRide && !_sessionInvalidHandled) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  Future<void> _counterOffer() async {
    final offer = _offer;

    if (offer == null ||
        offer.status != 'OFFERED' ||
        _accepting ||
        _counterDialogOpen ||
        _navigatingToRide) {
      return;
    }

    setState(() {
      _counterDialogOpen = true;
    });

    String? proposedFare;

    try {
      proposedFare = await showDriverCounterOfferDialog(
        context: context,
        passengerOfferFare: offer.passengerOfferFare,
      );
    } finally {
      if (mounted) {
        setState(() {
          _counterDialogOpen = false;
        });
      } else {
        _counterDialogOpen = false;
      }
    }

    if (!mounted || proposedFare == null) {
      return;
    }

    final currentOffer = _offer;

    if (currentOffer == null ||
        currentOffer.id != offer.id ||
        currentOffer.status != 'OFFERED' ||
        _accepting ||
        _navigatingToRide) {
      await _loadOffers();

      return;
    }

    setState(() {
      _accepting = true;
    });

    var reloadOffers = false;

    try {
      debugPrint('DRIVER COUNTER OFFER - enviando S/ $proposedFare');

      final proposed = await ref
          .read(driverOffersRepositoryProvider)
          .counterOffer(offer.id, proposedFare);

      debugPrint(
        'DRIVER COUNTER OFFER OK '
        'status=${proposed.status} '
        'fare=${proposed.proposedFare}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
        _pendingProposals = [
          _proposalFromOffer(proposed, fallbackFare: proposedFare),
        ];
      });

      _showMessage('Contraoferta enviada al pasajero.');
    } on DioException catch (error) {
      debugPrint(
        'DRIVER COUNTER OFFER ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (!mounted) {
        return;
      }

      final statusCode = error.response?.statusCode;

      if (statusCode == 409) {
        setState(() {
          if (_offer?.id == offer.id) {
            _offer = null;
          }
        });
      }

      _showMessage(
        driverCounterOfferErrorMessage(
          statusCode: statusCode,
          hasResponse: error.response != null,
        ),
      );

      reloadOffers = true;
    } finally {
      if (mounted && !_navigatingToRide && !_sessionInvalidHandled) {
        setState(() {
          _accepting = false;
        });
      }
    }

    if (reloadOffers && mounted && !_navigatingToRide) {
      await _loadOffers();
    }
  }

  Future<void> _rejectOffer() async {
    final offer = _offer;

    if (offer == null || _accepting || _navigatingToRide) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      await ref.read(driverOffersRepositoryProvider).rejectOffer(offer.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
      });

      _showMessage('Solicitud rechazada.');

      await _loadOffers();
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFER REJECT ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (await _handleSessionInvalidatedIfNeeded()) {
        return;
      }

      if (!mounted) {
        return;
      }

      String message = 'No se pudo rechazar la solicitud.';

      if (error.response?.statusCode == 409) {
        message = 'La solicitud ya venció o dejó de estar disponible.';
      } else if (error.response?.statusCode == 404) {
        message = 'La solicitud ya no está disponible.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);
    } finally {
      if (mounted && !_navigatingToRide && !_sessionInvalidHandled) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------
  // Logout / navigation
  // ---------------------------------------------------------------------

  Future<void> _logout() async {
    if (_loggingOut) {
      return;
    }

    if (mounted) {
      setState(() {
        _loggingOut = true;
      });
    } else {
      _loggingOut = true;
    }

    _stopOnlineWorkers();

    if (_status == DriverHomeStatus.available) {
      try {
        await ref.read(driverOperationsRepositoryProvider).goOffline();
      } catch (error) {
        debugPrint('DRIVER LOGOUT - no se pudo poner OFFLINE: $error');
      }
    }

    await ref.read(authRepositoryProvider).logout();

    if (mounted) {
      setState(() {
        _loggingOut = false;
      });
    } else {
      _loggingOut = false;
    }

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  void _goToActiveRide() {
    if (!mounted || _counterDialogOpen || _navigatingToRide) {
      return;
    }

    _navigatingToRide = true;

    _stopOnlineWorkers();

    context.go('/active-ride');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Recenter manual, igual que Passenger: siempre pide una Position
  /// nueva y fresca (nunca la cacheada en `_lastPosition`, nunca un
  /// stream de "mejor" Position), y le pide a `DriverHomeMap` que
  /// centre la cámara en esa misma Position que también queda
  /// guardada en el estado. Nunca toca un `GoogleMapController`
  /// directamente: eso es responsabilidad exclusiva de `DriverHomeMap`.
  Future<void> _recenterMap() async {
    if (_recentering) {
      return;
    }

    setState(() {
      _recentering = true;
    });

    try {
      final position = await _getDriverPosition(requestPermission: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _lastPosition = position;
        _lastPositionAt = DateTime.now();
        _gpsStatus = DriverGpsStatus.active;
      });

      _requestCameraCenter(position);

      _refreshLocationAccuracyStatus();
    } on _DriverLocationException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('DRIVER RECENTER - error: $error');
      _showMessage('No se pudo obtener tu ubicación GPS.');
    } finally {
      if (mounted) {
        setState(() {
          _recentering = false;
        });
      }
    }
  }

  /// Emite un pedido de cámara declarativo nuevo hacia `DriverHomeMap`
  /// (conectar/reconectar o recentrado manual). `DriverHomeMap` decide
  /// con SU controller —vivo mientras esa instancia exista— cómo y
  /// cuándo aplicarlo; Home nunca guarda ni usa un
  /// `GoogleMapController`.
  void _requestCameraCenter(Position position) {
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraRequest = DriverMapCameraRequest(
        id: ++_cameraRequestSequence,
        target: LatLng(position.latitude, position.longitude),
      );
    });
  }

  Widget _buildRecenterButton() {
    return Material(
      key: const ValueKey('driver-home-recenter-button'),
      color: DriverPalette.amber,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black38,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _recentering ? null : _recenterMap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: _recentering
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: DriverPalette.greenPrimary,
                  ),
                )
              : const Icon(
                  Icons.my_location,
                  color: DriverPalette.greenPrimary,
                  size: 22,
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  /// El botón custom de recentrado nunca se muestra OFFLINE: el mapa
  /// vivo queda oculto detrás del overlay opaco y no tiene sentido
  /// ofrecer recentrar algo que el conductor no puede ver.
  bool get _showRecenterButton =>
      _lastPosition != null && _status != DriverHomeStatus.offline;

  DriverHomeMapFallback get _mapFallback {
    /*
     * OFFLINE y sin un problema de GPS conocido: todavía no se
     * intentó adquirir Position, así que "Obteniendo tu ubicación..."
     * sería engañoso. Si el usuario ya pulsó Conectarme (_loading)
     * sí estamos adquiriendo de verdad, y eso se refleja abajo.
     * Si ya conocemos un problema real (permiso, servicio, etc.),
     * seguimos mostrando ese motivo específico en vez del genérico.
     */
    if (_status == DriverHomeStatus.offline &&
        !_loading &&
        _gpsStatus == DriverGpsStatus.unknown) {
      return DriverHomeMapFallback.offline;
    }

    switch (_effectiveGpsStatus) {
      case DriverGpsStatus.serviceDisabled:
        return DriverHomeMapFallback.serviceDisabled;
      case DriverGpsStatus.permissionDenied:
        return DriverHomeMapFallback.permissionDenied;
      case DriverGpsStatus.permissionDeniedForever:
        return DriverHomeMapFallback.permissionDeniedForever;
      case DriverGpsStatus.acquireError:
        return DriverHomeMapFallback.acquireError;
      case DriverGpsStatus.publishError:
        return DriverHomeMapFallback.publishError;
      case DriverGpsStatus.unknown:
      case DriverGpsStatus.active:
      case DriverGpsStatus.stale:
        return DriverHomeMapFallback.acquiring;
    }
  }

  String get _grossAmountDisplay {
    final stats = _dailyStats;
    return stats != null ? 'S/ ${stats.grossAmount}' : '—';
  }

  String get _completedRidesDisplay {
    final stats = _dailyStats;
    return stats != null ? '${stats.completedRides}' : '—';
  }

  String get _onlineDurationDisplay {
    final state = _operationalState;

    if (state == null) {
      return '—';
    }

    final duration = state.onlineDurationAt(DateTime.now());

    if (duration == null) {
      return '—';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  String _gpsStatusLabel() {
    switch (_effectiveGpsStatus) {
      case DriverGpsStatus.active:
        return 'Ubicación GPS activa';
      case DriverGpsStatus.stale:
        return 'Ubicación GPS desactualizada';
      default:
        return 'Obteniendo ubicación...';
    }
  }

  /// "Ubicación GPS activa" solo cuando hay una Position real y
  /// fresh, y no hay ningún problema conocido (serviceDisabled,
  /// permission denied/forever, acquire/publish error).
  bool get _gpsPillActive =>
      _lastPosition != null && _effectiveGpsStatus == DriverGpsStatus.active;

  bool get _showReducedAccuracyHint =>
      _gpsPillActive &&
      _locationAccuracyStatus == LocationAccuracyStatus.reduced;

  /// Igual que Passenger: el punto azul nativo solo se activa cuando
  /// es seguro hacerlo. Nunca se activa solo porque `position` no sea
  /// null: si el último intento conocido falló por permiso o
  /// servicio, seguimos sin habilitarlo aunque quede una Position
  /// vieja cacheada.
  bool get _myLocationSafe =>
      _lastPosition != null &&
      _gpsStatus != DriverGpsStatus.permissionDenied &&
      _gpsStatus != DriverGpsStatus.permissionDeniedForever &&
      _gpsStatus != DriverGpsStatus.serviceDisabled;

  /// Alto del área física del mapa dentro del espacio disponible bajo
  /// el header (`availableHeight`, medido en vivo con [LayoutBuilder]:
  /// nunca un número fijo pensado para un dispositivo puntual). Deja
  /// el resto del espacio para que el bottom sheet ocupe SU región
  /// propia, en vez de flotar detrás de todo el mapa.
  double _mapAreaHeight(double availableHeight) =>
      (availableHeight * 0.42).clamp(200.0, 340.0);

  /// Cuánto se solapa el borde redondeado del sheet sobre el borde
  /// inferior del área del mapa. Implementado con geometría real
  /// ([Positioned] con `top` explícito), no con un `Transform`: así
  /// el sheet ocupa físicamente esa región —sin espacio reservado
  /// pero sin pintar detrás del solape— en vez de solo desplazar su
  /// pintura y dejar un hueco.
  static const double _sheetOverlap = 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.cream,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mapHeight = _mapAreaHeight(constraints.maxHeight);
                  final isOffline = _status == DriverHomeStatus.offline;

                  return Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: mapHeight,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Positioned.fill(
                              child: DriverHomeMap(
                                position: _lastPosition,
                                myLocationEnabled: _myLocationSafe,
                                fallback: _mapFallback,
                                cameraRequest: _cameraRequest,
                              ),
                            ),
                            if (_showRecenterButton)
                              Positioned(
                                top: 14,
                                right: 16,
                                child: _buildRecenterButton(),
                              ),
                            /*
                             * OFFLINE con una Position ya conocida: el
                             * GoogleMap real sigue montado debajo (para
                             * no repetir el ciclo dispose/recreate que
                             * causó el bug de controller), pero el
                             * conductor NO debe percibirlo. Un overlay
                             * opaco con el MISMO copy de fallback lo
                             * cubre por completo y absorbe cualquier
                             * tap/gesto para que no llegue al mapa.
                             *
                             * Si todavía no hay Position (primer
                             * OFFLINE), no hace falta: DriverHomeMap ya
                             * muestra su propio fallback porque
                             * `position` es null, y agregar este
                             * overlay encima duplicaría el icono.
                             */
                            if (isOffline && _lastPosition != null)
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {},
                                  child: DriverHomeMapFallbackView(
                                    reason: _mapFallback,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: mapHeight - _sheetOverlap,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildSheet(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ColoredBox(
      color: DriverPalette.cream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: DriverPalette.greenPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: DriverPalette.amberLight, width: 1.5),
              ),
              child: const Icon(
                Icons.local_taxi_rounded,
                color: DriverPalette.amber,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'TukiTuki Conductor',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: DriverPalette.greenPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('driver-home-logout-button'),
              onPressed: (_status == DriverHomeStatus.restoring || _loggingOut)
                  ? null
                  : _logout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DriverPalette.greenPrimary,
                      ),
                    )
                  : const Icon(Icons.logout, color: DriverPalette.greenPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet() {
    switch (_status) {
      case DriverHomeStatus.restoring:
        return _sheetShell(_buildRestoringSheet());
      case DriverHomeStatus.error:
        return _sheetShell(_buildErrorSheet());
      case DriverHomeStatus.busyRecovery:
        return _sheetShell(_buildBusyRecoverySheet());
      case DriverHomeStatus.offline:
        return _sheetShell(_buildOfflineSheet());
      case DriverHomeStatus.available:
        if (_offer != null) {
          return _sheetShell(_buildOfferSheet(_offer!));
        }
        if (_pendingProposals.isNotEmpty) {
          return _sheetShell(_buildProposalsSheet());
        }
        return _sheetShell(_buildAvailableSheet());
    }
  }

  /// El sheet vive en su PROPIA región física (un [Positioned] con
  /// `top: mapHeight - _sheetOverlap` en [build], no un
  /// `Column`+`Transform`): su caja real ya empieza en ese punto, así
  /// que pinta cream hasta el borde inferior sin dejar ningún hueco
  /// reservado-pero-no-pintado (un `Transform` solo mueve el dibujo,
  /// no la caja de layout, y eso era exactamente lo que producía la
  /// franja residual). `SafeArea(top:false)` sigue reservando el
  /// inset inferior seguro para que el CTA nunca quede bajo la barra
  /// de gestos, con el mismo cream de fondo detrás.
  Widget _sheetShell(Widget child) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: DriverPalette.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DriverPalette.brown.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestoringSheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: DriverPalette.greenPrimary,
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Preparando tu jornada',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Recuperando tu estado...',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
      ],
    );
  }

  Widget _buildErrorSheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusIconCircle(
          color: DriverPalette.coral,
          icon: Icons.error_outline,
        ),
        const SizedBox(height: 14),
        const Text(
          'No pudimos recuperar tu estado',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _errorMessage ?? 'Ocurrió un error inesperado.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _restoreInFlight
                ? null
                : () => unawaited(_restoreState()),
            style: FilledButton.styleFrom(
              backgroundColor: DriverPalette.greenPrimary,
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Reintentar'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusyRecoverySheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Recuperando tu viaje...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Estamos sincronizando tu viaje activo.',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _restoreInFlight
                ? null
                : () => unawaited(_restoreState()),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Reintentar'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineSheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sin icono aquí a propósito: el fallback del área de mapa ya
        // comunica "Conéctate para activar tu ubicación"; repetir un
        // icono en el sheet era redundante.
        const Text(
          'Estás desconectado',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Conéctate para comenzar a recibir solicitudes',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 16),
        // Con solo 2 tarjetas (sin EN LÍNEA), se acotan un poco los
        // lados para que no se sientan estiradas de borde a borde.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: _buildStatsRow(includeOnlineDuration: false),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _goOnline,
            style: FilledButton.styleFrom(
              backgroundColor: DriverPalette.greenPrimary,
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.power_settings_new),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_loading ? 'Conectando...' : 'Conectarme'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailableSheet() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusIconCircle(
          color: DriverPalette.greenAvailable,
          icon: Icons.check,
        ),
        const SizedBox(height: 14),
        const Text(
          'Estás disponible',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Esperando solicitudes de viaje',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        if (_gpsPillActive) ...[const SizedBox(height: 10), _buildGpsPill()],
        if (_showReducedAccuracyHint) ...[
          const SizedBox(height: 6),
          Text(
            'Activa la ubicación precisa para mejorar tu posición',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: DriverPalette.brown.withValues(alpha: 0.8),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildStatsRow(includeOnlineDuration: true),
        const SizedBox(height: 14),
        _buildTip(),
        if (_locationStatusMessage != null) ...[
          const SizedBox(height: 14),
          _buildLocationWarning(),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _goOffline,
            style: OutlinedButton.styleFrom(
              foregroundColor: DriverPalette.coral,
              side: const BorderSide(color: DriverPalette.coral),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.power_settings_new),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_loading ? 'Desconectando...' : 'Desconectarme'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow({required bool includeOnlineDuration}) {
    final cards = <Widget>[
      Expanded(
        child: _StatCard(value: _grossAmountDisplay, label: 'GANADO HOY'),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _StatCard(value: _completedRidesDisplay, label: 'VIAJES HOY'),
      ),
    ];

    if (includeOnlineDuration && _status == DriverHomeStatus.available) {
      cards.addAll([
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(value: _onlineDurationDisplay, label: 'EN LÍNEA'),
        ),
      ]);
    }

    return Row(children: cards);
  }

  Widget _buildGpsPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: DriverPalette.greenAvailable.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on,
            size: 14,
            color: DriverPalette.greenAvailable,
          ),
          const SizedBox(width: 6),
          Text(
            _gpsStatusLabel(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DriverPalette.greenAvailable,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DriverPalette.amberLight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lightbulb_outline,
            size: 18,
            color: DriverPalette.orangeDeep,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tip: Mantén tu ubicación activa para recibir solicitudes cercanas.',
              style: TextStyle(fontSize: 12.5, color: DriverPalette.brown),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off, color: DriverPalette.coral),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _locationStatusMessage ?? 'La ubicación no está disponible.',
              style: const TextStyle(color: DriverPalette.brown),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProposalsSheet() {
    final count = _pendingProposals.length;

    var primary = _pendingProposals.first;

    for (final proposal in _pendingProposals) {
      final currentExpiry = primary.expiresAt;
      final candidateExpiry = proposal.expiresAt;

      if (currentExpiry == null) {
        continue;
      }

      if (candidateExpiry != null && candidateExpiry.isBefore(currentExpiry)) {
        primary = proposal;
      }
    }

    final fare = primary.proposedFare ?? primary.passengerOfferFare;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _StatusIconCircle(
          color: DriverPalette.amber,
          icon: Icons.hourglass_top,
        ),
        const SizedBox(height: 14),
        Text(
          count > 1 ? 'Propuestas pendientes ($count)' : 'Propuesta enviada',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'S/ $fare',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Esperando que el pasajero elija a su conductor.',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 6),
        const Text(
          'Sigues disponible mientras esperas la respuesta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        if (count > 1) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _pendingProposals.map((proposal) {
              final chipFare =
                  proposal.proposedFare ?? proposal.passengerOfferFare;

              return Chip(
                label: Text('S/ $chipFare'),
                backgroundColor: DriverPalette.amberLight.withValues(
                  alpha: 0.4,
                ),
                side: BorderSide.none,
              );
            }).toList(),
          ),
        ],
        if (_locationStatusMessage != null) ...[
          const SizedBox(height: 14),
          _buildLocationWarning(),
        ],
      ],
    );
  }

  Widget _buildOfferSheet(DriverRideOffer offer) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Icon(
            Icons.notifications_active,
            size: 44,
            color: DriverPalette.orange,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '¡Nueva solicitud!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Precio recomendado TukiTuki',
          textAlign: TextAlign.center,
          style: TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 2),
        Text(
          'S/ ${offer.estimatedFare}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: DriverPalette.greenPrimary,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'El pasajero ofrece',
                style: TextStyle(color: DriverPalette.brown),
              ),
              const SizedBox(height: 4),
              Text(
                'S/ ${offer.passengerOfferFare}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: DriverPalette.greenPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
                title: const Text('Recoger en'),
                subtitle: Text(offer.originAddress),
              ),
              const Divider(height: 1),
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.location_on,
                  color: DriverPalette.orange,
                ),
                title: const Text('Destino'),
                subtitle: Text(offer.destinationAddress),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Estás a '
          '${(offer.distanceToOriginMeters / 1000).toStringAsFixed(1)} km '
          'del pasajero',
          textAlign: TextAlign.center,
          style: const TextStyle(color: DriverPalette.brown),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _accepting ? null : _acceptOffer,
          style: FilledButton.styleFrom(
            backgroundColor: DriverPalette.greenPrimary,
          ),
          icon: _accepting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _accepting
                  ? 'Enviando...'
                  : 'Aceptar S/ ${offer.passengerOfferFare}',
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _accepting ? null : _counterOffer,
          icon: const Icon(Icons.edit),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Hacer contraoferta'),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _accepting ? null : _rejectOffer,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('Rechazar solicitud'),
          ),
        ),
      ],
    );
  }
}

class _StatusIconCircle extends StatelessWidget {
  const _StatusIconCircle({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 28),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: DriverPalette.greenPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DriverPalette.brown,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverLocationException implements Exception {
  const _DriverLocationException(this.message, this.status);

  final String message;
  final DriverGpsStatus status;

  @override
  String toString() => message;
}
