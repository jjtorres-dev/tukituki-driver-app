import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/notifications/data/local_notifications_service.dart';
import 'package:driver/features/notifications/data/push_message_handler.dart';

class _ShowCall {
  _ShowCall(this.title, this.body);

  final String title;
  final String body;
}

class _FakeLocalNotifications implements LocalNotifications {
  final List<_ShowCall> calls = [];

  @override
  Future<void> show({required String title, required String body}) async {
    calls.add(_ShowCall(title, body));
  }
}

RemoteMessage _message({
  Map<String, dynamic> data = const {},
  String? title,
  String? body,
  bool withNotification = true,
}) {
  return RemoteMessage(
    data: data,
    notification: withNotification
        ? RemoteNotification(title: title, body: body)
        : null,
  );
}

void main() {
  late StreamController<RemoteMessage> messages;
  late _FakeLocalNotifications localNotifications;

  PushMessageHandler build() {
    final handler = PushMessageHandler(messages.stream, localNotifications);
    addTearDown(handler.dispose);
    return handler;
  }

  setUp(() {
    messages = StreamController<RemoteMessage>.broadcast();
    localNotifications = _FakeLocalNotifications();
    addTearDown(messages.close);
  });

  test(
    "route 'ride-offer' con notification real → show() una vez con ese "
    'título y cuerpo',
    () async {
      build().start();

      messages.add(
        _message(
          data: {'route': 'ride-offer'},
          title: 'Viaje a Miraflores',
          body: 'S/ 12.50 · efectivo',
        ),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.title, 'Viaje a Miraflores');
      expect(localNotifications.calls.single.body, 'S/ 12.50 · efectivo');
    },
  );

  test(
    "route 'ride-offer' sin notification → show() con los textos de "
    'fallback',
    () async {
      build().start();

      messages.add(
        _message(data: {'route': 'ride-offer'}, withNotification: false),
      );
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.title, 'Nueva solicitud de viaje');
      expect(localNotifications.calls.single.body, 'Toca para ver los detalles');
    },
  );

  test(
    "route 'ride-offer' con notification pero title/body nulos → fallback",
    () async {
      build().start();

      messages.add(_message(data: {'route': 'ride-offer'}));
      await pumpEventQueue();

      expect(localNotifications.calls, hasLength(1));
      expect(localNotifications.calls.single.title, 'Nueva solicitud de viaje');
      expect(localNotifications.calls.single.body, 'Toca para ver los detalles');
    },
  );

  test('route con otro valor → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(
      _message(data: {'route': 'chat-message'}, title: 'x', body: 'y'),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('route ausente → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(_message(data: {'offerId': 'abc'}, title: 'x', body: 'y'));
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('data vacío → show() NO llamado, sin excepción', () async {
    build().start();

    messages.add(_message(title: 'x', body: 'y'));
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('dos start() seguidos → una sola suscripción (show() una vez)', () async {
    final handler = build();

    handler.start();
    handler.start();

    messages.add(
      _message(data: {'route': 'ride-offer'}, title: 'A', body: 'B'),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, hasLength(1));
  });

  test('dispose() cancela la suscripción: un mensaje posterior no llama show()', () async {
    final handler = build();
    handler.start();

    handler.dispose();

    messages.add(
      _message(data: {'route': 'ride-offer'}, title: 'A', body: 'B'),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, isEmpty);
  });

  test('mensaje malformado (data con claves faltantes) no crashea el handler', () async {
    build().start();

    messages.add(_message(data: {'foo': 'bar'}, withNotification: false));
    messages.add(_message(withNotification: false));
    await pumpEventQueue();

    // Sigue vivo: un 'ride-offer' válido posterior se procesa igual.
    messages.add(
      _message(data: {'route': 'ride-offer'}, title: 'ok', body: 'sigue vivo'),
    );
    await pumpEventQueue();

    expect(localNotifications.calls, hasLength(1));
    expect(localNotifications.calls.single.body, 'sigue vivo');
  });
}
