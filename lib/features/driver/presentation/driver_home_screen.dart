import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_repository.dart';
import '../data/driver_offers_repository.dart';
import '../data/driver_operations_repository.dart';
import '../domain/driver_ride_offer.dart';

class DriverHomeScreen
    extends ConsumerStatefulWidget {
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

  DriverRideOffer? _offer;

  Timer? _heartbeatTimer;
  Timer? _offersTimer;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _offersTimer?.cancel();
    super.dispose();
  }

  Future<void> _goOnline() async {
    setState(() {
      _loading = true;
    });

    try {
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

      String message =
          'No se pudo conectar como conductor.';

      if (error.response?.statusCode == 400) {
        message =
            'El vehículo o los documentos no están válidos.';
      } else if (error.response?.statusCode == 403) {
        message =
            'El conductor todavía no está aprobado.';
      } else if (error.response == null) {
        message =
            'No se pudo conectar con TukiTuki.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
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
        } catch (_) {}
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
      // Seguiremos intentando en el siguiente polling.
    }
  }

  Future<void> _acceptOffer() async {
    final offer = _offer;

    if (offer == null) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      final accepted = await ref
          .read(driverOffersRepositoryProvider)
          .acceptOffer(offer.id);

      _offersTimer?.cancel();

      if (!mounted) {
        return;
      }

      setState(() {
        _offer = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '¡Viaje aceptado! Estado: ${accepted.status}',
          ),
        ),
      );
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
        SnackBar(content: Text(message)),
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
    setState(() {
      _loading = true;
    });

    try {
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

    if (_online) {
      try {
        await ref
            .read(driverOperationsRepositoryProvider)
            .goOffline();
      } catch (_) {}
    }

    await ref
        .read(authRepositoryProvider)
        .logout();

    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TukiTuki Conductor',
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
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
                    leading:
                        const Icon(Icons.my_location),
                    title:
                        const Text('Recoger en'),
                    subtitle: Text(
                      offer.originAddress,
                    ),
                  ),

                  const Divider(),

                  ListTile(
                    leading:
                        const Icon(Icons.location_on),
                    title:
                        const Text('Destino'),
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
                : const Icon(Icons.check),
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