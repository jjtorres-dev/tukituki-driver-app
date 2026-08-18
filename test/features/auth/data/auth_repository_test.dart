import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/core/storage/secure_storage.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';

/// Adapter con guion (`script`): cada test define, por path, qué
/// responder. Sin red real ni paquetes de mocking adicionales, igual
/// que el resto del repo (`_FixedResponseAdapter` en
/// `driver_offers_repository_test.dart`). También registra qué
/// paths fueron efectivamente solicitados, para poder afirmar que
/// una llamada NO ocurrió (p.ej. `drivers/me` sin teléfono
/// verificado).
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.responses);

  final Map<String, (int, Object?)> responses;
  final List<String> requestedPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);

    final scripted = responses[options.path];

    if (scripted == null) {
      throw StateError('Sin respuesta configurada para ${options.path}');
    }

    final (statusCode, data) = scripted;

    return ResponseBody.fromString(
      data == null ? '' : jsonEncode(data),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthRepository _repositoryWith(Map<String, (int, Object?)> responses) {
  final dio = Dio()..httpClientAdapter = _ScriptedAdapter(responses);
  return AuthRepository(dio, const FlutterSecureStorage());
}

Map<String, dynamic> _meJson({
  String id = 'user-1',
  List<String> roles = const ['PASSENGER'],
  bool isPhoneVerified = true,
}) {
  return {
    'id': id,
    'phoneE164': '+51987654321',
    'roles': roles,
    'status': 'ACTIVE',
    'isPhoneVerified': isPhoneVerified,
    'createdAt': '2026-08-10T12:00:00.000Z',
  };
}

Map<String, dynamic> _driverProfileJson({
  String status = 'DRAFT',
  String? rejectionReason,
  String? suspensionReason,
}) {
  return {
    'id': 'profile-1',
    'userId': 'user-1',
    'firstName': 'Juan',
    'lastName': 'Torres',
    'documentType': 'DNI',
    'documentNumber': '12345678',
    'birthDate': '1995-06-15',
    'address': null,
    'email': null,
    'photoUrl': null,
    'ratingAverage': '0.00',
    'ratingCount': 0,
    'status': status,
    'rejectionReason': rejectionReason,
    'submittedAt': null,
    'approvedAt': null,
    'approvedByUserId': null,
    'suspensionReason': suspensionReason,
    'suspendedAt': null,
    'suspendedByUserId': null,
    'createdAt': '2026-08-10T12:00:00.000Z',
    'updatedAt': '2026-08-10T12:00:00.000Z',
  };
}

Map<String, dynamic> _driverDocumentJson({
  required String type,
  String status = 'DRAFT',
  bool withFile = true,
  String? documentNumber = 'ABC123',
  String? issuedAt = '2024-01-01',
  String? expiresAt,
}) {
  return {
    'id': 'document-$type',
    'driverProfileId': 'profile-1',
    'type': type,
    'status': status,
    'fileUrl': null,
    'fileObjectKey': withFile ? 'drivers/profile-1/documents/$type.jpg' : null,
    'documentNumber': documentNumber,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'rejectionReason': null,
  };
}

List<Map<String, dynamic>> _allCompleteDocumentsJson() {
  return [
    _driverDocumentJson(type: 'DRIVER_LICENSE', expiresAt: '2030-01-01'),
    _driverDocumentJson(type: 'SOAT', expiresAt: '2030-01-01'),
    _driverDocumentJson(type: 'VEHICLE_REGISTRATION'),
  ];
}

Map<String, dynamic> _driverVehicleJson({String status = 'DRAFT'}) {
  return {
    'id': 'vehicle-1',
    'driverProfileId': 'profile-1',
    'plate': '1234-AB',
    'brand': 'Bajaj',
    'model': 'RE 4S',
    'year': 2024,
    'color': 'Azul',
    'engineNumber': null,
    'chassisNumber': null,
    'ownership': 'OWNED',
    'vehicleType': 'MOTOTAXI',
    'status': status,
    'rejectionReason': null,
    'createdAt': '2026-08-10T12:00:00.000Z',
    'updatedAt': '2026-08-10T12:00:00.000Z',
  };
}

void main() {
  late Map<String, String> secureStorageData;

  setUp(() {
    secureStorageData = {};
    FlutterSecureStoragePlatform.instance = TestFlutterSecureStoragePlatform(
      secureStorageData,
    );
  });

  group('AuthRepository.registerPassenger', () {
    test('envía phoneE164 y password a auth/register/passenger', () async {
      final repository = _repositoryWith({
        'auth/register/passenger': (
          201,
          {
            'user': {
              'id': 'user-1',
              'phoneE164': '+51987654321',
              'roles': ['PASSENGER'],
              'status': 'ACTIVE',
              'isPhoneVerified': false,
              'createdAt': '2026-08-10T12:00:00.000Z',
            },
          },
        ),
      });

      await repository.registerPassenger(
        phoneE164: '+51987654321',
        password: 'Password123',
      );
      // No lanza: suficiente para confirmar que el 201 con body se
      // trata como éxito.
    });

    test('propaga 409 (teléfono ya registrado) sin envolverlo', () async {
      final repository = _repositoryWith({
        'auth/register/passenger': (409, {'message': 'Ya existe'}),
      });

      await expectLater(
        repository.registerPassenger(
          phoneE164: '+51987654321',
          password: 'Password123',
        ),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('AuthRepository.getMe', () {
    test('parsea roles, isPhoneVerified, status y phoneE164', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(roles: ['PASSENGER', 'DRIVER'])),
      });

      final user = await repository.getMe();

      expect(user.id, 'user-1');
      expect(user.phoneE164, '+51987654321');
      expect(user.roles, ['PASSENGER', 'DRIVER']);
      expect(user.status, 'ACTIVE');
      expect(user.isPhoneVerified, isTrue);
      expect(user.isDriver, isTrue);
      expect(user.isPassenger, isTrue);
    });
  });

  group('AuthRepository.getDriverProfile', () {
    test('404 se traduce a null (NO_PROFILE, no un error)', () async {
      final repository = _repositoryWith({
        'drivers/me': (404, {'message': 'No existe'}),
      });

      final application = await repository.getDriverProfile();

      expect(application, isNull);
    });

    test('200 parsea DriverApplication', () async {
      final repository = _repositoryWith({
        'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
      });

      final application = await repository.getDriverProfile();

      expect(application, isNotNull);
      expect(application!.id, 'profile-1');
      expect(application.userId, 'user-1');
      expect(application.status, DriverApplicationStatus.pendingReview);
    });

    test(
      'un error distinto de 404 se relanza sin convertirse en null',
      () async {
        final repository = _repositoryWith({
          'drivers/me': (500, {'message': 'boom'}),
        });

        await expectLater(
          repository.getDriverProfile(),
          throwsA(isA<DioException>()),
        );
      },
    );
  });

  group('AuthRepository.getVehicle', () {
    test('404 se traduce a null (sin vehículo, no un error)', () async {
      final repository = _repositoryWith({
        'drivers/me/vehicle': (404, {'message': 'No existe'}),
      });

      final vehicle = await repository.getVehicle();

      expect(vehicle, isNull);
    });

    test('200 parsea DriverVehicle', () async {
      final repository = _repositoryWith({
        'drivers/me/vehicle': (200, _driverVehicleJson()),
      });

      final vehicle = await repository.getVehicle();

      expect(vehicle, isNotNull);
      expect(vehicle!.id, 'vehicle-1');
      expect(vehicle.plate, '1234-AB');
      expect(vehicle.ownership, VehicleOwnership.owned);
    });

    test(
      'un error distinto de 404 se relanza sin convertirse en null',
      () async {
        final repository = _repositoryWith({
          'drivers/me/vehicle': (500, {'message': 'boom'}),
        });

        await expectLater(
          repository.getVehicle(),
          throwsA(isA<DioException>()),
        );
      },
    );
  });

  group('AuthRepository.getMyDocuments', () {
    test('200 con lista vacía → []', () async {
      final repository = _repositoryWith({
        'drivers/me/documents': (200, <Map<String, dynamic>>[]),
      });

      final documents = await repository.getMyDocuments();

      expect(documents, isEmpty);
    });

    test('200 parsea cada DriverDocument de la lista', () async {
      final repository = _repositoryWith({
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });

      final documents = await repository.getMyDocuments();

      expect(documents, hasLength(3));
      expect(documents.map((d) => d.id), contains('document-DRIVER_LICENSE'));
    });

    test('un error se relanza sin envolverlo (nunca 404 aquí)', () async {
      final repository = _repositoryWith({
        'drivers/me/documents': (500, {'message': 'boom'}),
      });

      await expectLater(
        repository.getMyDocuments(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('AuthRepository.resolveSessionState', () {
    test(
      'MVP (DRIVER-ONBOARDING-R3.3): teléfono no verificado SÍ llama a '
      'drivers/me (OTP diferido, no bloquea el onboarding) — 404 → noProfile',
      () async {
        final adapter = _ScriptedAdapter({
          'auth/me': (200, _meJson(isPhoneVerified: false)),
          'drivers/me': (404, null),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = AuthRepository(dio, const FlutterSecureStorage());

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.noProfile);
        expect(adapter.requestedPaths, ['auth/me', 'drivers/me']);
      },
    );

    test(
      'MVP: teléfono no verificado + DRAFT sin vehículo → draftNoVehicle',
      () async {
        final repository = _repositoryWith({
          'auth/me': (200, _meJson(isPhoneVerified: false)),
          'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
          'drivers/me/vehicle': (404, null),
        });

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.draftNoVehicle);
      },
    );

    test(
      'MVP: teléfono no verificado + PENDING_REVIEW → pendingReview',
      () async {
        final repository = _repositoryWith({
          'auth/me': (200, _meJson(isPhoneVerified: false)),
          'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
        });

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.pendingReview);
      },
    );

    test(
      'MVP: teléfono no verificado + APPROVED + rol DRIVER → approved',
      () async {
        final repository = _repositoryWith({
          'auth/me': (
            200,
            _meJson(roles: ['PASSENGER', 'DRIVER'], isPhoneVerified: false),
          ),
          'drivers/me': (200, _driverProfileJson(status: 'APPROVED')),
        });

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.approved);
      },
    );

    test('verificado + drivers/me 404 → noProfile', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (404, null),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.noProfile);
    });

    test('DRAFT + vehicle 404 → draftNoVehicle, SÍ consulta vehicle', () async {
      final adapter = _ScriptedAdapter({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (404, null),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = AuthRepository(dio, const FlutterSecureStorage());

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draftNoVehicle);
      expect(
        adapter.requestedPaths,
        containsAll(['auth/me', 'drivers/me', 'drivers/me/vehicle']),
      );
    });

    test('DRAFT + vehicle 200 + documentos vacíos → draftDocumentsIncomplete, '
        'SÍ consulta drivers/me/documents', () async {
      final adapter = _ScriptedAdapter({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, <Map<String, dynamic>>[]),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = AuthRepository(dio, const FlutterSecureStorage());

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draftDocumentsIncomplete);
      expect(state.vehicle?.plate, '1234-AB');
      expect(
        adapter.requestedPaths,
        containsAll([
          'auth/me',
          'drivers/me',
          'drivers/me/vehicle',
          'drivers/me/documents',
        ]),
      );
    });

    test('DRAFT + vehicle 200 + los 3 documentos requeridos completos → '
        'draftDocumentsComplete', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draftDocumentsComplete);
      expect(state.documents, hasLength(3));
    });

    test('REJECTED → correctionsRequired, carga vehicle/documents y '
        'marca contexto de reenvío (DRIVER-ONBOARDING-R3.8)', () async {
      final adapter = _ScriptedAdapter({
        'auth/me': (200, _meJson()),
        'drivers/me': (
          200,
          _driverProfileJson(
            status: 'REJECTED',
            rejectionReason: 'Foto ilegible',
          ),
        ),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final repository = AuthRepository(dio, const FlutterSecureStorage());

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.correctionsRequired);
      expect(state.application?.rejectionReason, 'Foto ilegible');
      expect(state.vehicle?.plate, '1234-AB');
      expect(state.documents, hasLength(3));
      expect(
        adapter.requestedPaths,
        containsAll([
          'auth/me',
          'drivers/me',
          'drivers/me/vehicle',
          'drivers/me/documents',
        ]),
      );
      expect(
        secureStorageData[StorageKeys.driverResubmissionContext('user-1')],
        'true',
      );
    });

    test('DRAFT ya corregido (sin observaciones) pero con contexto de '
        'reenvío local activo → sigue correctionsRequired hasta el '
        'reenvío exitoso (DRIVER-ONBOARDING-R3.8, Backend no conserva '
        'historial de rechazos)', () async {
      secureStorageData[StorageKeys.driverResubmissionContext('user-1')] =
          'true';

      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.correctionsRequired);
    });

    test(
      'DRAFT sin observaciones y sin contexto de reenvío local → '
      'draftDocumentsComplete (flujo normal, nunca tocado por R3.8)',
      () async {
        final repository = _repositoryWith({
          'auth/me': (200, _meJson()),
          'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
          'drivers/me/vehicle': (200, _driverVehicleJson()),
          'drivers/me/documents': (200, _allCompleteDocumentsJson()),
        });

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.draftDocumentsComplete);
      },
    );

    test(
      'PENDING_REVIEW → pendingReview, NO consulta drivers/me/vehicle',
      () async {
        final adapter = _ScriptedAdapter({
          'auth/me': (200, _meJson()),
          'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
        });
        final dio = Dio()..httpClientAdapter = adapter;
        final repository = AuthRepository(dio, const FlutterSecureStorage());

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.pendingReview);
        expect(adapter.requestedPaths, ['auth/me', 'drivers/me']);
      },
    );

    test('SUSPENDED → suspended, conserva suspensionReason', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (
          200,
          _driverProfileJson(
            status: 'SUSPENDED',
            suspensionReason: 'Reincidencia de cancelaciones',
          ),
        ),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.suspended);
      expect(
        state.application?.suspensionReason,
        'Reincidencia de cancelaciones',
      );
    });

    test('APPROVED + rol DRIVER → approved', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(roles: ['PASSENGER', 'DRIVER'])),
        'drivers/me': (200, _driverProfileJson(status: 'APPROVED')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.approved);
    });

    test(
      'APPROVED sin rol DRIVER → approvedRoleMismatch (nunca Home en silencio)',
      () async {
        final repository = _repositoryWith({
          'auth/me': (200, _meJson(roles: ['PASSENGER'])),
          'drivers/me': (200, _driverProfileJson(status: 'APPROVED')),
        });

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.approvedRoleMismatch);
      },
    );

    test('status desconocido → unknownApplicationStatus', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'ALGO_NUEVO')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.unknownApplicationStatus);
    });
  });

  group('AuthRepository resubmission context — scoped por cuenta '
      '(DRIVER-ONBOARDING-R3.8B)', () {
    test('markResubmissionContext()/hasResubmissionContext() requieren '
        'userId y usan una key scoped por cuenta', () async {
      final repository = _repositoryWith({});

      expect(
        await repository.hasResubmissionContext(userId: 'user-1'),
        isFalse,
      );

      await repository.markResubmissionContext(userId: 'user-1');

      expect(await repository.hasResubmissionContext(userId: 'user-1'), isTrue);
      expect(
        secureStorageData[StorageKeys.driverResubmissionContext('user-1')],
        'true',
      );
    });

    test(
      'clearResubmissionContext() borra el marcador de esa cuenta',
      () async {
        final repository = _repositoryWith({});

        await repository.markResubmissionContext(userId: 'user-1');
        expect(
          await repository.hasResubmissionContext(userId: 'user-1'),
          isTrue,
        );

        await repository.clearResubmissionContext(userId: 'user-1');

        expect(
          await repository.hasResubmissionContext(userId: 'user-1'),
          isFalse,
        );
        expect(
          secureStorageData.containsKey(
            StorageKeys.driverResubmissionContext('user-1'),
          ),
          isFalse,
        );
      },
    );

    test('C. un marcador de la cuenta A NUNCA es visible para la cuenta B '
        '— nunca es un booleano global', () async {
      final repository = _repositoryWith({});

      await repository.markResubmissionContext(userId: 'user-A');

      expect(await repository.hasResubmissionContext(userId: 'user-A'), isTrue);
      expect(
        await repository.hasResubmissionContext(userId: 'user-B'),
        isFalse,
      );
    });

    test('B. clearSession() (logout) NUNCA borra el marcador — cerrar '
        'sesión termina la sesión, no el ciclo administrativo de la '
        'solicitud (hallazgo físico pre-review, R3.8B)', () async {
      final repository = _repositoryWith({});

      await repository.markResubmissionContext(userId: 'user-1');
      expect(await repository.hasResubmissionContext(userId: 'user-1'), isTrue);

      await repository.clearSession();

      expect(await repository.hasResubmissionContext(userId: 'user-1'), isTrue);
    });

    test('B/D. logout + login de la MISMA cuenta con el perfil ya '
        'corregido a DRAFT preserva el contexto de reenvío vía '
        'resolveSessionState()', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(id: 'user-1')),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });

      await repository.markResubmissionContext(userId: 'user-1');
      await repository.clearSession();

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.correctionsRequired);
    });

    test(
      'E. todo corregido pero aún sin reenviar, logout + login misma '
      'cuenta → sigue en modo reenvío, nunca "Enviar solicitud" inicial',
      () async {
        final repository = _repositoryWith({
          'auth/me': (200, _meJson(id: 'user-1')),
          'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
          'drivers/me/vehicle': (200, _driverVehicleJson(status: 'DRAFT')),
          'drivers/me/documents': (200, _allCompleteDocumentsJson()),
        });

        // Simula: REJECTED detectado en un login anterior (marca el
        // contexto), el conductor corrige todo (perfil/vehicle/
        // documentos ya vuelven a DRAFT/sin observaciones) y cierra
        // sesión ANTES de reenviar.
        await repository.markResubmissionContext(userId: 'user-1');
        await repository.clearSession();

        final state = await repository.resolveSessionState();

        expect(state.kind, DriverSessionKind.correctionsRequired);
      },
    );

    test('I. cuenta B, DRAFT normal que nunca fue rechazada, jamás hereda '
        'el marcador de la cuenta A', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(id: 'user-B')),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
        'drivers/me/vehicle': (200, _driverVehicleJson()),
        'drivers/me/documents': (200, _allCompleteDocumentsJson()),
      });

      await repository.markResubmissionContext(userId: 'user-A');

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draftDocumentsComplete);
    });

    test('F. PENDING_REVIEW limpia el marcador de forma defensiva (refuerza '
        'la limpieza explícita del submit, por si nunca se ejecutó)', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(id: 'user-1')),
        'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
      });

      await repository.markResubmissionContext(userId: 'user-1');

      await repository.resolveSessionState();

      expect(
        await repository.hasResubmissionContext(userId: 'user-1'),
        isFalse,
      );
    });

    test('14. APPROVED limpia cualquier marcador residual de esa cuenta '
        '(estado terminal, ya no hay ciclo de corrección posible)', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(id: 'user-1', roles: ['PASSENGER', 'DRIVER'])),
        'drivers/me': (200, _driverProfileJson(status: 'APPROVED')),
      });

      await repository.markResubmissionContext(userId: 'user-1');

      await repository.resolveSessionState();

      expect(
        await repository.hasResubmissionContext(userId: 'user-1'),
        isFalse,
      );
    });

    test('14. SUSPENDED limpia cualquier marcador residual de esa cuenta '
        '(estado terminal)', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(id: 'user-1')),
        'drivers/me': (200, _driverProfileJson(status: 'SUSPENDED')),
      });

      await repository.markResubmissionContext(userId: 'user-1');

      await repository.resolveSessionState();

      expect(
        await repository.hasResubmissionContext(userId: 'user-1'),
        isFalse,
      );
    });

    test('A. el marcador sobrevive sin ninguna interacción adicional — '
        'no depende de estado en memoria (simula reinicio de la app: una '
        'nueva instancia de AuthRepository sobre el mismo storage)', () async {
      final first = _repositoryWith({});
      await first.markResubmissionContext(userId: 'user-1');

      final second = _repositoryWith({});

      expect(await second.hasResubmissionContext(userId: 'user-1'), isTrue);
    });
  });
}
