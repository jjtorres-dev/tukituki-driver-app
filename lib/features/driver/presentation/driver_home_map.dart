import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/theme/driver_palette.dart';

/// Motivo por el que todavía no hay una [Position] válida que
/// representar en el mapa. Determina el fallback visual mostrado
/// en lugar del GoogleMap real.
enum DriverHomeMapFallback {
  acquiring,

  /// El conductor está OFFLINE y todavía no intentó conectarse:
  /// no hay una adquisición de GPS en curso, así que no se puede
  /// decir "Obteniendo tu ubicación...".
  offline,

  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  acquireError,
  publishError,
  unknown,
}

/// Punto de inyección mínimo para pruebas: el widget `GoogleMap` real
/// es una platform view que no funciona en `flutter test` sin Google
/// Play Services. Los tests pueden reemplazar el builder del mapa
/// real por uno de prueba, sin falsear las reglas de negocio (la
/// configuración resuelta —posición, marker, cámara— sigue siendo la
/// real calculada por este widget).
typedef DriverHomeMapBuilder =
    Widget Function(BuildContext context, DriverHomeMapResolved resolved);

@visibleForTesting
DriverHomeMapBuilder? driverHomeMapBuilderOverride;

/// Estado resuelto que este widget calculó a partir de la [Position]
/// real. Expuesto para que los tests puedan verificar coordenadas sin
/// depender del platform view nativo.
class DriverHomeMapResolved {
  const DriverHomeMapResolved({
    required this.target,
    required this.markers,
    required this.cameraRequest,
  });

  final LatLng target;
  final Set<Marker> markers;

  /// Último pedido de cámara recibido del padre, tal cual, para que
  /// los tests puedan verificar qué se le pidió a este widget sin
  /// depender de un `GoogleMapController` real.
  final DriverMapCameraRequest? cameraRequest;
}

/// Pedido declarativo de cámara: en vez de que el padre (Home)
/// guarde un `GoogleMapController` y lo mueva directamente, le pide a
/// [DriverHomeMap] que centre la cámara en `target`. El propio
/// [DriverHomeMap] decide CUÁNDO y CON QUÉ controller ejecutarlo
/// (inmediatamente si ya existe uno vivo, o en cuanto se cree si
/// todavía no existe), y es el único dueño de esa decisión.
///
/// `id` debe ser estrictamente creciente por cada pedido nuevo (p.ej.
/// un contador que el padre incrementa). Permite a [DriverHomeMap]
/// distinguir "ya apliqué este pedido" de "llegó uno nuevo" sin
/// comparar por igualdad estructural de `target`.
@immutable
class DriverMapCameraRequest {
  const DriverMapCameraRequest({
    required this.id,
    required this.target,
    this.zoom = DriverHomeMap.initialZoom,
  });

  final int id;
  final LatLng target;
  final double zoom;

  @override
  bool operator ==(Object other) =>
      other is DriverMapCameraRequest &&
      other.id == id &&
      other.target == target &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(id, target, zoom);
}

/// Área de mapa del Home: GoogleMap real centrado en la posición del
/// conductor, o un fallback elegante cuando todavía no hay una
/// [Position] válida. Nunca usa coordenadas ficticias.
///
/// El [GoogleMapController] es propiedad EXCLUSIVA del State de este
/// widget: nunca se entrega al padre. Cualquier movimiento de cámara
/// pedido desde afuera (botón de recentrado, reconexión) llega como
/// un [cameraRequest] declarativo; este widget decide con qué
/// controller —siempre el suyo, siempre vivo mientras exista— y en
/// qué momento ejecutarlo. Así se evita por diseño la clase de bug
/// "GoogleMapController usado después de dispose": nadie fuera de
/// este State puede quedarse con una referencia obsoleta.
class DriverHomeMap extends StatefulWidget {
  const DriverHomeMap({
    super.key,
    required this.position,
    required this.myLocationEnabled,
    this.fallback = DriverHomeMapFallback.acquiring,
    this.cameraRequest,
  });

  final Position? position;

