import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/domain/driver_application.dart';

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
  List<String> roles = const ['PASSENGER'],
  bool isPhoneVerified = true,
}) {
  return {
    'id': 'user-1',
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

void main() {
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

    test('MVP: teléfono no verificado + DRAFT → draft', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(isPhoneVerified: false)),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draft);
    });

    test('MVP: teléfono no verificado + PENDING_REVIEW → pendingReview', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson(isPhoneVerified: false)),
        'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.pendingReview);
    });

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

    test('DRAFT → draft', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'DRAFT')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.draft);
    });

    test('REJECTED → rejected, conserva rejectionReason', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (
          200,
          _driverProfileJson(
            status: 'REJECTED',
            rejectionReason: 'Foto ilegible',
          ),
        ),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.rejected);
      expect(state.application?.rejectionReason, 'Foto ilegible');
    });

    test('PENDING_REVIEW → pendingReview', () async {
      final repository = _repositoryWith({
        'auth/me': (200, _meJson()),
        'drivers/me': (200, _driverProfileJson(status: 'PENDING_REVIEW')),
      });

      final state = await repository.resolveSessionState();

      expect(state.kind, DriverSessionKind.pendingReview);
    });

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
}
