import 'package:flutter_test/flutter_test.dart';

import 'package:driver/features/driver/domain/driver_document.dart';

DriverDocument _document({
  String id = 'document-1',
  DriverDocumentType type = DriverDocumentType.driverLicense,
  DriverDocumentStatus status = DriverDocumentStatus.draft,
  String? fileUrl,
  String? fileObjectKey = 'drivers/profile-1/documents/license.jpg',
  String? documentNumber = 'ABC123',
  String? issuedAt = '2024-01-01',
  String? expiresAt = '2030-01-01',
  String? rejectionReason,
}) {
  return DriverDocument(
    id: id,
    driverProfileId: 'profile-1',
    type: type,
    status: status,
    fileUrl: fileUrl,
    fileObjectKey: fileObjectKey,
    documentNumber: documentNumber,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    rejectionReason: rejectionReason,
  );
}

void main() {
  group('DriverDocumentType.fromRaw', () {
    test('parsea los 3 tipos que el Paso 4 puede crear', () {
      expect(
        DriverDocumentType.fromRaw('DRIVER_LICENSE'),
        DriverDocumentType.driverLicense,
      );
      expect(DriverDocumentType.fromRaw('SOAT'), DriverDocumentType.soat);
      expect(
        DriverDocumentType.fromRaw('VEHICLE_REGISTRATION'),
        DriverDocumentType.vehicleRegistration,
      );
    });

    test('parsea los tipos legacy defensivamente', () {
      expect(
        DriverDocumentType.fromRaw('DNI_FRONT'),
        DriverDocumentType.dniFront,
      );
      expect(
        DriverDocumentType.fromRaw('DNI_BACK'),
        DriverDocumentType.dniBack,
      );
      expect(
        DriverDocumentType.fromRaw('PROFILE_PHOTO'),
        DriverDocumentType.profilePhoto,
      );
    });

    test('un valor desconocido o null → unknown', () {
      expect(
        DriverDocumentType.fromRaw('ALGO_NUEVO'),
        DriverDocumentType.unknown,
      );
      expect(DriverDocumentType.fromRaw(null), DriverDocumentType.unknown);
    });
  });

  group('DriverDocumentStatus.fromRaw', () {
    test('parsea los 4 valores reales de Backend', () {
      expect(DriverDocumentStatus.fromRaw('DRAFT'), DriverDocumentStatus.draft);
      expect(
        DriverDocumentStatus.fromRaw('PENDING_REVIEW'),
        DriverDocumentStatus.pendingReview,
      );
      expect(
        DriverDocumentStatus.fromRaw('APPROVED'),
        DriverDocumentStatus.approved,
      );
      expect(
        DriverDocumentStatus.fromRaw('REJECTED'),
        DriverDocumentStatus.rejected,
      );
    });

    test('un valor desconocido o null → unknown (nunca SUSPENDED)', () {
      expect(
        DriverDocumentStatus.fromRaw('SUSPENDED'),
        DriverDocumentStatus.unknown,
      );
      expect(DriverDocumentStatus.fromRaw(null), DriverDocumentStatus.unknown);
    });
  });

  group('DriverDocument.fromJson / hasFile', () {
    test('parsea todos los campos', () {
      final document = DriverDocument.fromJson({
        'id': 'document-1',
        'driverProfileId': 'profile-1',
        'type': 'SOAT',
        'status': 'PENDING_REVIEW',
        'fileUrl': null,
        'fileObjectKey': 'drivers/profile-1/documents/soat.jpg',
        'documentNumber': 'XYZ999',
        'issuedAt': '2024-05-01',
        'expiresAt': '2025-05-01',
        'rejectionReason': null,
      });

      expect(document.id, 'document-1');
      expect(document.type, DriverDocumentType.soat);
      expect(document.status, DriverDocumentStatus.pendingReview);
      expect(document.documentNumber, 'XYZ999');
      expect(document.issuedAt, '2024-05-01');
      expect(document.expiresAt, '2025-05-01');
      expect(document.hasFile, isTrue);
    });

    test('hasFile es true si fileUrl o fileObjectKey tienen valor', () {
      expect(
        _document(
          fileUrl: 'https://cdn.example.com/x.jpg',
          fileObjectKey: null,
        ).hasFile,
        isTrue,
      );
      expect(
        _document(fileObjectKey: 'drivers/x/documents/y.jpg').hasFile,
        isTrue,
      );
    });

    test('hasFile es false si ambos son null o vacíos', () {
      expect(_document(fileUrl: null, fileObjectKey: null).hasFile, isFalse);
      expect(_document(fileUrl: '', fileObjectKey: '').hasFile, isFalse);
    });
  });

  group('requiredDriverOnboardingDocumentTypes', () {
    test('son exactamente licencia, SOAT y tarjeta de propiedad, en orden', () {
      expect(requiredDriverOnboardingDocumentTypes, [
        DriverDocumentType.driverLicense,
        DriverDocumentType.soat,
        DriverDocumentType.vehicleRegistration,
      ]);
    });
  });

  group('isDriverDocumentComplete', () {
    final today = DateTime.utc(2026, 8, 17);

    test('document null → false', () {
      expect(isDriverDocumentComplete(null, today: today), isFalse);
    });

    test('sin archivo → false, sin importar la metadata', () {
      final document = _document(fileUrl: null, fileObjectKey: null);

      expect(isDriverDocumentComplete(document, today: today), isFalse);
    });

    test('sin documentNumber (null o vacío) → false', () {
      expect(
        isDriverDocumentComplete(_document(documentNumber: null), today: today),
        isFalse,
      );
      expect(
        isDriverDocumentComplete(_document(documentNumber: '  '), today: today),
        isFalse,
      );
    });

    test('sin issuedAt, o issuedAt no parseable → false', () {
      expect(
        isDriverDocumentComplete(_document(issuedAt: null), today: today),
        isFalse,
      );
      expect(
        isDriverDocumentComplete(
          _document(issuedAt: 'no-es-fecha'),
          today: today,
        ),
        isFalse,
      );
    });

    test('issuedAt futuro → false', () {
      final document = _document(issuedAt: '2026-08-18');

      expect(isDriverDocumentComplete(document, today: today), isFalse);
    });

    test('issuedAt igual a hoy → válido (no futuro)', () {
      final document = _document(
        issuedAt: '2026-08-17',
        expiresAt: '2030-01-01',
      );

      expect(isDriverDocumentComplete(document, today: today), isTrue);
    });

    group('DRIVER_LICENSE / SOAT exigen expiresAt', () {
      test('sin expiresAt → false', () {
        final license = _document(
          type: DriverDocumentType.driverLicense,
          expiresAt: null,
        );
        final soat = _document(type: DriverDocumentType.soat, expiresAt: null);

        expect(isDriverDocumentComplete(license, today: today), isFalse);
        expect(isDriverDocumentComplete(soat, today: today), isFalse);
      });

      test('expiresAt no parseable → false', () {
        final document = _document(
          type: DriverDocumentType.driverLicense,
          expiresAt: 'no-es-fecha',
        );

        expect(isDriverDocumentComplete(document, today: today), isFalse);
      });

      test('expiresAt anterior o igual a issuedAt → false', () {
        final before = _document(
          type: DriverDocumentType.driverLicense,
          issuedAt: '2024-01-01',
          expiresAt: '2023-12-31',
        );
        final equal = _document(
          type: DriverDocumentType.driverLicense,
          issuedAt: '2024-01-01',
          expiresAt: '2024-01-01',
        );

        expect(isDriverDocumentComplete(before, today: today), isFalse);
        expect(isDriverDocumentComplete(equal, today: today), isFalse);
      });

      test('expiresAt ya vencido (anterior a hoy) → false', () {
        final document = _document(
          type: DriverDocumentType.driverLicense,
          issuedAt: '2020-01-01',
          expiresAt: '2026-08-16',
        );

        expect(isDriverDocumentComplete(document, today: today), isFalse);
      });

      test('expiresAt igual a hoy → válido (todavía no vencido)', () {
        final document = _document(
          type: DriverDocumentType.driverLicense,
          issuedAt: '2020-01-01',
          expiresAt: '2026-08-17',
        );

        expect(isDriverDocumentComplete(document, today: today), isTrue);
      });

      test('archivo + número + fechas válidas → true', () {
        final license = _document(
          type: DriverDocumentType.driverLicense,
          issuedAt: '2024-01-01',
          expiresAt: '2030-01-01',
        );
        final soat = _document(
          type: DriverDocumentType.soat,
          issuedAt: '2024-01-01',
          expiresAt: '2030-01-01',
        );

        expect(isDriverDocumentComplete(license, today: today), isTrue);
        expect(isDriverDocumentComplete(soat, today: today), isTrue);
      });
    });

    group('VEHICLE_REGISTRATION no exige expiresAt', () {
      test('sin expiresAt, con archivo+número+issuedAt válido → true', () {
        final document = _document(
          type: DriverDocumentType.vehicleRegistration,
          expiresAt: null,
        );

        expect(isDriverDocumentComplete(document, today: today), isTrue);
      });

      test('un expiresAt presente pero irrelevante no lo invalida', () {
        final document = _document(
          type: DriverDocumentType.vehicleRegistration,
          expiresAt: '2000-01-01',
        );

        expect(isDriverDocumentComplete(document, today: today), isTrue);
      });
    });

    test('tipos legacy/unknown nunca se consideran completos', () {
      for (final type in [
        DriverDocumentType.dniFront,
        DriverDocumentType.dniBack,
        DriverDocumentType.profilePhoto,
        DriverDocumentType.unknown,
      ]) {
        final document = _document(type: type);

        expect(isDriverDocumentComplete(document, today: today), isFalse);
      }
    });
  });
}
