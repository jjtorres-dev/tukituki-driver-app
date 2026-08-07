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
  ConsumerState<DriverHomeScreen> createState() =>
      _DriverHomeScreenState();
}

class _DriverHomeScreenState
    extends ConsumerState<DriverHomeScreen> {
  bool _loading = false;
  bool _online = false;
  bool _accepting = false;
  bool _restoringState = true;

  DriverRideOffer? _offer;

  Timer? _heartbeatTimer;
  Timer? _offersTimer;

  @override
  void initState() {
    super.initState();

    _restoreState();
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();

    super.dispose();
  }

  Future<void> _restoreState() async {
    bool redirected = false;

    try {
      final ridesRepository = ref.read(
        driverRidesRepositoryProvider,
      );

      final operationsRepository = ref.read(
        driverOperationsRepositoryProvider,
      );

      // 1. Primero comprobamos si ya existe
      // un viaje activo.
      final activeRide =
          await ridesRepository.getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        redirected = true;

        _heartbeatTimer?.cancel();
        _offersTimer?.cancel();

        context.go('/active-ride');
        return;
      }

      // 2. Si no hay viaje, consultamos
      // el estado operativo.
      final status =
          await operationsRepository.getStatus();

      if (!mounted) {
        return;
      }

      // 3. Si backend dice BUSY, comprobamos
      // nuevamente el viaje antes de mostrar Home.
      if (status == 'BUSY') {
        final ride =
            await ridesRepository.getActiveRide();

        if (!mounted) {
          return;
        }

        if (ride != null) {
          redirected = true;

          _heartbeatTimer?.cancel();
          _offersTimer?.cancel();

          context.go('/active-ride');
          return;
        }
      }

      setState(() {
        _online = status == 'AVAILABLE';
      });

      if (_online) {
        _startOnlineWorkers();
      }
    } catch (error) {
      debugPrint(
        'Error restaurando estado del conductor: $error',
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
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // Antes de intentar ONLINE,
      // comprobamos si existe un viaje activo.
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        _heartbeatTimer?.cancel();
        _offersTimer?.cancel();

        context.go('/active-ride');
        return;
      }

      final repository = ref.read(
        driverOperationsRepositoryProvider,
      );

      final status =
          await repository.goOnline();

      await repository.updateTestLocation();
      await repository.heartbeat();

      if (!mounted) {
        return;
      }

      if (status == 'BUSY') {
        final ride = await ref
            .read(driverRidesRepositoryProvider)
            .getActiveRide();

        if (!mounted) {
          return;
        }

        if (ride != null) {
          context.go('/active-ride');
          return;
        }
      }

      setState(() {
        _online = status == 'AVAILABLE';
      });

      if (_online) {
        _startOnlineWorkers();
      }
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      // Un 400 también puede ocurrir porque
      // el conductor ya tiene viaje y está BUSY.
      if (error.response?.statusCode == 400) {
        try {
          final activeRide = await ref
              .read(driverRidesRepositoryProvider)
              .getActiveRide();

          if (!mounted) {
            return;
          }

          if (activeRide != null) {
            _heartbeatTimer?.cancel();
            _offersTimer?.cancel();

            context.go('/active-ride');
            return;
          }
        } catch (_) {
          // Seguimos con el mensaje genérico.
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
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

  void _startOnlineWorkers() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();

    _loadOffers();

    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) async {
        try {
          final repository = ref.read(
            driverOperationsRepositoryProvider,
          );

          await repository.heartbeat();
          await repository.updateTestLocation();
        } catch (_) {
          // Se intentará nuevamente.
        }
      },
    );

    _offersTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _loadOffers(),
    );
  }

  Future<void> _loadOffers() async {
    if (!_online || _accepting) {
      return;
    }

    try {
      // Primero verificamos si el conductor
      // ya recibió/asignó un viaje.
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        _heartbeatTimer?.cancel();
        _offersTimer?.cancel();

        context.go('/active-ride');
        return;
      }

      final offers = await ref
          .read(driverOffersRepositoryProvider)
          .getActiveOffers();

      if (!mounted) {
        return;
      }

      setState(() {
        _offer =
            offers.isEmpty ? null : offers.first;
      });
    } catch (_) {
      // Seguiremos intentando
      // en el siguiente polling.
    }
  }

  Future<void> _acceptOffer() async {
    final offer = _offer;

    if (offer == null || _accepting) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      await ref
          .read(driverOffersRepositoryProvider)
          .acceptOffer(offer.id);

      if (!mounted) {
        return;
      }

      // El backend acaba de poner al conductor
      // BUSY y asignó el viaje.
      _heartbeatTimer?.cancel();
      _offersTimer?.cancel();

      context.go('/active-ride');
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }

      String message =
          'No se pudo aceptar la oferta.';

      if (error.response?.statusCode == 409) {
        message =
            'La oferta ya venció o fue asignada.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );

      await _loadOffers();
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  Future<void> _goOffline() async {
    if (_loading) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // No permitimos intentar OFFLINE
      // si ya existe un viaje.
      final activeRide = await ref
          .read(driverRidesRepositoryProvider)
          .getActiveRide();

      if (!mounted) {
        return;
      }

      if (activeRide != null) {
        _heartbeatTimer?.cancel();
        _offersTimer?.cancel();

        context.go('/active-ride');
        return;
      }

      await ref
          .read(driverOperationsRepositoryProvider)
          .goOffline();

      _heartbeatTimer?.cancel();
      _offersTimer?.cancel();

      if (!mounted) {
        return;
      }

      setState(() {
        _online = false;
        _offer = null;
      });
    } on DioException catch (error) {
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
            context.go('/active-ride');
            return;
          }
        } catch (_) {}
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo desconectar al conductor.',
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

  Future<void> _logout() async {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();

    // Solo intentamos OFFLINE si la UI
    // realmente sabe que está AVAILABLE.
    if (_online) {
      try {
        await ref
            .read(driverOperationsRepositoryProvider)
            .goOffline();
      } catch (_) {
        // Logout continúa aunque no pueda
        // cambiar el estado operativo.
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
                  'Recuperando tu viaje...',
                  style: TextStyle(
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
        title: const Text(
          'TukiTuki Conductor',
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(
              Icons.logout,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _offer != null
              ? _buildOffer(_offer!)
              : _buildStatus(),
        ),
      ),
    );
  }

  Widget _buildStatus() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _online
                ? Icons.check_circle
                : Icons.offline_bolt_outlined,
            size: 90,
          ),

          const SizedBox(height: 24),

          Text(
            _online
                ? 'Estás disponible'
                : 'Estás desconectado',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
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
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 16,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
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
          const SizedBox(height: 20),

          const Icon(
            Icons.notifications_active,
            size: 72,
          ),

          const SizedBox(height: 16),

          const Text(
            '¡Nuevo viaje!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'S/ ${offer.estimatedFare}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.my_location,
                    ),
                    title: const Text(
                      'Recoger en',
                    ),
                    subtitle: Text(
                      offer.originAddress,
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    leading: const Icon(
                      Icons.location_on,
                    ),
                    title: const Text(
                      'Destino',
                    ),
                    subtitle: Text(
                      offer.destinationAddress,
                    ),
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
            onPressed:
                _accepting ? null : _acceptOffer,
            icon: _accepting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.check,
                  ),
            label: Padding(
              padding:
                  const EdgeInsets.symmetric(
                vertical: 16,
              ),
              child: Text(
                _accepting
                    ? 'Aceptando...'
                    : 'Aceptar viaje',
              ),
            ),
          ),
        ],
      ),
    );
  }
}