  /// Habilita el punto azul nativo de Google Maps para representar
  /// al propio Driver, igual que en Passenger. Home decide este
  /// valor evaluando permiso/servicio/estado GPS vigentes; este
  /// widget nunca lo activa por sí mismo cuando `position` es null.
  final bool myLocationEnabled;

  final DriverHomeMapFallback fallback;

  /// Último pedido de centrado de cámara emitido por Home (conectar,
  /// reconectar, tap en el botón de recentrado). Null = ningún pedido
  /// pendiente todavía.
  final DriverMapCameraRequest? cameraRequest;

  static const double initialZoom = 16.5;

  @override
  State<DriverHomeMap> createState() => _DriverHomeMapState();
}

class _DriverHomeMapState extends State<DriverHomeMap> {
  GoogleMapController? _controller;

  /// `true` desde que este State empieza a destruirse. Toda ruta que
  /// pueda ejecutar código async (callbacks del plugin, Futures en
  /// vuelo) debe revisar esta bandera además de `mounted` antes de
  /// tocar `_controller`, porque `mounted` ya es `false` en cuanto
  /// arranca `dispose()`, pero un callback nativo tardío (p.ej.
  /// `onMapCreated` de una creación que ya no importa) puede llegar
  /// en ese mismo instante.
  bool _disposed = false;

  /// `id` del último [DriverMapCameraRequest] realmente aplicado
  /// (con un controller vivo). Evita repetir `animateCamera` en cada
  /// rebuild cuando el pedido no cambió, y permite detectar pedidos
  /// que llegaron ANTES de que el controller existiera (quedan
  /// pendientes hasta que `_onMapCreated` los consuma).
  int? _lastAppliedCameraRequestId;

  @override
  void didUpdateWidget(covariant DriverHomeMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    _maybeApplyCameraRequest();
  }

  @override
  void dispose() {
    _disposed = true;

    // NO se llama controller.dispose() manualmente: el propio widget
    // `GoogleMap`/su Element ya dispone la vista nativa y el
    // controller asociado al desmontarse. Llamarlo de nuevo acá es
    // un doble-dispose clásico que produce exactamente el
    // "Bad state: ... already disposed" que este checkpoint elimina.
    _controller = null;

    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    if (_disposed || !mounted) {
      // El State se desmontó mientras la vista nativa terminaba de
      // crearse (callback tardío del plugin). No guardamos ni usamos
      // este controller: no hay nadie vivo para dueño de él.
      return;
    }

    _controller = controller;

    _maybeApplyCameraRequest();
  }

  /// Aplica [widget.cameraRequest] si:
  /// - existe;
  /// - es distinto del último ya aplicado (por `id`, no por
  ///   igualdad estructural: un recenter al mismo lugar debe poder
  ///   repetirse);
  /// - ya existe un controller vivo.
  ///
  /// Si el controller todavía no existe, el pedido queda
  /// automáticamente pendiente (no se marca como aplicado) y
  /// [_onMapCreated] lo retoma en cuanto el controller nace. Cubre
  /// ambas carreras: Position/pedido antes del mapa, y mapa antes de
  /// Position/pedido.
  void _maybeApplyCameraRequest() {
    final request = widget.cameraRequest;

    if (request == null || request.id == _lastAppliedCameraRequestId) {
      return;
    }

    final controller = _controller;

    if (controller == null) {
      return;
    }

    _lastAppliedCameraRequestId = request.id;

    _animateTo(controller, request.target, request.zoom);
  }

