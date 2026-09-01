import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/notifications/data/local_notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // DRIVER-PUSH-R1 (Etapa 1). Best-effort: si Firebase no puede
  // inicializar (sin conexión al arrancar, Play Services ausente,
  // etc.) la app debe seguir funcionando igual, sin push. No hay
  // firebase_options.dart: es Android-only y el plugin gradle
  // `com.google.gms.google-services` inyecta la configuración desde
  // android/app/google-services.json.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (error) {
    debugPrint('DRIVER PUSH - Firebase.initializeApp() falló: $error');
  }

  // DRIVER-PUSH-R1 (Etapa 2). Best-effort: inicializa
  // flutter_local_notifications y crea explícitamente el canal
  // `ride_offers`. Un fallo acá no impide que la app arranque —
  // simplemente no habrá aviso en foreground (el Home mantiene su
  // polling de 3s como fuente de verdad). La instancia ya inicializada
  // se expone al árbol vía `flutterLocalNotificationsPluginProvider`.
  final localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  try {
    await localNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        // El manejo real del tap (abrir la propuesta) es Etapa 3; acá
        // el tap solo trae la app al frente.
        debugPrint(
          'DRIVER PUSH - notificación tocada (payload: ${response.payload})',
        );
      },
    );

    await localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kRideOffersChannelId,
            kRideOffersChannelName,
            description: kRideOffersChannelDescription,
            importance: Importance.high,
          ),
        );
  } catch (error) {
    debugPrint(
      'DRIVER PUSH - init de flutter_local_notifications falló: $error',
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        flutterLocalNotificationsPluginProvider.overrideWithValue(
          localNotificationsPlugin,
        ),
      ],
      child: const TukiTukiDriverApp(),
    ),
  );
}
