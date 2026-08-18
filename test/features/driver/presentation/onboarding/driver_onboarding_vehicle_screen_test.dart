import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:driver/core/router/driver_onboarding_routes.dart';
import 'package:driver/features/auth/data/auth_repository.dart';
import 'package:driver/features/auth/domain/authenticated_user.dart';
import 'package:driver/features/auth/domain/driver_session_state.dart';
import 'package:driver/features/driver/data/driver_vehicle_repository.dart';
import 'package:driver/features/driver/domain/driver_vehicle.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_progress.dart';
import 'package:driver/features/driver/presentation/onboarding/driver_onboarding_vehicle_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriverOnboardingVehicleScreen', () {
    testWidgets('A. renderiza el título "Tu mototaxi"', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Tu mototaxi'), findsOneWidget);
    });

    testWidgets('B. progress marca Pasos 1-2 completos y Paso 3 actual', (
      tester,
    ) async {
      await _pumpScreen(tester);

      final progress = tester.widget<DriverOnboardingProgress>(
        find.byType(DriverOnboardingProgress),
      );

      expect(progress.currentStep, 3);
    });

    testWidgets('C. muestra los campos correctos del Paso 3', (tester) async {
      await _pumpScreen(tester);

      expect(find.text('Placa'), findsOneWidget);
      expect(find.text('Marca'), findsOneWidget);
      expect(find.text('Modelo'), findsOneWidget);
      expect(find.text('Año'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('El mototaxi es'), findsOneWidget);
      expect(find.text('Propio'), findsOneWidget);
      expect(find.text('Alquilado'), findsOneWidget);
    });

    testWidgets('D. motor no visible', (tester) async {
      await _pumpScreen(tester);

      expect(find.textContaining('motor'), findsNothing);
      expect(find.textContaining('Motor'), findsNothing);
    });

    testWidgets('E. chasis no visible', (tester) async {
      await _pumpScreen(tester);

      expect(find.textContaining('chasis'), findsNothing);
      expect(find.textContaining('Chasis'), findsNothing);
    });

    testWidgets('F. vehicleType no visible', (tester) async {
      await _pumpScreen(tester);

      expect(find.textContaining('MOTOTAXI'), findsNothing);
      expect(find.textContaining('vehicleType'), findsNothing);
    });

    testWidgets('G. la placa se envía en mayúsculas', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '1234-ab');
      await _fillRestValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.lastPlate, '1234-AB');
    });

    testWidgets('H. placa: regex 5-15 caracteres', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '12');
      await _fillRestValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(
        find.text('Ingresa una placa válida (5 a 15 caracteres)'),
        findsOneWidget,
      );
      expect(vehicleRepository.createCalls, 0);
    });

    testWidgets('I. marca: requerida 2-80 caracteres', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '1234-AB');
      await tester.enterText(_brandField, 'B');
      await tester.enterText(_modelField, 'RE 4S');
      await tester.enterText(_yearField, '2024');
      await tester.enterText(_colorField, 'Azul');
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('Ingresa la marca (2 a 80 caracteres)'), findsOneWidget);
      expect(vehicleRepository.createCalls, 0);
    });

    testWidgets('J. modelo: requerido', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '1234-AB');
      await tester.enterText(_brandField, 'Bajaj');
      await tester.enterText(_modelField, '');
      await tester.enterText(_yearField, '2024');
      await tester.enterText(_colorField, 'Azul');
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('Ingresa el modelo'), findsOneWidget);
      expect(vehicleRepository.createCalls, 0);
    });

    testWidgets('K. año < 1980 rechazado', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '1234-AB');
      await tester.enterText(_brandField, 'Bajaj');
      await tester.enterText(_modelField, 'RE 4S');
      await tester.enterText(_yearField, '1979');
      await tester.enterText(_colorField, 'Azul');
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.createCalls, 0);
      expect(find.textContaining('Ingresa un año válido'), findsOneWidget);
    });

    testWidgets('L. año > actual+1 rechazado', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      final tooFar = DateTime.now().year + 2;

      await tester.enterText(_plateField, '1234-AB');
      await tester.enterText(_brandField, 'Bajaj');
      await tester.enterText(_modelField, 'RE 4S');
      await tester.enterText(_yearField, '$tooFar');
      await tester.enterText(_colorField, 'Azul');
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.createCalls, 0);
      expect(find.textContaining('Ingresa un año válido'), findsOneWidget);
    });

    testWidgets('M. año válido aceptado', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.createCalls, 1);
      expect(vehicleRepository.lastYear, 2024);
    });

    testWidgets('N. color: requerido 2-50 caracteres', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await tester.enterText(_plateField, '1234-AB');
      await tester.enterText(_brandField, 'Bajaj');
      await tester.enterText(_modelField, 'RE 4S');
      await tester.enterText(_yearField, '2024');
      await tester.enterText(_colorField, 'A');
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('Ingresa el color (2 a 50 caracteres)'), findsOneWidget);
      expect(vehicleRepository.createCalls, 0);
    });

    testWidgets('O. ownership obligatorio: sin seleccionar, no POST', (
      tester,
    ) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _tapSubmit(tester);

      expect(
        find.text('Indica si el mototaxi es propio o alquilado.'),
        findsOneWidget,
      );
      expect(vehicleRepository.createCalls, 0);
      expect(find.text('START_ROUTE'), findsNothing);
    });

    testWidgets('P. Propio → OWNED', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.lastOwnership, VehicleOwnership.owned);
    });

    testWidgets('Q. Alquilado → RENTED', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Alquilado');
      await _tapSubmit(tester);

      expect(vehicleRepository.lastOwnership, VehicleOwnership.rented);
    });

    testWidgets('R. formulario inválido: no POST', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.createCalls, 0);
    });

    testWidgets('S/T. formulario válido: POST exacto', (tester) async {
      final vehicleRepository = _FakeDriverVehicleRepository();
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(vehicleRepository.createCalls, 1);
      expect(vehicleRepository.lastPlate, '1234-AB');
      expect(vehicleRepository.lastBrand, 'Bajaj');
      expect(vehicleRepository.lastModel, 'RE 4S');
      expect(vehicleRepository.lastYear, 2024);
      expect(vehicleRepository.lastColor, 'Azul');
      expect(vehicleRepository.lastOwnership, VehicleOwnership.owned);
    });

    testWidgets('U. doble tap: un solo POST', (tester) async {
      final completer = Completer<DriverVehicle>();
      final vehicleRepository = _FakeDriverVehicleRepository(
        completer: completer,
      );
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');

      await tester.ensureVisible(_submitButton);
      await tester.tap(_submitButton);
      await tester.pump();
      await tester.tap(_submitButton);
      await tester.pump();

      expect(vehicleRepository.createCalls, 1);

      completer.complete(_sampleVehicle());
      await tester.pumpAndSettle();
    });

    testWidgets('V. POST exitoso navega a Paso 4 (DOCUMENTS_ROUTE)', (
      tester,
    ) async {
      await _pumpScreen(tester);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
    });

    testWidgets('W. error en POST: no navega, conserva los valores', (
      tester,
    ) async {
      final vehicleRepository = _FakeDriverVehicleRepository(
        error: _dioError(500),
      );
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('START_ROUTE'), findsNothing);
      expect(
        find.text(
          'No pudimos guardar los datos de tu mototaxi. Inténtalo nuevamente.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(_plateField).controller!.text,
        '1234-AB',
      );
    });

    testWidgets('X. placa duplicada: mensaje amigable en el campo Placa', (
      tester,
    ) async {
      final vehicleRepository = _FakeDriverVehicleRepository(
        error: _dioError(409, message: 'La placa ya está registrada'),
      );
      await _pumpScreen(tester, vehicleRepository: vehicleRepository);

      await _fillAllValid(tester);
      await _selectOwnership(tester, 'Propio');
      await _tapSubmit(tester);

      expect(find.text('Esta placa ya está registrada.'), findsOneWidget);
      expect(find.text('START_ROUTE'), findsNothing);
      expect(find.textContaining('409'), findsNothing);
      expect(find.textContaining('DioException'), findsNothing);
    });

    testWidgets(
      '409 "ya tiene vehículo" confirmado vía GET: recupera y navega a Paso 4',
      (tester) async {
        final vehicleRepository = _FakeDriverVehicleRepository(
          error: _dioError(
            409,
            message: 'El conductor ya tiene un vehículo registrado',
          ),
        );
        final authRepository = _FakeAuthRepository(
          getVehicleResult: _sampleVehicle(),
        );
        await _pumpScreen(
          tester,
          vehicleRepository: vehicleRepository,
          authRepository: authRepository,
        );

        await _fillAllValid(tester);
        await _selectOwnership(tester, 'Propio');
        await _tapSubmit(tester);

        expect(authRepository.getVehicleCalls, 1);
        expect(find.text('DOCUMENTS_ROUTE'), findsOneWidget);
      },
    );

    testWidgets(
      '409 "ya tiene vehículo" sin poder confirmar: error amigable, no navega',
      (tester) async {
        final vehicleRepository = _FakeDriverVehicleRepository(
          error: _dioError(
            409,
            message: 'El conductor ya tiene un vehículo registrado',
          ),
        );
        final authRepository = _FakeAuthRepository(getVehicleResult: null);
        await _pumpScreen(
          tester,
          vehicleRepository: vehicleRepository,
          authRepository: authRepository,
        );

        await _fillAllValid(tester);
        await _selectOwnership(tester, 'Propio');
        await _tapSubmit(tester);

        expect(find.text('START_ROUTE'), findsNothing);
        expect(
          find.text(
            'No pudimos guardar los datos de tu mototaxi. Inténtalo nuevamente.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('el botón de volver cierra sesión y navega a Login', (
      tester,
    ) async {
      final authRepository = _FakeAuthRepository();
      await _pumpScreen(tester, authRepository: authRepository);

      await tester.tap(find.byKey(const Key('vehicle-back-button')));
      await tester.pumpAndSettle();

      expect(authRepository.logoutCalls, 1);
      expect(find.text('LOGIN_ROUTE'), findsOneWidget);
    });
  });

  group(
    'DriverOnboardingVehicleScreen — modo EDIT (DRIVER-ONBOARDING-R3.7)',
    () {
      DriverVehicle editVehicle() {
        return const DriverVehicle(
          id: 'vehicle-1',
          driverProfileId: 'profile-1',
          plate: 'J-2637',
          brand: 'Honda',
          model: 'Mototaxi',
          year: 2022,
          color: 'Azul',
          ownership: VehicleOwnership.owned,
          status: VehicleStatus.draft,
        );
      }

      testWidgets('precarga los campos del vehículo existente', (tester) async {
        await _pumpScreen(
          tester,
          pushedFromReviewArgs: DriverOnboardingVehicleScreenArgs(
            vehicle: editVehicle(),
          ),
        );

        expect(find.widgetWithText(TextFormField, 'J-2637'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Honda'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Mototaxi'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, '2022'), findsOneWidget);
        expect(find.widgetWithText(TextFormField, 'Azul'), findsOneWidget);
        expect(find.text('Guardar cambios'), findsOneWidget);
      });

      testWidgets(
        'guardar cambios llama updateVehicle (PATCH), nunca createVehicle',
        (tester) async {
          final vehicleRepository = _FakeDriverVehicleRepository();
          await _pumpScreen(
            tester,
            vehicleRepository: vehicleRepository,
            pushedFromReviewArgs: DriverOnboardingVehicleScreenArgs(
              vehicle: editVehicle(),
            ),
          );

          await tester.enterText(_colorField, 'Rojo');
          await tester.ensureVisible(_submitButton);
          await tester.tap(_submitButton);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 20));

          expect(vehicleRepository.updateCalls, 1);
          expect(vehicleRepository.createCalls, 0);
        },
      );

      testWidgets(
        'la flecha de volver hace pop (no cierra sesión) cuando llegó '
        'empujada desde Revisar y enviar',
        (tester) async {
          final authRepository = _FakeAuthRepository();
          await _pumpScreen(
            tester,
            authRepository: authRepository,
            pushedFromReviewArgs: DriverOnboardingVehicleScreenArgs(
              vehicle: editVehicle(),
            ),
          );

          await tester.tap(find.byKey(const Key('vehicle-back-button')));
          await tester.pumpAndSettle();

          expect(authRepository.logoutCalls, 0);
          expect(find.text('open'), findsOneWidget);
          expect(find.text('LOGIN_ROUTE'), findsNothing);
        },
      );
    },
  );
}

