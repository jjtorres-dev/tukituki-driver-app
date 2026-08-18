import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:driver/core/router/driver_onboarding_routes.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/data/driver_document_repository.dart';
import 'package:driver/features/driver/data/driver_photo_uploader.dart';
import 'package:driver/features/driver/data/driver_storage_repository.dart';
import 'package:driver/features/driver/domain/driver_document.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_documents_screen.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_progress.dart';

/// PNG 1x1 real y válido — mismo criterio que en "Sobre ti"
/// (`driver_onboarding_about_you_screen_test.dart`): un `Uint8List`
/// arbitrario dispara una excepción asíncrona de decodificación al
/// renderizar `Image.memory`.
Uint8List _validPngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}

DriverPickedDocumentFile _pickedImage() {
  return DriverPickedDocumentFile(
    bytes: _validPngBytes(),
    contentType: 'image/jpeg',
  );
}

DriverPickedDocumentFile _pickedPdf({String fileName = 'licencia.pdf'}) {
  return DriverPickedDocumentFile(
    bytes: Uint8List.fromList([1, 2, 3, 4]),
    contentType: 'application/pdf',
    fileName: fileName,
  );
}

DriverDocument _completeDocument(DriverDocumentType type) {
  final needsExpiresAt =
      type == DriverDocumentType.driverLicense ||
      type == DriverDocumentType.soat;

  return DriverDocument(
    id: 'document-${type.value}',
    driverProfileId: 'profile-1',
    type: type,
    status: DriverDocumentStatus.draft,
    fileObjectKey: 'drivers/profile-1/documents/${type.value}.jpg',
    documentNumber: 'ABC123',
    issuedAt: '2024-01-01',
    expiresAt: needsExpiresAt ? '2030-01-01' : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    driverOnboardingDocumentImagePickerOverride = null;
    driverOnboardingDocumentPdfPickerOverride = null;
    driverOnboardingDocumentDatePickerOverride = null;
  });

  group('DriverOnboardingDocumentsScreen — carga inicial', () {
    testWidgets('A. muestra un loader mientras carga', (tester) async {
      final authRepository = _FakeAuthRepository(
        completer: Completer<List<DriverDocument>>(),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.byKey(const Key('documents-loading')), findsOneWidget);
    });

    testWidgets('B. error de carga muestra Reintentar y recarga al tocarlo', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        getMyDocumentsError: _dioError(500, path: 'drivers/me/documents'),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(find.byKey(const Key('documents-load-error')), findsOneWidget);
      expect(authRepository.getMyDocumentsCalls, 1);

      authRepository.getMyDocumentsError = null;
      await tester.tap(find.byKey(const Key('documents-retry-button')));
      await tester.pump();
      await tester.pump();

      expect(authRepository.getMyDocumentsCalls, 2);
      expect(find.byKey(const Key('documents-load-error')), findsNothing);
    });

    testWidgets('C. renderiza título, progreso Paso 4 y las 3 tarjetas', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('Tus documentos'), findsOneWidget);
      final progress = tester.widget<DriverOnboardingProgress>(
        find.byType(DriverOnboardingProgress),
      );
      expect(progress.currentStep, 4);

      expect(find.text('Licencia de conducir'), findsOneWidget);
      expect(find.text('SOAT'), findsOneWidget);
      expect(find.text('Tarjeta de propiedad / TIV'), findsOneWidget);
    });

    testWidgets('D. sin documentos previos, las 3 tarjetas están vacías', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('Agregar documento'), findsNWidgets(3));
    });

    testWidgets(
      'E. resume con documentos completos: cada tarjeta ya muestra el '
      'badge de completo, sin volver a mostrar "Agregar documento"',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          documents: requiredDriverOnboardingDocumentTypes
              .map(_completeDocument)
              .toList(),
        );
        await _pumpScreen(tester, authRepository: authRepository);

        expect(find.text('Agregar documento'), findsNothing);
        expect(find.text('Documento cargado'), findsNWidgets(3));
        expect(
          find.byKey(const Key('documents-continue-button')),
          findsOneWidget,
        );
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('documents-continue-button')),
        );
        expect(button.onPressed, isNotNull);
      },
    );

    testWidgets('F. resume con archivo cargado pero metadata incompleta: la '
        'tarjeta queda en edición con el formulario visible', (tester) async {
      final authRepository = _FakeAuthRepository(
        documents: [
          DriverDocument(
            id: 'document-license',
            driverProfileId: 'profile-1',
            type: DriverDocumentType.driverLicense,
            status: DriverDocumentStatus.draft,
            fileObjectKey: 'drivers/profile-1/documents/license.jpg',
          ),
        ],
      );
      await _pumpScreen(tester, authRepository: authRepository);

      expect(
        find.byKey(const Key('documents-license-number-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-license-save-button')),
        findsOneWidget,
      );
    });
  });

  group('DriverOnboardingDocumentsScreen — selector de archivo', () {
    testWidgets('G. abre el selector con las 3 opciones + cancelar', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('documents-license-add-button')));
      await tester.pumpAndSettle();

      expect(find.text('Tomar una foto'), findsOneWidget);
      expect(find.text('Elegir de galería'), findsOneWidget);
      expect(find.text('Elegir archivo PDF'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('H. "Tomar una foto" usa ImageSource.camera', (tester) async {
      ImageSource? usedSource;
      driverOnboardingDocumentImagePickerOverride = (source) async {
        usedSource = source;
        return _pickedImage();
      };

      await _pumpScreen(tester);
      await tester.tap(find.byKey(const Key('documents-license-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-picker-camera-option')));
      await tester.pumpAndSettle();

      expect(usedSource, ImageSource.camera);
    });

    testWidgets('I. "Elegir de galería" usa ImageSource.gallery', (
      tester,
    ) async {
      ImageSource? usedSource;
      driverOnboardingDocumentImagePickerOverride = (source) async {
        usedSource = source;
        return _pickedImage();
      };

      await _pumpScreen(tester);
      await tester.tap(find.byKey(const Key('documents-soat-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-picker-gallery-option')));
      await tester.pumpAndSettle();

      expect(usedSource, ImageSource.gallery);
    });

    testWidgets('J. "Elegir archivo PDF" usa el picker de PDF', (tester) async {
      var pdfPickerCalls = 0;
      driverOnboardingDocumentPdfPickerOverride = () async {
        pdfPickerCalls += 1;
        return _pickedPdf();
      };

      await _pumpScreen(tester);
      await _pickFile(tester, 'vehicle-registration', 'pdf');

      expect(pdfPickerCalls, 1);
    });

    testWidgets('K. cancelar el selector no rompe la pantalla', (tester) async {
      await _pumpScreen(tester);

      await tester.tap(find.byKey(const Key('documents-license-add-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-picker-cancel-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Agregar documento'), findsNWidgets(3));
    });

    testWidgets('L. elegir imagen muestra miniatura y campos de metadata (con '
        'vencimiento para licencia)', (tester) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();

      await _pumpScreen(tester);
      await _pickFile(tester, 'license', 'gallery');

      expect(
        find.byKey(const Key('documents-license-number-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-license-issued-at-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-license-expires-at-field')),
        findsOneWidget,
      );
    });

    testWidgets('M. elegir PDF muestra ícono + nombre de archivo, sin preview/'
        'renderizador visual', (tester) async {
      driverOnboardingDocumentPdfPickerOverride = () async =>
          _pickedPdf(fileName: 'mi-licencia.pdf');

      await _pumpScreen(tester);
      await _pickFile(tester, 'license', 'pdf');

      expect(find.text('mi-licencia.pdf'), findsOneWidget);
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    });

    testWidgets('N. tarjeta de propiedad NO muestra campo de vencimiento', (
      tester,
    ) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();

      await _pumpScreen(tester);
      await _pickFile(tester, 'vehicle-registration', 'gallery');

      expect(
        find.byKey(
          const Key('documents-vehicle-registration-expires-at-field'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
        findsOneWidget,
      );
    });
  });

  group('DriverOnboardingDocumentsScreen — validación de metadata', () {
    testWidgets('O. Guardar sin número de documento muestra error', (
      tester,
    ) async {
      final documentRepository = _FakeDriverDocumentRepository();
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();

      await _pumpScreen(tester, documentRepository: documentRepository);
      await _pickFile(tester, 'soat', 'gallery');

      await tester.ensureVisible(
        find.byKey(const Key('documents-soat-save-button')),
      );
      await tester.tap(find.byKey(const Key('documents-soat-save-button')));
      await tester.pump();

      expect(
        find.text('Ingresa un número de documento válido (3 a 50 caracteres).'),
        findsOneWidget,
      );
      expect(documentRepository.updateCalls, 0);
    });

    testWidgets('P. Guardar sin fecha de emisión muestra error', (
      tester,
    ) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();

      await _pumpScreen(tester);
      await _pickFile(tester, 'soat', 'gallery');
      await tester.enterText(
        find.byKey(const Key('documents-soat-number-field')),
        'ABC123',
      );
      await _tapSave(tester, 'soat');

      expect(find.text('Selecciona la fecha de emisión.'), findsOneWidget);
    });

    testWidgets(
      'Q. licencia/SOAT sin fecha de vencimiento muestra error; tarjeta '
      'de propiedad no la exige',
      (tester) async {
        driverOnboardingDocumentImagePickerOverride = (source) async =>
            _pickedImage();
        driverOnboardingDocumentDatePickerOverride =
            (
              context, {
              required initialDate,
              required firstDate,
              required lastDate,
              required helpText,
            }) async => DateTime(2024, 1, 1);

        await _pumpScreen(tester);
        await _pickFile(tester, 'soat', 'gallery');
        await tester.enterText(
          find.byKey(const Key('documents-soat-number-field')),
          'ABC123',
        );
        await tester.ensureVisible(
          find.byKey(const Key('documents-soat-issued-at-field')),
        );
        await tester.tap(
          find.byKey(const Key('documents-soat-issued-at-field')),
        );
        await tester.pump();

        await _tapSave(tester, 'soat');

        expect(
          find.text('Selecciona la fecha de vencimiento.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('R. fecha de emisión futura muestra error', (tester) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();

      final future = DateTime.now().add(const Duration(days: 5));
      driverOnboardingDocumentDatePickerOverride =
          (
            context, {
            required initialDate,
            required firstDate,
            required lastDate,
            required helpText,
          }) async => DateTime(future.year, future.month, future.day);

      await _pumpScreen(tester);
      await _pickFile(tester, 'vehicle-registration', 'gallery');
      await tester.enterText(
        find.byKey(const Key('documents-vehicle-registration-number-field')),
        'ABC123',
      );
      await tester.ensureVisible(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.tap(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.pump();

      await _tapSave(tester, 'vehicle-registration');

      expect(
        find.text('La fecha de emisión no puede ser futura.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'S. fecha de vencimiento anterior o igual a la de emisión muestra '
      'error',
      (tester) async {
        driverOnboardingDocumentImagePickerOverride = (source) async =>
            _pickedImage();

        var callCount = 0;
        driverOnboardingDocumentDatePickerOverride =
            (
              context, {
              required initialDate,
              required firstDate,
              required lastDate,
              required helpText,
            }) async {
              callCount += 1;
              return callCount == 1
                  ? DateTime(2024, 6, 1)
                  : DateTime(2024, 6, 1);
            };

        await _pumpScreen(tester);
        await _pickFile(tester, 'license', 'gallery');
        await tester.enterText(
          find.byKey(const Key('documents-license-number-field')),
          'ABC123',
        );

        await tester.ensureVisible(
          find.byKey(const Key('documents-license-issued-at-field')),
        );
        await tester.tap(
          find.byKey(const Key('documents-license-issued-at-field')),
        );
        await tester.pump();

        await tester.ensureVisible(
          find.byKey(const Key('documents-license-expires-at-field')),
        );
        await tester.tap(
          find.byKey(const Key('documents-license-expires-at-field')),
        );
        await tester.pump();

        await _tapSave(tester, 'license');

        expect(
          find.text(
            'La fecha de vencimiento debe ser posterior a la de emisión.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('DriverOnboardingDocumentsScreen — guardado', () {
    testWidgets(
      'T. archivo nuevo: presigna, sube, completa, refresca la lista y '
      'recién ahí hace PATCH — en ese orden',
      (tester) async {
        driverOnboardingDocumentImagePickerOverride = (source) async =>
            _pickedImage();
        driverOnboardingDocumentDatePickerOverride =
            (
              context, {
              required initialDate,
              required firstDate,
              required lastDate,
              required helpText,
            }) async => DateTime(2024, 1, 1);

        final authRepository = _FakeAuthRepository(
          documentsAfterRefetch: [
            DriverDocument(
              id: 'document-VEHICLE_REGISTRATION',
              driverProfileId: 'profile-1',
              type: DriverDocumentType.vehicleRegistration,
              status: DriverDocumentStatus.draft,
              fileObjectKey: 'drivers/profile-1/documents/tiv.jpg',
            ),
          ],
        );
        final storageRepository = _FakeDriverStorageRepository();
        final uploader = _FakeDriverPhotoUploader();
        final documentRepository = _FakeDriverDocumentRepository();

        await _pumpScreen(
          tester,
          authRepository: authRepository,
          storageRepository: storageRepository,
          photoUploader: uploader,
          documentRepository: documentRepository,
        );

        await _pickFile(tester, 'vehicle-registration', 'gallery');
        await tester.enterText(
          find.byKey(const Key('documents-vehicle-registration-number-field')),
          'plc-999',
        );
        await tester.ensureVisible(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.tap(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.pump();

        await _tapSave(tester, 'vehicle-registration');

        expect(storageRepository.presignCalls, 1);
        expect(
          storageRepository.lastPresignCategory,
          vehicleRegistrationStorageCategory,
        );
        expect(uploader.uploadCalls, 1);
        expect(storageRepository.completeCalls, 1);
        expect(authRepository.getMyDocumentsCalls, 2);
        expect(documentRepository.updateCalls, 1);
        expect(
          documentRepository.lastDocumentNumber,
          'PLC-999',
          reason: 'se normaliza a mayúsculas antes de enviarse',
        );
        expect(documentRepository.lastExpiresAt, isNull);
        expect(find.text('Documento cargado'), findsOneWidget);
      },
    );

    testWidgets('U. si el presign falla, no se llama al uploader (PUT)', (
      tester,
    ) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();
      driverOnboardingDocumentDatePickerOverride =
          (
            context, {
            required initialDate,
            required firstDate,
            required lastDate,
            required helpText,
          }) async => DateTime(2024, 1, 1);

      final storageRepository = _FakeDriverStorageRepository(
        presignError: _dioError(400, path: 'storage/uploads/presign'),
      );
      final uploader = _FakeDriverPhotoUploader();

      await _pumpScreen(
        tester,
        storageRepository: storageRepository,
        photoUploader: uploader,
      );

      await _pickFile(tester, 'vehicle-registration', 'gallery');
      await tester.enterText(
        find.byKey(const Key('documents-vehicle-registration-number-field')),
        'ABC123',
      );
      await tester.ensureVisible(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.tap(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.pump();

      await _tapSave(tester, 'vehicle-registration');

      expect(uploader.uploadCalls, 0);
      expect(
        find.text('No pudimos subir el archivo. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });

    testWidgets('U2. si el PUT falla, no se llama complete', (tester) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();
      driverOnboardingDocumentDatePickerOverride =
          (
            context, {
            required initialDate,
            required firstDate,
            required lastDate,
            required helpText,
          }) async => DateTime(2024, 1, 1);

      final storageRepository = _FakeDriverStorageRepository();
      final uploader = _FakeDriverPhotoUploader(
        error: _dioError(500, path: 'https://bucket.example.com/put'),
      );

      await _pumpScreen(
        tester,
        storageRepository: storageRepository,
        photoUploader: uploader,
      );

      await _pickFile(tester, 'vehicle-registration', 'gallery');
      await tester.enterText(
        find.byKey(const Key('documents-vehicle-registration-number-field')),
        'ABC123',
      );
      await tester.ensureVisible(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.tap(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.pump();

      await _tapSave(tester, 'vehicle-registration');

      expect(storageRepository.completeCalls, 0);
      expect(
        find.text('No pudimos subir el archivo. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'U3. si complete falla, no avanza a "Documento cargado" ni hace PATCH',
      (tester) async {
        driverOnboardingDocumentImagePickerOverride = (source) async =>
            _pickedImage();
        driverOnboardingDocumentDatePickerOverride =
            (
              context, {
              required initialDate,
              required firstDate,
              required lastDate,
              required helpText,
            }) async => DateTime(2024, 1, 1);

        final storageRepository = _FakeDriverStorageRepository(
          completeError: _dioError(500, path: 'storage/uploads/complete'),
        );
        final documentRepository = _FakeDriverDocumentRepository();

        await _pumpScreen(
          tester,
          storageRepository: storageRepository,
          documentRepository: documentRepository,
        );

        await _pickFile(tester, 'vehicle-registration', 'gallery');
        await tester.enterText(
          find.byKey(const Key('documents-vehicle-registration-number-field')),
          'ABC123',
        );
        await tester.ensureVisible(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.tap(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.pump();

        await _tapSave(tester, 'vehicle-registration');

        expect(documentRepository.updateCalls, 0);
        expect(find.text('Documento cargado'), findsNothing);
        expect(
          find.text('No pudimos subir el archivo. Inténtalo nuevamente.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'V. complete exitoso pero PATCH falla: muestra "archivo cargado, '
      'faltan datos" y conserva el archivo (no vuelve a Agregar)',
      (tester) async {
        driverOnboardingDocumentImagePickerOverride = (source) async =>
            _pickedImage();
        driverOnboardingDocumentDatePickerOverride =
            (
              context, {
              required initialDate,
              required firstDate,
              required lastDate,
              required helpText,
            }) async => DateTime(2024, 1, 1);

        final authRepository = _FakeAuthRepository(
          documentsAfterRefetch: [
            DriverDocument(
              id: 'document-VEHICLE_REGISTRATION',
              driverProfileId: 'profile-1',
              type: DriverDocumentType.vehicleRegistration,
              status: DriverDocumentStatus.draft,
              fileObjectKey: 'drivers/profile-1/documents/tiv.jpg',
            ),
          ],
        );
        final documentRepository = _FakeDriverDocumentRepository(
          error: _dioError(
            400,
            path: 'drivers/me/documents/document-VEHICLE_REGISTRATION',
          ),
        );

        await _pumpScreen(
          tester,
          authRepository: authRepository,
          documentRepository: documentRepository,
        );

        await _pickFile(tester, 'vehicle-registration', 'gallery');
        await tester.enterText(
          find.byKey(const Key('documents-vehicle-registration-number-field')),
          'ABC123',
        );
        await tester.ensureVisible(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.tap(
          find.byKey(
            const Key('documents-vehicle-registration-issued-at-field'),
          ),
        );
        await tester.pump();

        await _tapSave(tester, 'vehicle-registration');

        expect(
          find.text('El archivo se cargó, pero faltan datos por guardar.'),
          findsOneWidget,
        );
        expect(find.text('Agregar documento'), findsNWidgets(2));
        expect(
          find.byKey(const Key('documents-vehicle-registration-save-button')),
          findsOneWidget,
        );
      },
    );
  });

  group('DriverOnboardingDocumentsScreen — Continuar', () {
    testWidgets('W. deshabilitado mientras falte al menos un documento', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        documents: [
          _completeDocument(DriverDocumentType.driverLicense),
          _completeDocument(DriverDocumentType.soat),
        ],
      );
      await _pumpScreen(tester, authRepository: authRepository);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('documents-continue-button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('X. con los 3 completos, navega a la foundation de Paso 5', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository(
        documents: requiredDriverOnboardingDocumentTypes
            .map(_completeDocument)
            .toList(),
      );
      await _pumpScreen(tester, authRepository: authRepository);

      final continueButton = find.byKey(const Key('documents-continue-button'));
      await tester.ensureVisible(continueButton);
      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(find.text('SUBMIT_REVIEW_ROUTE'), findsOneWidget);
    });
  });

  group('DriverOnboardingDocumentsScreen — navegación y privacidad', () {
    testWidgets('Y. el botón de volver cierra sesión y navega a Login', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository();
      await _pumpScreen(tester, authRepository: authRepository);

      await tester.tap(find.byKey(const Key('documents-back-button')));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCalls, 1);
      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });

    testWidgets('Z. los errores nunca muestran detalle técnico', (
      tester,
    ) async {
      driverOnboardingDocumentImagePickerOverride = (source) async =>
          _pickedImage();
      driverOnboardingDocumentDatePickerOverride =
          (
            context, {
            required initialDate,
            required firstDate,
            required lastDate,
            required helpText,
          }) async => DateTime(2024, 1, 1);

      final storageRepository = _FakeDriverStorageRepository(
        presignError: _dioError(400, path: 'storage/uploads/presign'),
      );

      await _pumpScreen(tester, storageRepository: storageRepository);

      await _pickFile(tester, 'vehicle-registration', 'gallery');
      await tester.enterText(
        find.byKey(const Key('documents-vehicle-registration-number-field')),
        'ABC123',
      );
      await tester.ensureVisible(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.tap(
        find.byKey(const Key('documents-vehicle-registration-issued-at-field')),
      );
      await tester.pump();

      await _tapSave(tester, 'vehicle-registration');

      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('400'), findsNothing);
      expect(find.textContaining('objectKey'), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('Bearer'), findsNothing);
    });
  });

  group('DriverOnboardingDocumentsScreen — Editar datos '
      '(DRIVER-ONBOARDING-R3.7)', () {
    testWidgets(
      'un documento completo muestra "Editar datos" además de "Cambiar"',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          documents: [_completeDocument(DriverDocumentType.soat)],
        );
        await _pumpScreen(tester, authRepository: authRepository);

        expect(
          find.byKey(const Key('documents-soat-edit-data-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('documents-soat-change-button')),
          findsOneWidget,
        );
      },
    );

    testWidgets('"Editar datos" muestra el formulario prefilled sin volver a '
        'pedir el archivo', (tester) async {
      final authRepository = _FakeAuthRepository(
        documents: [_completeDocument(DriverDocumentType.soat)],
      );
      await _pumpScreen(tester, authRepository: authRepository);

      await tester.tap(
        find.byKey(const Key('documents-soat-edit-data-button')),
      );
      await tester.pump();

      final numberField = tester.widget<TextFormField>(
        find.byKey(const Key('documents-soat-number-field')),
      );
      expect(numberField.controller?.text, 'ABC123');
      expect(
        find.byKey(const Key('documents-soat-save-button')),
        findsOneWidget,
      );
    });

    testWidgets(
      'guardar desde "Editar datos" solo hace PATCH, nunca presign/PUT',
      (tester) async {
        final authRepository = _FakeAuthRepository(
          documents: [_completeDocument(DriverDocumentType.soat)],
        );
        final storageRepository = _FakeDriverStorageRepository();
        final uploader = _FakeDriverPhotoUploader();
        final documentRepository = _FakeDriverDocumentRepository();
        await _pumpScreen(
          tester,
          authRepository: authRepository,
          storageRepository: storageRepository,
          photoUploader: uploader,
          documentRepository: documentRepository,
        );

        await tester.tap(
          find.byKey(const Key('documents-soat-edit-data-button')),
        );
        await tester.pump();

        await tester.enterText(
          find.byKey(const Key('documents-soat-number-field')),
          'XYZ999',
        );
        await _tapSave(tester, 'soat');

        expect(storageRepository.presignCalls, 0);
        expect(uploader.uploadCalls, 0);
        expect(documentRepository.updateCalls, 1);
        expect(documentRepository.lastDocumentNumber, 'XYZ999');
        expect(
          find.byKey(const Key('documents-soat-complete-badge')),
          findsOneWidget,
        );
      },
    );

    testWidgets('la flecha de volver hace pop (no cierra sesión) cuando llegó '
        'empujada desde Revisar y enviar', (tester) async {
      final authRepository = _FakeAuthRepository();
      await _pumpScreen(
        tester,
        authRepository: authRepository,
        pushedFromReview: true,
      );

      await tester.tap(find.byKey(const Key('documents-back-button')));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCalls, 0);
      expect(find.text('open'), findsOneWidget);
      expect(find.text('LOGIN_ROUTE'), findsNothing);
    });
  });

  group('DriverOnboardingDocumentsScreen — args de corrección '
      '(DRIVER-ONBOARDING-R3.8)', () {
    testWidgets('editableDocumentTypes restringe acciones a solo el tipo '
        'observado — los otros dos quedan solo-lectura, sin '
        'Editar/Cambiar/Agregar', (tester) async {
      final documents = requiredDriverOnboardingDocumentTypes
          .map(_completeDocument)
          .toList();

      await _pumpScreen(
        tester,
        authRepository: _FakeAuthRepository(documents: documents),
        args: const DriverOnboardingDocumentsScreenArgs(
          editableDocumentTypes: {DriverDocumentType.soat},
        ),
      );

      expect(
        find.byKey(const Key('documents-soat-edit-data-button')),
        findsOneWidget,
      );

      expect(
        find.byKey(const Key('documents-license-readonly-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-vehicle-registration-readonly-badge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-license-edit-data-button')),
        findsNothing,
      );
      expect(
        find.byKey(
          const Key('documents-vehicle-registration-edit-data-button'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('documents-license-change-button')),
        findsNothing,
      );
    });

    testWidgets('sin args (o editableDocumentTypes null) mantiene el '
        'comportamiento sin restricción de R3.6/R3.7', (tester) async {
      final documents = requiredDriverOnboardingDocumentTypes
          .map(_completeDocument)
          .toList();

      await _pumpScreen(
        tester,
        authRepository: _FakeAuthRepository(documents: documents),
      );

      expect(
        find.byKey(const Key('documents-license-edit-data-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('documents-soat-edit-data-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('documents-vehicle-registration-edit-data-button'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('focusDocumentType hace scroll hasta la tarjeta observada al '
        'abrir la pantalla', (tester) async {
      final documents = requiredDriverOnboardingDocumentTypes
          .map(_completeDocument)
          .toList();

      await _pumpScreen(
        tester,
        authRepository: _FakeAuthRepository(documents: documents),
        args: const DriverOnboardingDocumentsScreenArgs(
          focusDocumentType: DriverDocumentType.vehicleRegistration,
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );

      expect(scrollable.position.pixels, greaterThan(0));
    });
  });
}

Future<void> _pickFile(WidgetTester tester, String slug, String option) async {
  final addButton = find.byKey(Key('documents-$slug-add-button'));
  await tester.ensureVisible(addButton);
  await tester.tap(addButton);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('document-picker-$option-option')));
  await tester.pumpAndSettle();
}

Future<void> _tapSave(WidgetTester tester, String slug) async {
  final button = find.byKey(Key('documents-$slug-save-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

DioException _dioError(int? statusCode, {required String path}) {
  final request = RequestOptions(path: path);

  return DioException(
    requestOptions: request,
    response: statusCode == null
        ? null
        : Response<dynamic>(requestOptions: request, statusCode: statusCode),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeAuthRepository? authRepository,
  _FakeDriverStorageRepository? storageRepository,
  _FakeDriverPhotoUploader? photoUploader,
  _FakeDriverDocumentRepository? documentRepository,
  bool pushedFromReview = false,
  DriverOnboardingDocumentsScreenArgs? args,
}) async {
  final router = GoRouter(
    initialLocation: pushedFromReview ? '/root' : '/onboarding/documents',
    routes: [
      GoRoute(
        path: '/root',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-documents-from-review'),
              onPressed: () =>
                  context.push(DriverOnboardingRoutes.documents, extra: args),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding/documents',
        builder: (context, state) => DriverOnboardingDocumentsScreen(
          args: pushedFromReview
              ? state.extra as DriverOnboardingDocumentsScreenArgs?
              : args,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/start',
        builder: (context, state) => const Scaffold(body: Text('START_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/review',
        builder: (context, state) =>
            const Scaffold(body: Text('SUBMIT_REVIEW_ROUTE')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          authRepository ?? _FakeAuthRepository(),
        ),
        driverStorageRepositoryProvider.overrideWithValue(
          storageRepository ?? _FakeDriverStorageRepository(),
        ),
        driverPhotoUploaderProvider.overrideWithValue(
          photoUploader ?? _FakeDriverPhotoUploader(),
        ),
        driverDocumentRepositoryProvider.overrideWithValue(
          documentRepository ?? _FakeDriverDocumentRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();

  if (pushedFromReview) {
    await tester.tap(find.byKey(const Key('open-documents-from-review')));
    await tester.pumpAndSettle();
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({
    List<DriverDocument>? documents,
    this.documentsAfterRefetch,
    this.getMyDocumentsError,
    this.completer,
  }) : documents = documents ?? [],
       super(Dio(), const FlutterSecureStorage());

  List<DriverDocument> documents;

  /// Simula que, tras un `complete` de Storage, el nuevo documento ya
  /// aparece en `GET drivers/me/documents` (con su `id` real, pero
  /// típicamente sin metadata todavía). `null` reutiliza [documents]
  /// también en las llamadas siguientes.
  List<DriverDocument>? documentsAfterRefetch;

  Object? getMyDocumentsError;
  Completer<List<DriverDocument>>? completer;

  int logoutCalls = 0;
  int getMyDocumentsCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<List<DriverDocument>> getMyDocuments() async {
    getMyDocumentsCalls += 1;

    if (completer != null) {
      return completer!.future;
    }

    if (getMyDocumentsError case final e?) {
      throw e;
    }

    if (getMyDocumentsCalls > 1 && documentsAfterRefetch != null) {
      return documentsAfterRefetch!;
    }

    return documents;
  }

  /// La pantalla llama esto al pulsar "Continuar" (`_continue()`,
  /// `DRIVER-ONBOARDING-R3.7`) para decidir a dónde navegar en vez de
  /// hardcodear una ruta. Devuelve `draftDocumentsComplete` si los 3
  /// documentos requeridos ya están completos, replicando el mismo
  /// criterio que `resolveDriverApplicationState` real.
  @override
  Future<DriverSessionState> resolveSessionState() async {
    final hasAllRequired = requiredDriverOnboardingDocumentTypes.every((type) {
      DriverDocument? match;

      for (final document in documents) {
        if (document.type == type) {
          match = document;
          break;
        }
      }

      return isDriverDocumentComplete(match);
    });

    return DriverSessionState(
      kind: hasAllRequired
          ? DriverSessionKind.draftDocumentsComplete
          : DriverSessionKind.draftDocumentsIncomplete,
      user: const AuthenticatedUser(
        id: 'user-1',
        phoneE164: '+51987654321',
        roles: ['PASSENGER'],
        status: 'ACTIVE',
        isPhoneVerified: true,
      ),
      documents: documents,
    );
  }
}

class _FakeDriverStorageRepository extends DriverStorageRepository {
  _FakeDriverStorageRepository({this.presignError, this.completeError})
    : super(Dio());

  Object? presignError;
  Object? completeError;

  int presignCalls = 0;
  int completeCalls = 0;
  String? lastPresignCategory;
  String? lastPresignContentType;
  int? lastPresignFileSize;

  @override
  Future<DriverPresignedUpload> presignUpload({
    required String category,
    required String contentType,
    required int fileSize,
  }) async {
    presignCalls += 1;
    lastPresignCategory = category;
    lastPresignContentType = contentType;
    lastPresignFileSize = fileSize;

    if (presignError case final e?) {
      throw e;
    }

    return const DriverPresignedUpload(
      objectKey: 'drivers/profile-1/documents/abc.jpg',
      uploadUrl: 'https://bucket.example.com/put',
      contentType: 'image/jpeg',
    );
  }

  @override
  Future<void> completeUpload({
    required String category,
    required String objectKey,
  }) async {
    completeCalls += 1;

    if (completeError case final e?) {
      throw e;
    }
  }
}

class _FakeDriverPhotoUploader extends DriverPhotoUploader {
  _FakeDriverPhotoUploader({this.error});

  Object? error;
  int uploadCalls = 0;

  @override
  Future<void> upload({
    required String uploadUrl,
    required String contentType,
    required Uint8List bytes,
  }) async {
    uploadCalls += 1;

    if (error case final e?) {
      throw e;
    }
  }
}

class _FakeDriverDocumentRepository extends DriverDocumentRepository {
  _FakeDriverDocumentRepository({this.error}) : super(Dio());

  Object? error;
  int updateCalls = 0;
  String? lastDocumentNumber;
  String? lastIssuedAt;
  String? lastExpiresAt;

  @override
  Future<DriverDocument> updateDocumentMetadata({
    required String documentId,
    required String documentNumber,
    required String issuedAt,
    String? expiresAt,
  }) async {
    updateCalls += 1;
    lastDocumentNumber = documentNumber;
    lastIssuedAt = issuedAt;
    lastExpiresAt = expiresAt;

    if (error case final e?) {
      throw e;
    }

    final type = DriverDocumentType.values.firstWhere(
      (t) => 'document-${t.value}' == documentId,
      orElse: () => DriverDocumentType.unknown,
    );

    return DriverDocument(
      id: documentId,
      driverProfileId: 'profile-1',
      type: type,
      status: DriverDocumentStatus.draft,
      fileObjectKey: 'drivers/profile-1/documents/${type.value}.jpg',
      documentNumber: documentNumber,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }
}
