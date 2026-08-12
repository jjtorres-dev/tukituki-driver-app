import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/driver_palette.dart';
import '../data/driver_rides_repository.dart';
import '../domain/driver_pending_payment.dart';
import 'driver_ride_completion_view.dart';

/// Restore server-side de "Viaje completado / Cobrar efectivo"
/// (Checkpoint D): se llega aquí desde Home cuando `getActiveRide()`
/// ya no encuentra el ride (COMPLETED no es un status activo) pero
/// `GET drivers/me/rides/pending-payments` sí encuentra un CASH
/// PENDING. Deliberadamente NO depende de ningún `DriverRideCompletion`
/// en memoria ni de estado de otra pantalla: hace su propia consulta
/// por `rideId`, igual que ya hace `DriverCashPaymentScreen`.
///
/// No lleva GPS, timers ni heartbeat: restaurar un cobro pendiente es
/// UX, no un estado operacional (Backend ya dejó al conductor
/// AVAILABLE al completar el viaje).
class DriverCompletedPaymentScreen extends ConsumerStatefulWidget {
  const DriverCompletedPaymentScreen({required this.rideId, super.key});

  final String rideId;

  @override
  ConsumerState<DriverCompletedPaymentScreen> createState() =>
      _DriverCompletedPaymentScreenState();
}

class _DriverCompletedPaymentScreenState
    extends ConsumerState<DriverCompletedPaymentScreen> {
  DriverPendingPayment? _payment;

  bool _loading = true;
  bool _notFound = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _notFound = false;
      });
    }

    try {
      final payments = await ref
          .read(driverRidesRepositoryProvider)
          .getPendingPayments();

      if (!mounted) {
        return;
      }

      DriverPendingPayment? match;

      for (final candidate in payments) {
        if (candidate.rideId == widget.rideId) {
          match = candidate;
          break;
        }
      }

      setState(() {
        _payment = match;
        _notFound = match == null;
        _loading = false;
      });
    } on DioException catch (error) {
      debugPrint(
        'DRIVER COMPLETED PAYMENT LOAD ERROR '
        'status=${error.response?.statusCode} '
        'data=${error.response?.data}',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el cobro pendiente.';
      });
    } catch (error) {
      debugPrint('DRIVER COMPLETED PAYMENT LOAD ERROR: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = 'No se pudo consultar el cobro pendiente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final payment = _payment;

    if (payment == null) {
      return Scaffold(
        backgroundColor: DriverPalette.cream,
        appBar: AppBar(
          backgroundColor: DriverPalette.cream,
          elevation: 0,
          automaticallyImplyLeading: false,
          foregroundColor: DriverPalette.greenPrimary,
          title: const Text('Viaje completado'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _error ??
                      (_notFound
                          ? 'Ya no encontramos un cobro pendiente '
                                'para este viaje.'
                          : 'No se pudo consultar el cobro pendiente.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: DriverPalette.brown),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  FilledButton(
                    onPressed: _load,
                    child: const Text('Reintentar'),
                  )
                else
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Volver al inicio'),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return DriverRideCompletionView(
      passengerFirstName: null,
      passengerPhotoUrl: null,
      finalFare: payment.finalFare,
      actualDistanceMeters: null,
      actualDurationSeconds: null,
      paymentMethod: payment.payment.method,
      paymentStatus: payment.payment.status,
      onCollectCash: () {
        context.go('/cash-payment/${payment.rideId}');
      },
    );
  }
}
