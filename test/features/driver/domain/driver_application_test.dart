import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_application.dart';

void main() {
  group('DriverApplicationStatus.fromRaw', () {
    test('mapea los 5 valores reales de Backend', () {
      expect(
        DriverApplicationStatus.fromRaw('DRAFT'),
        DriverApplicationStatus.draft,
      );
      expect(
        DriverApplicationStatus.fromRaw('PENDING_REVIEW'),
        DriverApplicationStatus.pendingReview,
      );
      expect(
        DriverApplicationStatus.fromRaw('APPROVED'),
        DriverApplicationStatus.approved,
      );
      expect(
        DriverApplicationStatus.fromRaw('REJECTED'),
        DriverApplicationStatus.rejected,
      );
      expect(
        DriverApplicationStatus.fromRaw('SUSPENDED'),
        DriverApplicationStatus.suspended,
      );
    });

    test(
      'un valor desconocido o null cae en unknown, nunca en un caso real',
      () {
        expect(
          DriverApplicationStatus.fromRaw('ALGO_NUEVO'),
          DriverApplicationStatus.unknown,
        );
        expect(
          DriverApplicationStatus.fromRaw(null),
          DriverApplicationStatus.unknown,
        );
      },
    );
  });

  group('DriverApplication.fromJson', () {
    test('parsea los campos mínimos requeridos por este checkpoint', () {
      final application = DriverApplication.fromJson({
        'id': 'profile-1',
        'userId': 'user-1',
        'firstName': 'Juan',
        'lastName': 'Torres',
        'status': 'DRAFT',
        'rejectionReason': null,
        'suspensionReason': null,
        'submittedAt': null,
        'approvedAt': null,
      });

      expect(application.id, 'profile-1');
      expect(application.userId, 'user-1');
      expect(application.firstName, 'Juan');
      expect(application.lastName, 'Torres');
      expect(application.status, DriverApplicationStatus.draft);
      expect(application.rejectionReason, isNull);
      expect(application.suspensionReason, isNull);
      expect(application.submittedAt, isNull);
      expect(application.approvedAt, isNull);
    });

    test('conserva rawStatus incluso cuando el status es desconocido', () {
      final application = DriverApplication.fromJson({
        'id': 'profile-1',
        'userId': 'user-1',
        'firstName': 'Juan',
        'lastName': 'Torres',
        'status': 'ALGO_NUEVO',
      });

      expect(application.status, DriverApplicationStatus.unknown);
      expect(application.rawStatus, 'ALGO_NUEVO');
    });

    test('parsea submittedAt/approvedAt cuando vienen presentes', () {
      final application = DriverApplication.fromJson({
        'id': 'profile-1',
        'userId': 'user-1',
        'firstName': 'Juan',
        'lastName': 'Torres',
        'status': 'APPROVED',
        'submittedAt': '2026-08-10T12:00:00.000Z',
        'approvedAt': '2026-08-11T09:30:00.000Z',
      });

      expect(
        application.submittedAt,
        DateTime.parse('2026-08-10T12:00:00.000Z'),
      );
      expect(
        application.approvedAt,
        DateTime.parse('2026-08-11T09:30:00.000Z'),
      );
    });

    test(
      'campos ausentes no lanzan: quedan vacíos/null en vez de crashear',
      () {
        final application = DriverApplication.fromJson(const {});

        expect(application.id, '');
        expect(application.userId, '');
        expect(application.firstName, '');
        expect(application.lastName, '');
        expect(application.status, DriverApplicationStatus.unknown);
        expect(application.rejectionReason, isNull);
      },
    );
  });
}
