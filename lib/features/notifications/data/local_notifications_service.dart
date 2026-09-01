import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `DRIVER-PUSH-R1` (Etapa 2). Datos del canal Android para los avisos
/// de nuevas solicitudes de viaje. Se declaran acá para que `main()`
/// (que crea el canal al arrancar) y `FlnLocalNotifications` (que lo
/// referencia al mostrar) usen exactamente los mismos valores.
const String kRideOffersChannelId = 'ride_offers';
const String kRideOffersChannelName = 'Solicitudes de viaje';
const String kRideOffersChannelDescription =
    'Avisos de nuevas solicitudes de viaje entrantes';

/// ID fijo de la notificación: cada propuesta nueva REEMPLAZA el aviso
/// anterior en la barra de estado en lugar de apilarse.
const int kRideOfferNotificationId = 0;

/// Instancia de `FlutterLocalNotificationsPlugin` ya inicializada en
/// `main()` (con el canal `ride_offers` creado). `main()` sobreescribe
/// este provider vía `ProviderScope(overrides: ...)`; sin ese override
/// lanza a propósito, porque nada debería consumirlo fuera del árbol
/// real de la app.
final flutterLocalNotificationsPluginProvider =
    Provider<FlutterLocalNotificationsPlugin>((ref) {
      throw UnimplementedError(
        'flutterLocalNotificationsPluginProvider debe sobreescribirse con la '
        'instancia inicializada en main()',
      );
    });

/// Seam fino sobre `flutter_local_notifications`: permite que
/// `PushMessageHandler` se pruebe con un doble a mano (el plugin real
/// no funciona dentro de `flutter_test`).
abstract class LocalNotifications {
  /// Muestra —o reemplaza— el aviso de nueva solicitud de viaje.
  Future<void> show({required String title, required String body});
}

/// Implementación real: delega en el `FlutterLocalNotificationsPlugin`
/// ya inicializado, con ID fijo y el canal `ride_offers`.
class FlnLocalNotifications implements LocalNotifications {
  FlnLocalNotifications(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<void> show({required String title, required String body}) {
    return _plugin.show(
      id: kRideOfferNotificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          kRideOffersChannelId,
          kRideOffersChannelName,
          channelDescription: kRideOffersChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

final localNotificationsProvider = Provider<LocalNotifications>((ref) {
  return FlnLocalNotifications(
    ref.watch(flutterLocalNotificationsPluginProvider),
  );
});
