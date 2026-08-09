import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/driver_offers_repository.dart';
import '../data/driver_operations_repository.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_ride_offer.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
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

  DriverRideOffer? _offer;
  String? _pendingOfferId;
  String? _pendingProposedFare;

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
    if (state == AppLifecycleState.resumed && _online && !_navigatingToRide) {
      debugPrint('DRIVER APP RESUMED - refrescando presencia');

      unawaited(_refreshDriverPresence());
      unawaited(_loadOffers());
    }
  }

  Future<void> _restoreState() async {
    bool redirected = false;

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

      debugPrint('DRIVER RESTORE - consultando estado operativo...');

      final status = await operationsRepository.getStatus();

      debugPrint('DRIVER RESTORE - status=$status');

      if (!mounted) {
        return;
      }

      if (status == 'BUSY') {
        final ride = await ridesRepository.getActiveRide();

        if (!mounted) {
          return;
        }

        if (ride != null) {
          redirected = true;
          _goToActiveRide();

          return;
        }
      }

      final isAvailable = status == 'AVAILABLE';

      setState(() {
        _online = isAvailable;
      });

      if (isAvailable) {
        // Muy importante:
        // no esperamos al primer Timer.
        // Refrescamos presencia inmediatamente.
        await _refreshDriverPresence();

        if (!mounted) {
          return;
        }

        if (_online) {
          _startOnlineWorkers();
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
      debugPrint('DRIVER RESTORE ERROR inesperado: $error');
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

      final repository = ref.read(driverOperationsRepositoryProvider);

      debugPrint('DRIVER ONLINE - conectando...');

      final status = await repository.goOnline();

      debugPrint('DRIVER ONLINE - backend status=$status');

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

        _showMessage('El backend no dejó al conductor disponible.');

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _online = true;
      });

      // Inmediatamente después de ONLINE:
      // heartbeat + GPS.
      await _refreshDriverPresence();

      if (!mounted) {
        return;
      }

      if (_online) {
        _startOnlineWorkers();

        await _loadOffers();
      }
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

      String message = 'No se pudo conectar como conductor.';

      if (error.response?.statusCode == 400) {
        message = 'No se pudo cambiar el estado del conductor.';
      } else if (error.response?.statusCode == 403) {
        message = 'El conductor todavía no está aprobado.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _startOnlineWorkers() {
    _stopOnlineWorkers();

    if (!_online || _navigatingToRide) {
      return;
    }

    debugPrint('DRIVER WORKERS - iniciados');

    // Lo ejecutamos ya, sin esperar al Timer.
    unawaited(_refreshDriverPresence());
    unawaited(_loadOffers());

    // En staging usamos 10 segundos
    // para mantener lastSeenAt fresco.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_refreshDriverPresence());
    });

    // Revisamos ofertas cada 3 segundos.
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

  Future<void> _refreshDriverPresence() async {
    if (!_online || _refreshingPresence || _navigatingToRide) {
      return;
    }

    _refreshingPresence = true;

    try {
      final repository = ref.read(driverOperationsRepositoryProvider);

      // Heartbeat primero:
      // el backend confirma que seguimos online.
      final heartbeatStatus = await repository.heartbeat();

      debugPrint(
        'DRIVER HEARTBEAT OK '
        'status=$heartbeatStatus',
      );

      // Luego refrescamos la ubicación.
      await repository.updateTestLocation();

      debugPrint(
        'DRIVER LOCATION OK '
        'lat=-6.4877 lon=-76.3599',
      );
    } on DioException catch (error) {
      debugPrint(
        'DRIVER PRESENCE ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data} '
        'type=${error.type} '
        'message=${error.message}',
      );

      // Swagger indica que heartbeat 400 significa
      // que el conductor está desconectado.
      if (error.response?.statusCode == 400) {
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
    } catch (error) {
      debugPrint('DRIVER PRESENCE ERROR inesperado: $error');
    } finally {
      _refreshingPresence = false;
    }
  }

  Future<void> _loadOffers() async {
    if (!_online || _accepting || _loadingOffers || _navigatingToRide) {
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

      final pendingOfferId = _pendingOfferId;

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
                  pending.proposedFare ?? _pendingProposedFare;
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

          if (error.response?.statusCode == 404 && mounted) {
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

      debugPrint('DRIVER OFFERS OK - cantidad=${offers.length}');

      if (offers.isNotEmpty) {
        final first = offers.first;

        debugPrint(
          'DRIVER OFFER FOUND '
          'status=${first.status} '
          'distance=${first.distanceToOriginMeters} '
          'expiresAt=${first.expiresAt}',
        );
      }

      if (!mounted || _navigatingToRide) {
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
    } catch (error) {
      debugPrint('DRIVER OFFERS ERROR inesperado: $error');
    } finally {
      _loadingOffers = false;
    }
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
            proposed.proposedFare ?? offer.passengerOfferFare;
      });

      _showMessage('Propuesta enviada al pasajero.');
    } on DioException catch (error) {
      debugPrint(
        'DRIVER OFFER ACCEPT ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

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
      if (mounted && !_navigatingToRide) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  Future<void> _counterOffer() async {
    final offer = _offer;

    if (offer == null || _accepting || _navigatingToRide) {
      return;
    }

    final controller = TextEditingController();
    String? validationError;

    final proposedFare = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Hacer contraoferta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'El pasajero ofrece '
                    'S/ ${offer.passengerOfferFare}',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Tu contraoferta',
                      prefixText: 'S/ ',
                      errorText: validationError,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final raw = controller.text.trim().replaceAll(',', '.');

                    final value = double.tryParse(raw);

                    final passengerValue = double.tryParse(
                      offer.passengerOfferFare,
                    );

                    if (value == null || value <= 0) {
                      setDialogState(() {
                        validationError = 'Ingresa un monto válido.';
                      });
                      return;
                    }

                    final parts = raw.split('.');

                    if (parts.length > 2 ||
                        (parts.length == 2 && parts[1].length > 2)) {
                      setDialogState(() {
                        validationError = 'Usa como máximo 2 decimales.';
                      });
                      return;
                    }

                    if (passengerValue != null && value <= passengerValue) {
                      setDialogState(() {
                        validationError =
                            'La contraoferta debe ser '
                            'mayor que S/ '
                            '${offer.passengerOfferFare}.';
                      });
                      return;
                    }

                    if (value > 9999.99) {
                      setDialogState(() {
                        validationError = 'El monto es demasiado alto.';
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(value.toStringAsFixed(2));
                  },
                  child: const Text('Enviar'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();

    if (proposedFare == null || !mounted) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      debugPrint(
        'DRIVER COUNTER OFFER - '
        'enviando S/ $proposedFare',
      );

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
        _pendingOfferId = proposed.id;
        _pendingProposedFare = proposed.proposedFare ?? proposedFare;
      });

      _showMessage('Contraoferta enviada al pasajero.');
    } on DioException catch (error) {
      debugPrint(
        'DRIVER COUNTER OFFER ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      String message = 'No se pudo enviar la contraoferta.';

      if (error.response?.statusCode == 400) {
        message =
            'El monto de la contraoferta '
            'no es válido.';
      } else if (error.response?.statusCode == 409) {
        message =
            'La oferta ya venció o '
            'dejó de estar disponible.';
      } else if (error.response?.statusCode == 404) {
        message = 'La oferta ya no está disponible.';
      } else if (error.response == null) {
        message = 'No se pudo conectar con TukiTuki.';
      }

      _showMessage(message);

      await _loadOffers();
    } finally {
      if (mounted && !_navigatingToRide) {
        setState(() {
          _accepting = false;
        });
      }
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
      if (mounted && !_navigatingToRide) {
        setState(() {
          _accepting = false;
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

      final status = await ref
          .read(driverOperationsRepositoryProvider)
          .goOffline();

      debugPrint('DRIVER OFFLINE OK status=$status');

      _stopOnlineWorkers();

      if (!mounted) {
        return;
      }

      setState(() {
        _online = false;
        _offer = null;
        _pendingOfferId = null;
        _pendingProposedFare = null;
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

      _showMessage('No se pudo desconectar al conductor.');
    } finally {
      if (mounted && !_navigatingToRide) {
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
        await ref.read(driverOperationsRepositoryProvider).goOffline();
      } catch (error) {
        debugPrint(
          'DRIVER LOGOUT - '
          'no se pudo poner OFFLINE: $error',
        );
      }
    }

    await ref.read(authRepositoryProvider).logout();

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  void _goToActiveRide() {
    if (!mounted || _navigatingToRide) {
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

  @override
  Widget build(BuildContext context) {
    if (_restoringState) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Recuperando tu estado...',
                  style: TextStyle(fontSize: 18),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TukiTuki Conductor'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _offer != null ? _buildOffer(_offer!) : _buildStatus(),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    if (_online && _pendingOfferId != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top, size: 90),
            const SizedBox(height: 24),
            const Text(
              'Propuesta enviada',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_pendingProposedFare != null)
              Text(
                'S/ $_pendingProposedFare',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 16),
            const Text(
              'Esperando que el pasajero '
              'elija a su conductor.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sigues disponible mientras '
              'esperas la respuesta.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _online ? Icons.check_circle : Icons.offline_bolt_outlined,
            size: 90,
          ),

          const SizedBox(height: 24),

          Text(
            _online ? 'Estás disponible' : 'Estás desconectado',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          Text(
            _online
                ? 'Esperando solicitudes de viaje'
                : 'Conéctate para recibir viajes',
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading
                  ? null
                  : _online
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
                    : Text(_online ? 'Desconectarme' : 'Conectarme'),
              ),
            ),
          ),
        ],
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
                    : 'Aceptar S/ '
                          '${offer.passengerOfferFare}',
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