DriverVehicle _sampleVehicle() {
  return const DriverVehicle(
    id: 'vehicle-1',
    driverProfileId: 'profile-1',
    plate: '1234-AB',
    brand: 'Bajaj',
    model: 'RE 4S',
    year: 2024,
    color: 'Azul',
    ownership: VehicleOwnership.owned,
    status: VehicleStatus.draft,
  );
}

Finder get _plateField => find.byKey(const Key('vehicle-plate-field'));
Finder get _brandField => find.byKey(const Key('vehicle-brand-field'));
Finder get _modelField => find.byKey(const Key('vehicle-model-field'));
Finder get _yearField => find.byKey(const Key('vehicle-year-field'));
Finder get _colorField => find.byKey(const Key('vehicle-color-field'));
Finder get _submitButton => find.byKey(const Key('vehicle-submit-button'));

Future<void> _fillRestValid(WidgetTester tester) async {
  await tester.enterText(_brandField, 'Bajaj');
  await tester.enterText(_modelField, 'RE 4S');
  await tester.enterText(_yearField, '2024');
  await tester.enterText(_colorField, 'Azul');
}

Future<void> _fillAllValid(WidgetTester tester) async {
  await tester.enterText(_plateField, '1234-AB');
  await _fillRestValid(tester);
}

