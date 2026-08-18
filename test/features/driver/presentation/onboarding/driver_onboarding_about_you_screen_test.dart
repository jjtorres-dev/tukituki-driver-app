import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:driver/core/router/driver_onboarding_routes.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/data/driver_photo_uploader.dart';
import 'package:driver/features/driver/data/driver_profile_repository.dart';
import 'package:driver/features/driver/data/driver_storage_repository.dart';
import 'package:driver/features/driver/domain/driver_application.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_about_you_screen.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_progress.dart';

/// PNG 1x1 real y válido: la pantalla renderiza `Image.memory`/
/// `DecorationImage` con la foto elegida, así que un `Uint8List`
/// arbitrario dispara una excepción asíncrona de decodificación de
/// imagen que ensucia los tests. Bytes tomados de un PNG mínimo
/// conocido, no generados a mano.
Uint8List _validPngBytes() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    driverOnboardingPhotoPickerOverride = null;
    driverOnboardingBirthDatePickerOverride = null;
  });

  group(
    'isDriverOnboardingBirthDateAdult (pure, mismo criterio que Backend)',
    () {
      test('exactamente 18 años hoy → adulto', () {
        final today = DateTime(2026, 8, 17);
        final birthDate = DateTime(2008, 8, 17);

        expect(
          isDriverOnboardingBirthDateAdult(birthDate, today: today),
          isTrue,
        );
      });

      test('cumple 18 mañana → todavía no es adulto', () {
        final today = DateTime(2026, 8, 17);
        final birthDate = DateTime(2008, 8, 18);

        expect(
          isDriverOnboardingBirthDateAdult(birthDate, today: today),
          isFalse,
        );
      });

      test('10 años → no es adulto', () {
        final today = DateTime(2026, 8, 17);
        final birthDate = DateTime(2016, 1, 1);

        expect(
          isDriverOnboardingBirthDateAdult(birthDate, today: today),
          isFalse,
        );
      });
    },
  );

  group('DriverOnboardingAboutYouScreen', () {
    testWidgets('A. renderiza el título "Sobre ti"', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Sobre ti'), findsOneWidget);
    });

    testWidgets('B. progress marca Paso 1 completo y Paso 2 actual', (
      tester,
    ) async {
      await _pumpScreen(tester);

      final progress = tester.widget<DriverOnboardingProgress>(
        find.byType(DriverOnboardingProgress),
      );

      expect(progress.currentStep, 2);
    });

    testWidgets('C. muestra los campos correctos del Paso 2', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Nombre'), findsOneWidget);
      expect(find.text('Apellidos'), findsOneWidget);
      expect(find.text('Tipo de documento'), findsOneWidget);
      expect(find.text('Número'), findsOneWidget);
      expect(find.text('Fecha de nacimiento'), findsOneWidget);
      expect(find.text('Correo electrónico (opcional)'), findsOneWidget);
      expect(find.text('Dirección'), findsNothing);
    });

    testWidgets('D/E. el documento solo ofrece DNI y CE, nunca Pasaporte', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await tester.tap(_documentTypeField);
      await tester.pumpAndSettle();

      expect(find.text('DNI'), findsWidgets);
      expect(find.text('CE'), findsOneWidget);
      expect(find.text('Pasaporte'), findsNothing);
      expect(find.textContaining('PASSPORT'), findsNothing);
      expect(find.textContaining('FOREIGNER_CARD'), findsNothing);

      await tester.tap(find.text('DNI').last);
      await tester.pumpAndSettle();
    });

    testWidgets('F. el correo es opcional: envía sin él sin error', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await _fillValidForm(tester);
      await _selectValidBirthDate(tester);
      await _selectValidPhoto(tester);
      await _tapSubmit(tester);

      expect(profileRepository.createCalls, 1);
      expect(profileRepository.lastEmail, isNull);
    });

    testWidgets('G. nombre requerido, 2-80 caracteres', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await tester.enterText(_firstNameField, 'J');
      await tester.enterText(_lastNameField, 'Torres');
      await tester.enterText(_documentNumberField, '12345678');
      await _tapSubmit(tester);

      expect(
        find.text('Ingresa tu nombre (2 a 80 caracteres)'),
        findsOneWidget,
      );
      expect(profileRepository.createCalls, 0);
    });

    testWidgets('H. apellidos requeridos, 2-80 caracteres', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await tester.enterText(_firstNameField, 'Juan');
      await tester.enterText(_lastNameField, 'T');
      await tester.enterText(_documentNumberField, '12345678');
      await _tapSubmit(tester);

      expect(
        find.text('Ingresa tus apellidos (2 a 80 caracteres)'),
        findsOneWidget,
      );
      expect(profileRepository.createCalls, 0);
    });

    testWidgets('I. documento: regex 8-20 caracteres', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await tester.enterText(_firstNameField, 'Juan');
      await tester.enterText(_lastNameField, 'Torres');
      await tester.enterText(_documentNumberField, '123');
      await _tapSubmit(tester);

      expect(
        find.text('Ingresa un número de documento válido (8 a 20 caracteres)'),
        findsOneWidget,
      );
      expect(profileRepository.createCalls, 0);
    });

    testWidgets('J. menor de 18 años: no permite continuar', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await _fillValidForm(tester);
      await _selectValidPhoto(tester);

      final underage = DateTime.now();
      driverOnboardingBirthDatePickerOverride =
          (
            context, {
            required initialDate,
            required firstDate,
            required lastDate,
          }) async =>
              DateTime(underage.year - 10, underage.month, underage.day);

      await tester.ensureVisible(_birthDateField);
      await tester.tap(_birthDateField);
      await tester.pump();

      await _tapSubmit(tester);

      expect(find.text('Debes tener al menos 18 años.'), findsOneWidget);
      expect(profileRepository.createCalls, 0);
    });

    testWidgets('K/Q. adulto válido + foto: crea el DriverProfile (POST)', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(profileRepository.createCalls, 1);
      expect(profileRepository.lastFirstName, 'Juan');
      expect(profileRepository.lastLastName, 'Torres');
      expect(profileRepository.lastDocumentNumber, '12345678');
      expect(profileRepository.lastBirthDate, '2000-01-01');
    });

    testWidgets('L. sin foto: no llama Backend ni navega', (tester) async {
      final profileRepository = _FakeDriverProfileRepository();
      await _pumpScreen(tester, profileRepository: profileRepository);

      await _fillValidForm(tester);
      await _selectValidBirthDate(tester);
      await _tapSubmit(tester);

      expect(find.text('Agrega una foto para continuar.'), findsOneWidget);
      expect(profileRepository.createCalls, 0);
      expect(find.text('START_ROUTE'), findsNothing);
    });

    testWidgets('M. "Tomar una foto" invoca el picker con ImageSource.camera', (
      tester,
    ) async {
      ImageSource? usedSource;
      driverOnboardingPhotoPickerOverride = (source) async {
        usedSource = source;
        return DriverPickedPhoto(
          bytes: _validPngBytes(),
          contentType: 'image/jpeg',
        );
      };

      await _pumpScreen(tester);

      await tester.tap(_photoTrigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-picker-camera-option')));
      await tester.pumpAndSettle();

      expect(usedSource, ImageSource.camera);
    });

    testWidgets(
      'N. "Elegir de galería" invoca el picker con ImageSource.gallery',
      (tester) async {
        ImageSource? usedSource;
        driverOnboardingPhotoPickerOverride = (source) async {
          usedSource = source;
          return DriverPickedPhoto(
            bytes: _validPngBytes(),
            contentType: 'image/jpeg',
          );
        };

        await _pumpScreen(tester);

        await tester.tap(_photoTrigger);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('photo-picker-gallery-option')));
        await tester.pumpAndSettle();

        expect(usedSource, ImageSource.gallery);
      },
    );

    testWidgets('O. cancelar el picker (null) no rompe la pantalla', (
      tester,
    ) async {
      driverOnboardingPhotoPickerOverride = (source) async => null;

      await _pumpScreen(tester);

      await tester.tap(_photoTrigger);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo-picker-gallery-option')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Agregar foto'), findsOneWidget);
      expect(find.byKey(const Key('about-you-photo-error')), findsNothing);
    });

    testWidgets(
      'cancelar el bottom sheet (Cancelar) no rompe y no abre el picker',
      (tester) async {
        var pickerCalls = 0;
        driverOnboardingPhotoPickerOverride = (source) async {
          pickerCalls += 1;
          return null;
        };

        await _pumpScreen(tester);

        await tester.tap(_photoTrigger);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('photo-picker-cancel-button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(pickerCalls, 0);
      },
    );

    testWidgets('P. la preview aparece después de seleccionar una foto', (
      tester,
    ) async {
      await _pumpScreen(tester);

      expect(find.text('Agregar foto'), findsOneWidget);

      await _selectValidPhoto(tester);

      expect(find.text('Cambiar foto'), findsOneWidget);
    });

    testWidgets(
      'R. el POST no incluye address (la screen no la pide ni la envía)',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository();
        await _pumpScreen(tester, profileRepository: profileRepository);

        await _fillEverythingValid(tester);
        await _tapSubmit(tester);

        expect(profileRepository.createCalls, 1);
      },
    );

    testWidgets(
      'S/T. después de POST exitoso, presigna DRIVER_PROFILE_PHOTO con '
      'contentType y fileSize reales',
      (tester) async {
        final storageRepository = _FakeDriverStorageRepository();
        await _pumpScreen(tester, storageRepository: storageRepository);

        await _fillEverythingValid(tester);
        await _tapSubmit(tester);

        expect(storageRepository.presignCalls, 1);
        expect(
          storageRepository.lastPresignCategory,
          driverProfilePhotoStorageCategory,
        );
        expect(storageRepository.lastPresignContentType, 'image/jpeg');
        expect(storageRepository.lastPresignFileSize, _validPngBytes().length);
      },
    );

    testWidgets('W/X. complete se llama después del PUT y recién ahí navega', (
      tester,
    ) async {
      final storageRepository = _FakeDriverStorageRepository();
      final uploader = _FakeDriverPhotoUploader();
      await _pumpScreen(
        tester,
        storageRepository: storageRepository,
        photoUploader: uploader,
      );

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(uploader.uploadCalls, 1);
      expect(storageRepository.completeCalls, 1);
      expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
    });

    testWidgets('Y. si POST falla, no se llama presign', (tester) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(500, path: 'drivers/me'),
      );
      final storageRepository = _FakeDriverStorageRepository();
      await _pumpScreen(
        tester,
        profileRepository: profileRepository,
        storageRepository: storageRepository,
      );

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(storageRepository.presignCalls, 0);
      expect(
        find.text('No pudimos guardar tus datos. Inténtalo nuevamente.'),
        findsOneWidget,
      );
      expect(find.text('START_ROUTE'), findsNothing);
    });

    testWidgets('Z. si presign falla, no se llama al uploader (PUT)', (
      tester,
    ) async {
      final storageRepository = _FakeDriverStorageRepository(
        presignError: _dioError(400, path: 'storage/uploads/presign'),
      );
      final uploader = _FakeDriverPhotoUploader();
      await _pumpScreen(
        tester,
        storageRepository: storageRepository,
        photoUploader: uploader,
      );

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(uploader.uploadCalls, 0);
      expect(
        find.text('No pudimos subir tu foto. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });

    testWidgets('AA. si el PUT falla, no se llama complete', (tester) async {
      final storageRepository = _FakeDriverStorageRepository();
      final uploader = _FakeDriverPhotoUploader(
        error: _dioError(500, path: 'https://bucket.example.com/put'),
      );
      await _pumpScreen(
        tester,
        storageRepository: storageRepository,
        photoUploader: uploader,
      );

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(storageRepository.completeCalls, 0);
      expect(
        find.text('No pudimos subir tu foto. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });

    testWidgets('AB. si complete falla, no avanza a Paso 3', (tester) async {
      final storageRepository = _FakeDriverStorageRepository(
        completeError: _dioError(500, path: 'storage/uploads/complete'),
      );
      await _pumpScreen(tester, storageRepository: storageRepository);

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(find.text('START_ROUTE'), findsNothing);
      expect(
        find.text('No pudimos subir tu foto. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'AC. si la foto falla después de crear el DRAFT, reintentar NO repite el POST',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository();
        final uploader = _FakeDriverPhotoUploader(
          error: _dioError(500, path: 'https://bucket.example.com/put'),
        );
        await _pumpScreen(
          tester,
          profileRepository: profileRepository,
          photoUploader: uploader,
        );

        await _fillEverythingValid(tester);
        await _tapSubmit(tester);

        expect(profileRepository.createCalls, 1);
        expect(find.text('START_ROUTE'), findsNothing);

        uploader.error = null;
        await _tapSubmit(tester);

        expect(
          profileRepository.createCalls,
          1,
          reason: 'no debe repetir el POST tras el reintento',
        );
        expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
      },
    );

    testWidgets('AD. doble tap no crea dos POST concurrentes', (tester) async {
      final completer = Completer<DriverApplication>();
      final profileRepository = _FakeDriverProfileRepository(
        completer: completer,
      );
      await _pumpScreen(tester, profileRepository: profileRepository);

      await _fillEverythingValid(tester);

      await tester.ensureVisible(_submitButton);
      await tester.tap(_submitButton);
      await tester.pump();
      await tester.tap(_submitButton);
      await tester.pump();

      expect(profileRepository.createCalls, 1);

      completer.complete(
        const DriverApplication(
          id: 'profile-1',
          userId: 'user-1',
          firstName: 'Juan',
          lastName: 'Torres',
          status: DriverApplicationStatus.draft,
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('AE. los errores nunca muestran detalle técnico', (
      tester,
    ) async {
      final profileRepository = _FakeDriverProfileRepository(
        error: _dioError(409, path: 'drivers/me'),
      );
      final authRepository = _FakeAuthRepository(getDriverProfileResult: null);
      await _pumpScreen(
        tester,
        profileRepository: profileRepository,
        authRepository: authRepository,
      );

      await _fillEverythingValid(tester);
      await _tapSubmit(tester);

      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('409'), findsNothing);
      expect(find.textContaining('FOREIGNER_CARD'), findsNothing);
      expect(find.textContaining('objectKey'), findsNothing);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('Bearer'), findsNothing);
    });

    testWidgets(
      '409 en POST confirmado vía GET drivers/me: continúa sin reintentar el POST',
      (tester) async {
        final profileRepository = _FakeDriverProfileRepository(
          error: _dioError(409, path: 'drivers/me'),
        );
        final authRepository = _FakeAuthRepository(
          getDriverProfileResult: const DriverApplication(
            id: 'profile-1',
            userId: 'user-1',
            firstName: 'Juan',
            lastName: 'Torres',
            status: DriverApplicationStatus.draft,
          ),
        );
        await _pumpScreen(
          tester,
          profileRepository: profileRepository,
          authRepository: authRepository,
        );

        await _fillEverythingValid(tester);
        await _tapSubmit(tester);

        expect(authRepository.getDriverProfileCalls, 1);
        expect(find.text('VEHICLE_ROUTE'), findsOneWidget);
      },
    );

    testWidgets('el botón de volver cierra sesión y navega a Login', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository();
      await _pumpScreen(tester, authRepository: authRepository);

      await tester.tap(find.byKey(const Key('about-you-back-button')));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCalls, 1);
      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });

    testWidgets('D. tras seleccionar la fecha, el campo muestra DD/MM/YYYY', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await _selectValidBirthDate(tester);

      expect(find.text('01/01/2000'), findsOneWidget);
    });

    testWidgets(
      'B/C (DRIVER-ONBOARDING-R3.4.2): el DatePicker real (sin override) '
      'abre en español',
      (tester) async {
        await _pumpScreenWithRealLocale(tester);

        await tester.ensureVisible(_birthDateField);
        await tester.tap(_birthDateField);
        await tester.pumpAndSettle();

        expect(find.byType(DatePickerDialog), findsOneWidget);

        final locale = Localizations.localeOf(
          tester.element(find.byType(DatePickerDialog)),
        );
        expect(locale.languageCode, 'es');
      },
    );
  });

  group(
    'DriverOnboardingAboutYouScreen — modo EDIT (DRIVER-ONBOARDING-R3.7)',
    () {
      DriverApplication editProfile() {
        return const DriverApplication(
          id: 'profile-1',
          userId: 'user-1',
          firstName: 'Rocio',
          lastName: 'Alegre',
          status: DriverApplicationStatus.draft,
          documentType: IdentityDocumentType.dni,
          documentNumber: '76751234',
          birthDate: '1990-03-25',
          email: 'rocio@example.com',
          photoUrl: 'https://cdn.example.com/rocio.jpg',
        );
      }

      testWidgets('precarga los campos y la foto existente', (tester) async {
        await _pumpScreen(
          tester,
          pushedFromReviewArgs: DriverOnboardingAboutYouScreenArgs(
            profile: editProfile(),
          ),
        );

        expect(find.widgetWithText(TextFormField, 'Rocio'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Alegre'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '76751234'), findsOneWidget);
        expect(
          find.widgetWithText(TextFormField, 'rocio@example.com'),
          findsOneWidget,
        );
        expect(find.text('25/03/1990'), findsOneWidget);
        expect(
          find.byKey(const Key('about-you-existing-photo')),
          findsOneWidget,
        );
        expect(find.text('Guardar cambios'), findsOneWidget);
      });

      testWidgets('guardar sin elegir una foto nueva no muestra error: la foto '
          'existente ya satisface el requisito', (tester) async {
        final profileRepository = _FakeDriverProfileRepository();
        await _pumpScreen(
          tester,
          profileRepository: profileRepository,
          pushedFromReviewArgs: DriverOnboardingAboutYouScreenArgs(
            profile: editProfile(),
          ),
        );

        await _tapSubmit(tester);

        expect(find.byKey(const Key('about-you-photo-error')), findsNothing);
        expect(profileRepository.updateCalls, 1);
        expect(profileRepository.createCalls, 0);
      });

      testWidgets(
        'guardar cambios llama updateProfile (PATCH), nunca createProfile',
        (tester) async {
          final profileRepository = _FakeDriverProfileRepository();
          final authRepository = _FakeAuthRepository();
          await _pumpScreen(
            tester,
            profileRepository: profileRepository,
            authRepository: authRepository,
            pushedFromReviewArgs: DriverOnboardingAboutYouScreenArgs(
              profile: editProfile(),
            ),
          );

          await tester.enterText(_firstNameField, 'Rocio Actualizada');
          await _tapSubmit(tester);

          expect(profileRepository.updateCalls, 1);
          expect(profileRepository.createCalls, 0);
          expect(profileRepository.lastUpdateFirstName, 'Rocio Actualizada');
        },
      );

      testWidgets('elegir una foto nueva sube por Storage antes de terminar', (
        tester,
      ) async {
        final profileRepository = _FakeDriverProfileRepository();
        final storageRepository = _FakeDriverStorageRepository();
        final uploader = _FakeDriverPhotoUploader();
        await _pumpScreen(
          tester,
          profileRepository: profileRepository,
          storageRepository: storageRepository,
          photoUploader: uploader,
          pushedFromReviewArgs: DriverOnboardingAboutYouScreenArgs(
            profile: editProfile(),
          ),
        );

        driverOnboardingPhotoPickerOverride = (source) async =>
            DriverPickedPhoto(
              bytes: _validPngBytes(),
              contentType: 'image/jpeg',
            );

        await tester.ensureVisible(_photoTrigger);
        await tester.tap(_photoTrigger);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('photo-picker-gallery-option')));
        await tester.pumpAndSettle();

        await _tapSubmit(tester);

        expect(profileRepository.updateCalls, 1);
        expect(storageRepository.presignCalls, 1);
        expect(uploader.uploadCalls, 1);
        expect(storageRepository.completeCalls, 1);
      });

      testWidgets(
        'la flecha de volver hace pop (no cierra sesión) cuando llegó '
        'empujada desde Revisar y enviar',
        (tester) async {
          final authRepository = _FakeAuthRepository();
          await _pumpScreen(
            tester,
            authRepository: authRepository,
            pushedFromReviewArgs: DriverOnboardingAboutYouScreenArgs(
              profile: editProfile(),
            ),
          );

          await tester.tap(find.byKey(const Key('about-you-back-button')));
          await tester.pumpAndSettle();

          expect(authRepository.logoutCalls, 0);
          expect(find.text('open'), findsOneWidget);
          expect(find.text('LOGIN_ROUTE'), findsNothing);
        },
      );
    },
  );
}

Finder get _firstNameField =>
    find.byKey(const Key('about-you-first-name-field'));
Finder get _lastNameField => find.byKey(const Key('about-you-last-name-field'));
Finder get _documentTypeField =>
    find.byKey(const Key('about-you-document-type-field'));
Finder get _documentNumberField =>
    find.byKey(const Key('about-you-document-number-field'));
Finder get _birthDateField =>
    find.byKey(const Key('about-you-birth-date-field'));
Finder get _submitButton => find.byKey(const Key('about-you-submit-button'));
Finder get _photoTrigger =>
    find.byKey(const Key('about-you-photo-picker-trigger'));

Future<void> _fillValidForm(WidgetTester tester) async {
  await tester.enterText(_firstNameField, 'Juan');
  await tester.enterText(_lastNameField, 'Torres');
  await tester.enterText(_documentNumberField, '12345678');
}

Future<void> _selectValidBirthDate(WidgetTester tester) async {
  driverOnboardingBirthDatePickerOverride =
      (
        context, {
        required initialDate,
        required firstDate,
        required lastDate,
      }) async => DateTime(2000, 1, 1);

  await tester.ensureVisible(_birthDateField);
  await tester.tap(_birthDateField);
  await tester.pump();
}

Future<void> _selectValidPhoto(WidgetTester tester) async {
  driverOnboardingPhotoPickerOverride = (source) async =>
      DriverPickedPhoto(bytes: _validPngBytes(), contentType: 'image/jpeg');

  await tester.ensureVisible(_photoTrigger);
  await tester.tap(_photoTrigger);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('photo-picker-gallery-option')));
  await tester.pumpAndSettle();
}

Future<void> _fillEverythingValid(WidgetTester tester) async {
  await _selectValidPhoto(tester);
  await _fillValidForm(tester);
  await _selectValidBirthDate(tester);
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submitButton);
  await tester.tap(_submitButton);
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
  _FakeDriverProfileRepository? profileRepository,
  _FakeDriverStorageRepository? storageRepository,
  _FakeDriverPhotoUploader? photoUploader,
  DriverOnboardingAboutYouScreenArgs? pushedFromReviewArgs,
}) async {
  final router = GoRouter(
    initialLocation: pushedFromReviewArgs != null
        ? '/root'
        : '/onboarding/about-you',
    routes: [
      GoRoute(
        path: '/root',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-about-you-from-review'),
              onPressed: () => context.push(
                DriverOnboardingRoutes.aboutYou,
                extra: pushedFromReviewArgs,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding/about-you',
        builder: (context, state) => DriverOnboardingAboutYouScreen(
          args: state.extra as DriverOnboardingAboutYouScreenArgs?,
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
        path: '/onboarding/vehicle',
        builder: (context, state) =>
            const Scaffold(body: Text('VEHICLE_ROUTE')),
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
        driverProfileRepositoryProvider.overrideWithValue(
          profileRepository ?? _FakeDriverProfileRepository(),
        ),
        driverStorageRepositoryProvider.overrideWithValue(
          storageRepository ?? _FakeDriverStorageRepository(),
        ),
        driverPhotoUploaderProvider.overrideWithValue(
          photoUploader ?? _FakeDriverPhotoUploader(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  if (pushedFromReviewArgs != null) {
    await tester.tap(find.byKey(const Key('open-about-you-from-review')));
    await tester.pumpAndSettle();
  }
}

/// Mismo montaje que [_pumpScreen], pero con la localización real de
/// la app (`app.dart`) — usado exclusivamente para probar que el
/// `DatePicker` real (sin `driverOnboardingBirthDatePickerOverride`)
/// abre en español.
Future<void> _pumpScreenWithRealLocale(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/onboarding/about-you',
    routes: [
      GoRoute(
        path: '/onboarding/about-you',
        builder: (context, state) => const DriverOnboardingAboutYouScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        driverProfileRepositoryProvider.overrideWithValue(
          _FakeDriverProfileRepository(),
        ),
        driverStorageRepositoryProvider.overrideWithValue(
          _FakeDriverStorageRepository(),
        ),
        driverPhotoUploaderProvider.overrideWithValue(
          _FakeDriverPhotoUploader(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('es', 'PE'),
        supportedLocales: const [Locale('es', 'PE'), Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pump();
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.getDriverProfileResult})
    : super(Dio(), const FlutterSecureStorage());

  DriverApplication? getDriverProfileResult;
  int logoutCalls = 0;
  int getDriverProfileCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<DriverApplication?> getDriverProfile() async {
    getDriverProfileCalls += 1;

    return getDriverProfileResult;
  }

  /// La pantalla llama esto tras guardar (`_submit()`,
  /// `DRIVER-ONBOARDING-R3.7`) para decidir a dónde navegar en vez de
  /// hardcodear una ruta. `draftNoVehicle` es el siguiente paso real
  /// tras completar "Sobre ti" sin vehículo todavía.
  @override
  Future<DriverSessionState> resolveSessionState() async {
    return const DriverSessionState(
      kind: DriverSessionKind.draftNoVehicle,
      user: AuthenticatedUser(
        id: 'user-1',
        phoneE164: '+51987654321',
        roles: ['PASSENGER'],
        status: 'ACTIVE',
        isPhoneVerified: true,
      ),
    );
  }
}

class _FakeDriverProfileRepository extends DriverProfileRepository {
  _FakeDriverProfileRepository({this.error, this.completer}) : super(Dio());

  Object? error;
  Completer<DriverApplication>? completer;

  int createCalls = 0;
  String? lastFirstName;
  String? lastLastName;
  String? lastDocumentNumber;
  String? lastBirthDate;
  String? lastEmail;

  @override
  Future<DriverApplication> createProfile({
    required String firstName,
    required String lastName,
    required IdentityDocumentType documentType,
    required String documentNumber,
    required String birthDate,
    String? email,
  }) async {
    createCalls += 1;
    lastFirstName = firstName;
    lastLastName = lastName;
    lastDocumentNumber = documentNumber;
    lastBirthDate = birthDate;
    lastEmail = email;

    if (completer != null) {
      return completer!.future;
    }

    if (error case final e?) {
      throw e;
    }

    return DriverApplication(
      id: 'profile-1',
      userId: 'user-1',
      firstName: firstName,
      lastName: lastName,
      status: DriverApplicationStatus.draft,
      documentType: documentType,
      documentNumber: documentNumber,
      birthDate: birthDate,
      email: email,
    );
  }

  int updateCalls = 0;
  String? lastUpdateFirstName;
  String? lastUpdateEmail;

  @override
  Future<DriverApplication> updateProfile({
    required String firstName,
    required String lastName,
    required IdentityDocumentType documentType,
    required String documentNumber,
    required String birthDate,
    String? email,
  }) async {
    updateCalls += 1;
    lastUpdateFirstName = firstName;
    lastUpdateEmail = email;

    if (error case final e?) {
      throw e;
    }

    return DriverApplication(
      id: 'profile-1',
      userId: 'user-1',
      firstName: firstName,
      lastName: lastName,
      status: DriverApplicationStatus.draft,
      documentType: documentType,
      documentNumber: documentNumber,
      birthDate: birthDate,
      email: email,
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
      objectKey: 'drivers/profile-1/profile/abc.jpg',
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
