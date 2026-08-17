import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/auth/domain/authenticated_user.dart';

void main() {
  group('AuthenticatedUser.fromJson', () {
    test('parsea roles, isPhoneVerified, status y phoneE164', () {
      final user = AuthenticatedUser.fromJson({
        'id': 'user-1',
        'phoneE164': '+51987654321',
        'roles': ['PASSENGER', 'DRIVER'],
        'status': 'ACTIVE',
        'isPhoneVerified': true,
      });

      expect(user.id, 'user-1');
      expect(user.phoneE164, '+51987654321');
      expect(user.roles, ['PASSENGER', 'DRIVER']);
      expect(user.status, 'ACTIVE');
      expect(user.isPhoneVerified, isTrue);
    });

    test('roles ausente o no-lista se convierte en lista vacía', () {
      final user = AuthenticatedUser.fromJson({
        'id': 'user-1',
        'phoneE164': '+51987654321',
        'status': 'ACTIVE',
        'isPhoneVerified': false,
      });

      expect(user.roles, isEmpty);
      expect(user.isDriver, isFalse);
      expect(user.isPassenger, isFalse);
    });

    test('isPhoneVerified solo es true si el JSON trae exactamente true', () {
      final user = AuthenticatedUser.fromJson({
        'id': 'user-1',
        'phoneE164': '+51987654321',
        'roles': const ['PASSENGER'],
        'status': 'ACTIVE',
        'isPhoneVerified': 'true',
      });

      expect(user.isPhoneVerified, isFalse);
    });

    test('isDriver/isPassenger reflejan roles', () {
      final driverOnly = AuthenticatedUser.fromJson({
        'id': 'user-1',
        'phoneE164': '+51987654321',
        'roles': const ['DRIVER'],
        'status': 'ACTIVE',
        'isPhoneVerified': true,
      });

      expect(driverOnly.isDriver, isTrue);
      expect(driverOnly.isPassenger, isFalse);
    });
  });
}
