import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/driver_offers_repository.dart';
import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_ride_offer.dart';
import 'driver_counter_offer_dialog.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() =>
      _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
    with WidgetsBindingObserver {
  bool _loading = false;
  bool _online = false;
  bool _accepting = false;
  bool _restoringState = true;

  bool _refreshingPresence = false;
  bool _loadingOffers = false;
  bool _navigatingToRide = false;
  bool _counterDialogOpen = false;

  DriverRideOffer? _offer;
  String? _pendingOfferId;
  String? _pendingProposedFare;

  String? _locationStatusMessage;
  DateTime? _lastLocationPublishedAt;

  Timer? _heartbeatTimer;
  Timer? _offersTimer;

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
        _online &&
        !_navigatingToRide) {
      debugPrint(
        'DRIVER APP RESUMED - refrescando presencia',
      );

      unawaited(_refreshDriverPresence());
      unawaited(_loadOffers());
    }
  }

  Future<void> _restoreState() async {
    bool redirected = false;

    try {
      final ridesRepository =
          ref.read(driverRidesRepositoryProvider);

      final operationsRepository =
          ref.read(driverOperationsRepositoryProvider);

      debugPrint(
        'DRIVER RESTORE - verificando viaje activo...',
      );

      final activeRide =
          await ridesRepository.getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        debugPrint(
          'DRIVER RESTORE - viaje activo encontrado',
        );

        redirected = true;
        _goToActiveRide();

        return;
      }

      debugPrint(
        'DRIVER RESTORE - consultando estado operativo...',
      );

      final status =
          await operationsRepository.getStatus();

      debugPrint(
        'DRIVER RESTORE - status=$status',
      );

      if (!mounted) {
        return;
      }

      if (status == 'BUSY') {
        final ride =
            await ridesRepository.getActiveRide();

        if (!mounted) {
          return;
        }

        if (ride != null) {
          redirected = true;
          _goToActiveRide();

          return;
        }
      }

      final isAvailable =
          status == 'AVAILABLE';

      setState(() {
        _online = isAvailable;
      });

      if (isAvailable) {
        /*
         * Backend conserva AVAILABLE entre aperturas.
         *
         * Recuperamos inmediatamente heartbeat +
         * ubicación real para volver a publicar al
         * Driver correctamente en Redis GEO.
         *
         * No solicitamos nuevamente permiso aquí:
         * solo comprobamos el permiso existente.
         */
        await _refreshDriverPresence();

        if (!mounted) {
          return;
        }

        if (_online) {
          _startOnlineWorkers();

          await _loadOffers();
        }
      }
    } on DioException catch (error) {
      debugPrint(
        'DRIVER RESTORE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type}',
      );
    } catch (error) {
      debugPrint(
        'DRIVER RESTORE ERROR inesperado: $error',
      );
    } finally {
      if (mounted && !redirected) {
        setState(() {
          _restoringState = false;
        });
      }
    }
  }

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
       * Antes de marcar AVAILABLE en Backend,
       * comprobamos que realmente podamos obtener
       * una posición.
       *
       * Así evitamos:
       *
       * AVAILABLE en PostgreSQL
       * pero sin ubicación en Redis GEO.
       */
      final initialPosition =
          await _getDriverPosition(
        requestPermission: true,
      );

      if (!mounted) {
        return;
      }

      final repository =
          ref.read(driverOperationsRepositoryProvider);

      debugPrint(
        'DRIVER ONLINE - conectando...',
      );

      final status =
          await repository.goOnline();

      debugPrint(
        'DRIVER ONLINE - backend status=$status',
      );

      if (status == 'BUSY') {
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

      if (status != 'AVAILABLE') {
        if (!mounted) {
          return;
        }

        setState(() {
          _online = false;
        });

        _showMessage(
          'El backend no dejó al conductor disponible.',
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _online = true;
      });

      /*
       * Ya tenemos la ubicación adquirida antes
       * de llamar ONLINE.
       *
       * La reutilizamos para evitar pedir dos
       * posiciones seguidas al GPS.
       */
      await _refreshDriverPresence(
        knownPosition: initialPosition,
      );

      if (!mounted) {
        return;
      }

      if (_online) {
        /*
         * Los workers ya NO vuelven a ejecutar
         * otro refresh inmediatamente.
         *
         * Evitamos el doble heartbeat/location
         * detectado en la auditoría.
         */
        _startOnlineWorkers();

        await _loadOffers();
      }
    } on _DriverLocationException catch (error) {
      debugPrint(
        'DRIVER GPS ERROR - ${error.message}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _online = false;
        _locationStatusMessage =
            error.message;
      });

      _showMessage(error.message);
    } on DioException catch (error) {
      debugPrint(
        'DRIVER ONLINE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type}',
      );

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
            'DRIVER ONLINE - error comprobando '
            'viaje activo: $secondaryError',
          );
        }
      }

      String message =
          'No se pudo conectar como conductor.';

      if (error.response?.statusCode == 400) {
        message =
            'No se pudo cambiar el estado del conductor.';
      } else if (error.response?.statusCode == 403) {
        message =
            'El conductor todavía no está aprobado.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);
    } catch (error) {
      debugPrint(
        'DRIVER ONLINE ERROR inesperado: $error',
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'No se pudo completar la conexión del conductor.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<Position> _getDriverPosition({
    required bool requestPermission,
  }) async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        throw const _DriverLocationException(
          'Activa la ubicación del dispositivo '
          'para conectarte como conductor.',
        );
      }

      var permission =
          await Geolocator.checkPermission();

      if (permission ==
              LocationPermission.denied &&
          requestPermission) {
        permission =
            await Geolocator.requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        throw const _DriverLocationException(
          'TukiTuki necesita permiso de ubicación '
          'para publicar tu posición y recibir viajes.',
        );
      }

      if (permission ==
          LocationPermission.deniedForever) {
        throw const _DriverLocationException(
          'El permiso de ubicación está bloqueado. '
          'Actívalo desde Ajustes del dispositivo.',
        );
      }

      if (permission !=
              LocationPermission.whileInUse &&
          permission !=
              LocationPermission.always) {
        throw const _DriverLocationException(
          'No fue posible obtener permiso de ubicación.',
        );
      }

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(
          const Duration(seconds: 12),
        );
      } on TimeoutException {
        throw const _DriverLocationException(
          'El GPS está tardando demasiado '
          'en obtener tu ubicación. '
          'Intenta nuevamente.',
        );
      }
    } on _DriverLocationException {
      rethrow;
    } catch (error) {
      debugPrint(
        'DRIVER GPS - error obteniendo posición: $error',
      );

      throw const _DriverLocationException(
        'No se pudo obtener tu ubicación GPS.',
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

    debugPrint(
      'DRIVER LOCATION OK '
      'lat=${position.latitude.toStringAsFixed(6)} '
      'lon=${position.longitude.toStringAsFixed(6)} '
      'accuracy=${position.accuracy.toStringAsFixed(1)} '
      'speed=${position.speed.toStringAsFixed(1)} '
      'heading=${position.heading.toStringAsFixed(1)}',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _locationStatusMessage = null;
      _lastLocationPublishedAt =
          DateTime.now();
    });
  }

  void _startOnlineWorkers() {
    _stopOnlineWorkers();

    if (!_online || _navigatingToRide) {
      return;
    }

    debugPrint(
      'DRIVER WORKERS - iniciados',
    );

    /*
     * Ya hicimos presencia y ofertas antes
     * de entrar aquí.
     *
     * Por eso NO ejecutamos nuevamente
     * heartbeat/location de inmediato.
     */

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        unawaited(
          _refreshDriverPresence(),
        );
      },
    );

    _offersTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) {
        unawaited(
          _loadOffers(),
        );
      },
    );
  }

  void _stopOnlineWorkers() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();

    _heartbeatTimer = null;
    _offersTimer = null;
  }

  Future<bool> _refreshDriverPresence({
    Position? knownPosition,
  }) async {
    if (!_online ||
        _refreshingPresence ||
        _navigatingToRide) {
      return false;
    }

    _refreshingPresence = true;

    try {
      final repository =
          ref.read(driverOperationsRepositoryProvider);

      /*
       * Heartbeat primero.
       *
       * Backend confirma que seguimos en un
       * estado operativo válido.
       */
      final heartbeatStatus =
          await repository.heartbeat();

      debugPrint(
        'DRIVER HEARTBEAT OK '
        'status=$heartbeatStatus',
      );

      if (heartbeatStatus == 'BUSY') {
        final activeRide = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return false;
        }

        if (activeRide != null) {
          debugPrint(
            'DRIVER HEARTBEAT - '
            'viaje activo detectado',
          );

          _goToActiveRide();
          return false;
        }
      }

      if (heartbeatStatus != 'AVAILABLE') {
        await _reconcileOperationalStatus();

        return false;
      }

      /*
       * Durante los ticks periódicos NO volvemos
       * a pedir permiso al usuario.
       *
       * Solo comprobamos el permiso existente.
       */
      final position =
          knownPosition ??
          await _getDriverPosition(
            requestPermission: false,
          );

      await _publishDriverLocation(
        repository,
        position,
      );

      return true;
    } on _DriverLocationException catch (error) {
      debugPrint(
        'DRIVER PRESENCE GPS ERROR - '
        '${error.message}',
      );

      if (mounted) {
        setState(() {
          _locationStatusMessage =
              '${error.message} '
              'Tu ubicación no puede actualizarse '
              'hasta resolverlo.';
        });
      }

      /*
       * No pedimos permiso repetidamente ni
       * mostramos SnackBar cada 10 segundos.
       *
       * El worker seguirá intentando y recuperará
       * automáticamente la publicación si vuelve
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

      if (error.response?.statusCode == 400) {
        await _reconcileOperationalStatus();
      } else if (error.response?.statusCode ==
          503) {
        if (mounted) {
          setState(() {
            _locationStatusMessage =
                'La ubicación no pudo publicarse '
                'para recibir viajes. '
                'TukiTuki volverá a intentarlo.';
          });
        }
      }

      return false;
    } catch (error) {
      debugPrint(
        'DRIVER PRESENCE ERROR inesperado: $error',
      );

      return false;
    } finally {
      _refreshingPresence = false;
    }
  }

  Future<void> _reconcileOperationalStatus() async {
    try {
      final actualStatus = await ref
          .read(driverOperationsRepositoryProvider)
          .getStatus();

      debugPrint(
        'DRIVER PRESENCE - '
        'status real=$actualStatus',
      );

      if (!mounted) {
        return;
      }

      if (actualStatus == 'BUSY') {
        final activeRide = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return;
        }

        if (activeRide != null) {
          debugPrint(
            'DRIVER PRESENCE - '
            'conductor seleccionado por pasajero',
          );

          _goToActiveRide();

          return;
        }
      }

      if (actualStatus != 'AVAILABLE') {
        _stopOnlineWorkers();

        setState(() {
          _online = false;
          _offer = null;
        });

        _showMessage(
          'El conductor dejó de estar disponible. '
          'Pulsa Conectarme nuevamente.',
        );
      }
    } catch (statusError) {
      debugPrint(
        'DRIVER PRESENCE - '
        'no se pudo consultar status: '
        '$statusError',
      );
    }
  }

  Future<void> _loadOffers() async {
    if (!_online ||
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
        debugPrint(
          'DRIVER OFFERS - viaje activo detectado',
        );

        _goToActiveRide();
        return;
      }

      final pendingOfferId =
          _pendingOfferId;

      if (pendingOfferId != null) {
        try {
          final pending = await ref
              .read(driverOffersRepositoryProvider)
              .getOffer(pendingOfferId);

          if (!mounted) {
            return;
          }

          debugPrint(
            'DRIVER PENDING PROPOSAL '
            'status=${pending.status}',
          );

          if (pending.status == 'PROPOSED') {
            setState(() {
              _offer = null;
              _pendingProposedFare =
                  pending.proposedFare ??
                  _pendingProposedFare;
            });

            return;
          }

          if (pending.status == 'ACCEPTED') {
            final selectedRide = await ref
                .read(driverRidesRepositoryProvider)
                .getActiveRide();

            if (!mounted) {
              return;
            }

            if (selectedRide != null) {
              _goToActiveRide();
            }

            return;
          }

          if (pending.status == 'CANCELLED' ||
              pending.status == 'EXPIRED' ||
              pending.status == 'REJECTED') {
            setState(() {
              _pendingOfferId = null;
              _pendingProposedFare = null;
            });

            _showMessage(
              'La solicitud terminó o el pasajero '
              'eligió otra propuesta.',
            );
          }
        } on DioException catch (error) {
          debugPrint(
            'DRIVER PENDING PROPOSAL ERROR '
            'status=${error.response?.statusCode}',
          );

          if (error.response?.statusCode ==
                  404 &&
              mounted) {
            setState(() {
              _pendingOfferId = null;
              _pendingProposedFare = null;
            });
          } else {
            return;
          }
        }
      }

      final offers = await ref
          .read(driverOffersRepositoryProvider)
          .getActiveOffers();

      debugPrint(
        'DRIVER OFFERS OK - '
        'cantidad=${offers.length}',
      );

      if (offers.isNotEmpty) {
        final first = offers.first;

        debugPrint(
          'DRIVER OFFER FOUND '
          'status=${first.status} '
          'distance=${first.distanceToOriginMeters} '
          'expiresAt=${first.expiresAt}',
        );
      }

      if (!mounted ||
          _counterDialogOpen ||
          _navigatingToRide) {
        return;
      }

      setState(() {
        _offer =
            offers.isEmpty
                ? null
                : offers.first;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFERS ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type} '
        'message=${error.message}',
      );
    } catch (error) {
      debugPrint(
        'DRIVER OFFERS ERROR inesperado: $error',
      );
    } finally {
      _loadingOffers = false;
    }
  }

  Future<void> _acceptOffer() async {
    final offer = _offer;

    if (offer == null ||
        _accepting ||
        _navigatingToRide) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      debugPrint(
        'DRIVER OFFER PROPOSAL - enviando...',
      );

      final proposed = await ref
          .read(driverOffersRepositoryProvider)
          .acceptOffer(offer.id);

      debugPrint(
        'DRIVER OFFER PROPOSAL OK '
        'status=${proposed.status}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
        _pendingOfferId = proposed.id;
        _pendingProposedFare =
            proposed.proposedFare ??
            offer.passengerOfferFare;
      });

      _showMessage(
        'Propuesta enviada al pasajero.',
      );
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFER ACCEPT ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      String message =
          'No se pudo enviar la propuesta.';

      if (error.response?.statusCode == 409) {
        message =
            'La oferta ya venció o fue asignada.';
      } else if (error.response?.statusCode ==
          404) {
        message =
            'La oferta ya no está disponible.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);

      await _loadOffers();
    } finally {
      if (mounted &&
          !_navigatingToRide) {
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
      proposedFare =
          await showDriverCounterOfferDialog(
        context: context,
        passengerOfferFare:
            offer.passengerOfferFare,
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

    if (!mounted ||
        proposedFare == null) {
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
      debugPrint(
        'DRIVER COUNTER OFFER - '
        'enviando S/ $proposedFare',
      );

      final proposed = await ref
          .read(driverOffersRepositoryProvider)
          .counterOffer(
            offer.id,
            proposedFare,
          );

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
        _pendingOfferId = proposed.id;
        _pendingProposedFare =
            proposed.proposedFare ??
            proposedFare;
      });

      _showMessage(
        'Contraoferta enviada al pasajero.',
      );
    } on DioException catch (error) {
      debugPrint(
        'DRIVER COUNTER OFFER ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      final statusCode =
          error.response?.statusCode;

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
          hasResponse:
              error.response != null,
        ),
      );

      reloadOffers = true;
    } finally {
      if (mounted &&
          !_navigatingToRide) {
        setState(() {
          _accepting = false;
        });
      }
    }

    if (reloadOffers &&
        mounted &&
        !_navigatingToRide) {
      await _loadOffers();
    }
  }

  Future<void> _rejectOffer() async {
    final offer = _offer;

    if (offer == null ||
        _accepting ||
        _navigatingToRide) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      await ref
          .read(driverOffersRepositoryProvider)
          .rejectOffer(offer.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
      });

      _showMessage(
        'Solicitud rechazada.',
      );

      await _loadOffers();
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFER REJECT ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      String message =
          'No se pudo rechazar la solicitud.';

      if (error.response?.statusCode == 409) {
        message =
            'La solicitud ya venció o dejó de estar disponible.';
      } else if (error.response?.statusCode ==
          404) {
        message =
            'La solicitud ya no está disponible.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);
    } finally {
      if (mounted &&
          !_navigatingToRide) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  Future<void> _goOffline() async {
    if (_loading ||
        _navigatingToRide) {
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

      final status = await ref
          .read(driverOperationsRepositoryProvider)
          .goOffline();

      debugPrint(
        'DRIVER OFFLINE OK status=$status',
      );

      if (status != 'OFFLINE') {
        _showMessage(
          'El backend no confirmó la desconexión.',
        );

        return;
      }

      _stopOnlineWorkers();

      if (!mounted) {
        return;
      }

      setState(() {
        _online = false;
        _offer = null;
        _pendingOfferId = null;
        _pendingProposedFare = null;
        _locationStatusMessage = null;
        _lastLocationPublishedAt = null;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFLINE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

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
            'DRIVER OFFLINE - '
            'error comprobando viaje: '
            '$secondaryError',
          );
        }
      }

      _showMessage(
        'No se pudo desconectar al conductor.',
      );
    } finally {
      if (mounted &&
          !_navigatingToRide) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    _stopOnlineWorkers();

    if (_online) {
      try {
        await ref
            .read(driverOperationsRepositoryProvider)
            .goOffline();
      } catch (error) {
        debugPrint(
          'DRIVER LOGOUT - '
          'no se pudo poner OFFLINE: $error',
        );
      }
    }

    await ref
        .read(authRepositoryProvider)
        .logout();

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  void _goToActiveRide() {
    if (!mounted ||
        _counterDialogOpen ||
        _navigatingToRide) {
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

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restoringState) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Recuperando tu estado...',
                  style:
                      TextStyle(
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            const Text(
          'TukiTuki Conductor',
        ),
        actions: [
          IconButton(
            onPressed:
                _logout,
            icon:
                const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.all(
            24,
          ),
          child: _offer != null
              ? _buildOffer(_offer!)
              : _buildStatus(),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    if (_online &&
        _pendingOfferId != null) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.hourglass_top,
                size: 90,
              ),
              const SizedBox(
                height: 24,
              ),
              const Text(
                'Propuesta enviada',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              if (_pendingProposedFare !=
                  null)
                Text(
                  'S/ $_pendingProposedFare',
                  style:
                      const TextStyle(
                    fontSize: 32,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              const SizedBox(
                height: 16,
              ),
              const Text(
                'Esperando que el pasajero '
                'elija a su conductor.',
                textAlign:
                    TextAlign.center,
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Sigues disponible mientras '
                'esperas la respuesta.',
                textAlign:
                    TextAlign.center,
              ),
              if (_locationStatusMessage !=
                  null) ...[
                const SizedBox(
                  height: 20,
                ),
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
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              _online
                  ? Icons.check_circle
                  : Icons.offline_bolt_outlined,
              size: 90,
            ),
            const SizedBox(
              height: 24,
            ),
            Text(
              _online
                  ? 'Estás disponible'
                  : 'Estás desconectado',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                fontSize: 28,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _online
                  ? 'Esperando solicitudes de viaje'
                  : 'Conéctate para recibir viajes',
              textAlign:
                  TextAlign.center,
            ),
            if (_online &&
                _lastLocationPublishedAt !=
                    null &&
                _locationStatusMessage ==
                    null) ...[
              const SizedBox(
                height: 12,
              ),
              const Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Ubicación GPS activa',
                  ),
                ],
              ),
            ],
            if (_locationStatusMessage !=
                null) ...[
              const SizedBox(
                height: 20,
              ),
              _buildLocationWarning(),
            ],
            const SizedBox(
              height: 32,
            ),
            SizedBox(
              width:
                  double.infinity,
              child:
                  FilledButton(
                onPressed:
                    _loading
                        ? null
                        : _online
                            ? _goOffline
                            : _goOnline,
                child:
                    Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  child:
                      _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth:
                                    2,
                              ),
                            )
                          : Text(
                              _online
                                  ? 'Desconectarme'
                                  : 'Conectarme',
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationWarning() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.location_off,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Text(
                _locationStatusMessage ??
                    'La ubicación no está disponible.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffer(
    DriverRideOffer offer,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          const SizedBox(
            height: 20,
          ),
          const Icon(
            Icons.notifications_active,
            size: 72,
          ),
          const SizedBox(
            height: 16,
          ),
          const Text(
            '¡Nuevo viaje!',
            textAlign:
                TextAlign.center,
            style:
                TextStyle(
              fontSize: 30,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          const Text(
            'Precio recomendado TukiTuki',
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'S/ ${offer.estimatedFare}',
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 24,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          const SizedBox(
            height: 20,
          ),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                20,
              ),
              child: Column(
                children: [
                  const Text(
                    'El pasajero ofrece',
                    style:
                        TextStyle(
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'S/ ${offer.passengerOfferFare}',
                    style:
                        const TextStyle(
                      fontSize: 38,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 24,
          ),
          Card(
            child: Padding(
              padding:
                  const EdgeInsets.all(
                16,
              ),
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(
                      Icons.my_location,
                    ),
                    title:
                        const Text(
                      'Recoger en',
                    ),
                    subtitle:
                        Text(
                      offer.originAddress,
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading:
                        const Icon(
                      Icons.location_on,
                    ),
                    title:
                        const Text(
                      'Destino',
                    ),
                    subtitle:
                        Text(
                      offer.destinationAddress,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(
            height: 16,
          ),
          Text(
            'Estás a '
            '${(offer.distanceToOriginMeters / 1000).toStringAsFixed(1)} km '
            'del pasajero',
            textAlign:
                TextAlign.center,
          ),
          const SizedBox(
            height: 28,
          ),
          FilledButton.icon(
            onPressed:
                _accepting
                    ? null
                    : _acceptOffer,
            icon:
                _accepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth:
                              2,
                        ),
                      )
                    : const Icon(
                        Icons.check,
                      ),
            label:
                Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 16,
              ),
              child:
                  Text(
                _accepting
                    ? 'Enviando...'
                    : 'Aceptar S/ '
                        '${offer.passengerOfferFare}',
              ),
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          OutlinedButton.icon(
            onPressed:
                _accepting
                    ? null
                    : _counterOffer,
            icon:
                const Icon(
              Icons.edit,
            ),
            label:
                const Padding(
              padding:
                  EdgeInsets.symmetric(
                vertical: 16,
              ),
              child:
                  Text(
                'Hacer contraoferta',
              ),
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          TextButton(
            onPressed:
                _accepting
                    ? null
                    : _rejectOffer,
            child:
                const Padding(
              padding:
                  EdgeInsets.symmetric(
                vertical: 12,
              ),
              child:
                  Text(
                'Rechazar solicitud',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverLocationException
    implements Exception {
  const _DriverLocationException(
    this.message,
  );

  final String message;

  @override
  String toString() => message;
}
