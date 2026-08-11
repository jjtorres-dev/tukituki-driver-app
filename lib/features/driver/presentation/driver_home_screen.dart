import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/secure_storage.dart';
import '../../auth/data/auth_repository.dart';
import '../data/driver_offers_repository.dart';
import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_daily_stats.dart';
import '../domain/driver_operational_state.dart';
import '../domain/driver_pending_proposal.dart';
import '../domain/driver_ride_offer.dart';
import 'driver_counter_offer_dialog.dart';

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
  String? _statsError;
  String? _errorMessage;

  DriverRideOffer? _offer;
  List<DriverPendingProposal> _pendingProposals = const [];

  String? _locationStatusMessage;
  Position? _lastPosition;
  DateTime? _lastPositionAt;
  DriverGpsStatus _gpsStatus = DriverGpsStatus.unknown;

  Timer? _heartbeatTimer;
  Timer? _offersTimer;

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
        await _refreshDriverPresence();

        if (!mounted) {
          return false;
        }

        if (_status == DriverHomeStatus.available) {
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
        _statsError = null;
      });
    } catch (error) {
      debugPrint('DRIVER STATS ERROR: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _statsError = 'No se pudieron cargar tus estadísticas de hoy.';
      });
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
        _lastPosition = null;
        _lastPositionAt = null;
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
  }

  void _stopOnlineWorkers() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();

    _heartbeatTimer = null;
    _offersTimer = null;
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

    _loggingOut = true;

    _stopOnlineWorkers();

    if (_status == DriverHomeStatus.available) {
      try {
        await ref.read(driverOperationsRepositoryProvider).goOffline();
      } catch (error) {
        debugPrint('DRIVER LOGOUT - no se pudo poner OFFLINE: $error');
      }
    }

    await ref.read(authRepositoryProvider).logout();

    _loggingOut = false;

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

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TukiTuki Conductor'),
        actions: [
          IconButton(
            onPressed: _status == DriverHomeStatus.restoring ? null : _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case DriverHomeStatus.restoring:
        return _buildRestoring();

      case DriverHomeStatus.error:
        return _buildError();

      case DriverHomeStatus.busyRecovery:
        return _buildBusyRecovery();

      case DriverHomeStatus.offline:
      case DriverHomeStatus.available:
        return _offer != null ? _buildOffer(_offer!) : _buildStatus();
    }
  }

  Widget _buildRestoring() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Preparando tu jornada',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('Recuperando tu estado...', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 80),
            const SizedBox(height: 20),
            const Text(
              'No pudimos recuperar tu estado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Ocurrió un error inesperado.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _restoreInFlight
                    ? null
                    : () => unawaited(_restoreState()),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Reintentar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusyRecovery() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Recuperando tu viaje...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tu estado indica un viaje en curso. '
              'Estamos confirmándolo con TukiTuki.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _restoreInFlight
                    ? null
                    : () => unawaited(_restoreState()),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Reintentar'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final isAvailable = _status == DriverHomeStatus.available;

    if (isAvailable && _pendingProposals.isNotEmpty) {
      final proposal = _pendingProposals.first;
      final fare = proposal.proposedFare ?? proposal.passengerOfferFare;

      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top, size: 90),
              const SizedBox(height: 24),
              Text(
                _pendingProposals.length > 1
                    ? '${_pendingProposals.length} propuestas enviadas'
                    : 'Propuesta enviada',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'S/ $fare',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Esperando que el pasajero elija a su conductor.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sigues disponible mientras esperas la respuesta.',
                textAlign: TextAlign.center,
              ),
              if (_locationStatusMessage != null) ...[
                const SizedBox(height: 20),
                _buildLocationWarning(),
              ],
            ],
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAvailable ? Icons.check_circle : Icons.offline_bolt_outlined,
              size: 90,
            ),
            const SizedBox(height: 24),
            Text(
              isAvailable ? 'Estás disponible' : 'Estás desconectado',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isAvailable
                  ? 'Esperando solicitudes de viaje'
                  : 'Conéctate para recibir viajes',
              textAlign: TextAlign.center,
            ),
            if (isAvailable &&
                _lastPosition != null &&
                _locationStatusMessage == null) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _effectiveGpsStatus == DriverGpsStatus.active
                        ? Icons.location_on
                        : Icons.location_searching,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(_gpsStatusLabel()),
                ],
              ),
            ],
            if (_locationStatusMessage != null) ...[
              const SizedBox(height: 20),
              _buildLocationWarning(),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _loading
                    ? null
                    : isAvailable
                    ? _goOffline
                    : _goOnline,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isAvailable ? 'Desconectarme' : 'Conectarme'),
                ),
              ),
            ),
            _buildDailyStatsSection(),
          ],
        ),
      ),
    );
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

  Widget _buildDailyStatsSection() {
    final stats = _dailyStats;

    if (stats == null && _statsError == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: stats != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(
                      label: 'Ganado hoy',
                      value: 'S/ ${stats.grossAmount}',
                    ),
                    _StatColumn(
                      label: 'Viajes',
                      value: '${stats.completedRides}',
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        _statsError ??
                            'No se pudieron cargar tus estadísticas de hoy.',
                      ),
                    ),
                    TextButton(
                      onPressed: _loadingStats
                          ? null
                          : () => unawaited(_loadDailyStats()),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildLocationWarning() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_off),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _locationStatusMessage ?? 'La ubicación no está disponible.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffer(DriverRideOffer offer) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          const Icon(Icons.notifications_active, size: 72),
          const SizedBox(height: 16),
          const Text(
            '¡Nuevo viaje!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Precio recomendado TukiTuki',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'S/ ${offer.estimatedFare}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'El pasajero ofrece',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'S/ ${offer.passengerOfferFare}',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.my_location),
                    title: const Text('Recoger en'),
                    subtitle: Text(offer.originAddress),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.location_on),
                    title: const Text('Destino'),
                    subtitle: Text(offer.destinationAddress),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Estás a '
            '${(offer.distanceToOriginMeters / 1000).toStringAsFixed(1)} km '
            'del pasajero',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _accepting ? null : _acceptOffer,
            icon: _accepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                _accepting
                    ? 'Enviando...'
                    : 'Aceptar S/ ${offer.passengerOfferFare}',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _accepting ? null : _counterOffer,
            icon: const Icon(Icons.edit),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Hacer contraoferta'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _accepting ? null : _rejectOffer,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Rechazar solicitud'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label),
      ],
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