Future<void> _selectOwnership(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(_submitButton);
  await tester.tap(_submitButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

DioException _dioError(int? statusCode, {String? message}) {
  final request = RequestOptions(path: 'drivers/me/vehicle');

  return DioException(
    requestOptions: request,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: request,
            statusCode: statusCode,
            data: message == null ? null : {'message': message},
          ),
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  _FakeAuthRepository? authRepository,
  _FakeDriverVehicleRepository? vehicleRepository,
  DriverOnboardingVehicleScreenArgs? pushedFromReviewArgs,
}) async {
  final router = GoRouter(
    initialLocation: pushedFromReviewArgs != null
        ? '/root'
        : '/onboarding/vehicle',
    routes: [
      GoRoute(
        path: '/root',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open-vehicle-from-review'),
              onPressed: () => context.push(
                DriverOnboardingRoutes.vehicle,
                extra: pushedFromReviewArgs,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding/vehicle',
        builder: (context, state) => DriverOnboardingVehicleScreen(
          args: state.extra as DriverOnboardingVehicleScreenArgs?,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(body: Text('LOGIN_ROUTE')),
      ),
      GoRoute(
        path: '/onboarding/documents',
        builder: (context, state) =>
            const Scaffold(body: Text('DOCUMENTS_ROUTE')),
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
        driverVehicleRepositoryProvider.overrideWithValue(
          vehicleRepository ?? _FakeDriverVehicleRepository(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();

  if (pushedFromReviewArgs != null) {
    await tester.tap(find.byKey(const Key('open-vehicle-from-review')));
    await tester.pumpAndSettle();
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({this.getVehicleResult})
    : super(Dio(), const FlutterSecureStorage());

  DriverVehicle? getVehicleResult;
  int logoutCalls = 0;
  int getVehicleCalls = 0;

  @override
  Future<void> logout() async {
    logoutCalls += 1;
  }

  @override
  Future<DriverVehicle?> getVehicle() async {
    getVehicleCalls += 1;

    return getVehicleResult;
  }

  /// La pantalla llama esto tras guardar (`_submit()`,
  /// `DRIVER-ONBOARDING-R3.7`) para decidir a dónde navegar en vez de
  /// hardcodear una ruta. `draftDocumentsIncomplete` es el siguiente
  /// paso real tras completar "Tu mototaxi" sin documentos todavía.
  @override
  Future<DriverSessionState> resolveSessionState() async {
    return const DriverSessionState(
      kind: DriverSessionKind.draftDocumentsIncomplete,
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

class _FakeDriverVehicleRepository extends DriverVehicleRepository {
  _FakeDriverVehicleRepository({this.error, this.completer}) : super(Dio());

  Object? error;
  Completer<DriverVehicle>? completer;

  int createCalls = 0;
  String? lastPlate;
  String? lastBrand;
  String? lastModel;
  int? lastYear;
  String? lastColor;
  VehicleOwnership? lastOwnership;

  @override
  Future<DriverVehicle> createVehicle({
    required String plate,
    required String brand,
    required String model,
    required int year,
    required String color,
    required VehicleOwnership ownership,
  }) async {
    createCalls += 1;
    lastPlate = plate;
    lastBrand = brand;
    lastModel = model;
    lastYear = year;
    lastColor = color;
    lastOwnership = ownership;

    if (completer != null) {
      return completer!.future;
    }

    if (error case final e?) {
      throw e;
    }

    return DriverVehicle(
      id: 'vehicle-1',
      driverProfileId: 'profile-1',
      plate: plate,
      brand: brand,
      model: model,
      year: year,
      color: color,
      ownership: ownership,
      status: VehicleStatus.draft,
    );
  }

  int updateCalls = 0;
  String? lastUpdatePlate;

  @override
  Future<DriverVehicle> updateVehicle({
    String? plate,
    String? brand,
    String? model,
    int? year,
    String? color,
    VehicleOwnership? ownership,
  }) async {
    updateCalls += 1;
    lastUpdatePlate = plate;

    if (error case final e?) {
      throw e;
    }

    return DriverVehicle(
      id: 'vehicle-1',
      driverProfileId: 'profile-1',
      plate: plate ?? '',
      brand: brand ?? '',
      model: model ?? '',
      year: year ?? 0,
      color: color ?? '',
      ownership: ownership ?? VehicleOwnership.owned,
      status: VehicleStatus.draft,
    );
  }
}