  void _animateTo(GoogleMapController controller, LatLng target, double zoom) {
    unawaited(
      controller
          .animateCamera(CameraUpdate.newLatLngZoom(target, zoom))
          .catchError((Object error, StackTrace stackTrace) {
            // Carrera propia del plugin: el controller pudo
            // invalidarse en el lado nativo entre el chequeo de
            // arriba y la ejecución real del channel call. No es un
            // error de negocio (la Position/target siguen siendo
            // correctos); se ignora en vez de dejar una excepción
            // sin manejar.
            debugPrint('DRIVER MAP - animateCamera tardío ignorado: $error');
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;

    if (position == null) {
      return DriverHomeMapFallbackView(reason: widget.fallback);
    }

    final target = LatLng(position.latitude, position.longitude);

    /*
     * Igual que Passenger: la ubicación propia se representa con el
     * punto azul nativo de Google Maps (myLocationEnabled), NO con
     * un Marker propio. `markers` queda vacío por ahora, pero el
     * campo/infraestructura se conserva para pins reales futuros
     * (pickup del pasajero, destino), sin representar al Driver.
     */
    const markers = <Marker>{};

    final resolved = DriverHomeMapResolved(
      target: target,
      markers: markers,
      cameraRequest: widget.cameraRequest,
    );

    final testBuilder = driverHomeMapBuilderOverride;

    if (testBuilder != null) {
      return testBuilder(context, resolved);
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: target,
        zoom: DriverHomeMap.initialZoom,
      ),
      markers: markers,
      onMapCreated: _onMapCreated,
      myLocationEnabled: widget.myLocationEnabled,
      // Igual que Passenger: sin botón nativo. El recenter es un
      // botón custom coherente visualmente con la app.
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      buildingsEnabled: false,
      trafficEnabled: false,
    );
  }
}

/// Copy visual (icono + texto) para cuando no hay un mapa real que
/// mostrar. Pública (no privada del archivo) a propósito: Home la
/// reutiliza tal cual como overlay opaco sobre el `GoogleMap` ya
/// montado cuando el conductor está OFFLINE, para no duplicar el
/// mapeo icono/texto por estado en dos lugares.
class DriverHomeMapFallbackView extends StatelessWidget {
  const DriverHomeMapFallbackView({super.key, required this.reason});

  final DriverHomeMapFallback reason;

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(reason);
    final isAcquiring =
        reason == DriverHomeMapFallback.acquiring ||
        reason == DriverHomeMapFallback.unknown;

    return ColoredBox(
      color: DriverPalette.cream,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Círculo compacto: suficiente presencia visual sin
              // dominar el espacio ni empujar el texto hacia el sheet.
              SizedBox(
                width: 64,
                height: 64,
                child: isAcquiring
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 64,
                            height: 64,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: DriverPalette.amber,
                            ),
                          ),
                          Icon(
                            copy.icon,
                            size: 24,
                            color: DriverPalette.greenPrimary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ],
                      )
                    : Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DriverPalette.greenPrimary.withValues(
                            alpha: 0.08,
                          ),
                          border: Border.all(
                            color: DriverPalette.greenPrimary.withValues(
                              alpha: 0.14,
                            ),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          copy.icon,
                          size: 26,
                          color: DriverPalette.greenPrimary.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                copy.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DriverPalette.brown,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _FallbackCopy _copyFor(DriverHomeMapFallback reason) {
    switch (reason) {
      case DriverHomeMapFallback.offline:
        return const _FallbackCopy(
          Icons.power_settings_new,
          'Conéctate para activar tu ubicación',
        );
      case DriverHomeMapFallback.serviceDisabled:
        return const _FallbackCopy(
          Icons.location_disabled,
          'Activa la ubicación de tu dispositivo',
        );
      case DriverHomeMapFallback.permissionDenied:
        return const _FallbackCopy(
          Icons.location_off,
          'Permite el acceso a tu ubicación',
        );
      case DriverHomeMapFallback.permissionDeniedForever:
        return const _FallbackCopy(
          Icons.settings,
          'Habilita la ubicación desde Ajustes del dispositivo',
        );
      case DriverHomeMapFallback.acquireError:
        return const _FallbackCopy(
          Icons.gps_off,
          'No se pudo obtener tu ubicación GPS',
        );
      case DriverHomeMapFallback.publishError:
        return const _FallbackCopy(
          Icons.cloud_off,
          'No se pudo publicar tu ubicación. Reintentando...',
        );
      case DriverHomeMapFallback.acquiring:
      case DriverHomeMapFallback.unknown:
        return const _FallbackCopy(
          Icons.my_location,
          'Obteniendo tu ubicación...',
        );
    }
  }
}

class _FallbackCopy {
  const _FallbackCopy(this.icon, this.message);

  final IconData icon;
  final String message;
}
