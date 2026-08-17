import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_photo_uploader.dart';
import '../../data/driver_profile_repository.dart';
import '../../data/driver_storage_repository.dart';
import '../../domain/driver_application.dart';
import 'driver_onboarding_progress.dart';

/// Foto ya leída en memoria, lista para preview local y para subir.
class DriverPickedPhoto {
  const DriverPickedPhoto({required this.bytes, required this.contentType});

  final Uint8List bytes;
  final String contentType;
}

/// Formatos que Backend acepta para `DRIVER_PROFILE_PHOTO`
/// (`IMAGE_MIME_TYPES` en `storage-category.policy.ts`) — nunca PDF.
const List<String> driverOnboardingAllowedPhotoContentTypes = [
  'image/jpeg',
  'image/png',
  'image/webp',
];

const Map<String, String> _extensionContentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// La foto seleccionada no está en un formato que Backend acepta
/// para esta categoría.
class DriverPhotoUnsupportedFormatException implements Exception {
  const DriverPhotoUnsupportedFormatException();
}

typedef DriverPhotoPicker =
    Future<DriverPickedPhoto?> Function(ImageSource source);

/// Punto de inyección mínimo para pruebas: permite reemplazar la
/// selección real de imagen sin acoplar esta pantalla a
/// `image_picker` dentro de los tests ni agregar paquetes nuevos
/// (mismo criterio que `driverHomeGpsFetcherOverride` en
/// `driver_home_screen.dart`).
@visibleForTesting
DriverPhotoPicker? driverOnboardingPhotoPickerOverride;

Future<DriverPickedPhoto?> pickDriverOnboardingPhoto(ImageSource source) {
  final override = driverOnboardingPhotoPickerOverride;

  if (override != null) {
    return override(source);
  }

  return _pickPhotoFromDevice(source);
}

Future<DriverPickedPhoto?> _pickPhotoFromDevice(ImageSource source) async {
  final picker = ImagePicker();

  final xFile = await picker.pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1600,
  );

  if (xFile == null) {
    // El usuario canceló cámara/galería: no es un error.
    return null;
  }

  final bytes = await xFile.readAsBytes();
  final contentType = xFile.mimeType ?? _guessContentType(xFile.path);

  if (contentType == null ||
      !driverOnboardingAllowedPhotoContentTypes.contains(contentType)) {
    throw const DriverPhotoUnsupportedFormatException();
  }

  return DriverPickedPhoto(bytes: bytes, contentType: contentType);
}

String? _guessContentType(String path) {
  final dotIndex = path.lastIndexOf('.');

  if (dotIndex == -1 || dotIndex == path.length - 1) {
    return null;
  }

  final extension = path.substring(dotIndex + 1).toLowerCase();

  return _extensionContentTypes[extension];
}

typedef DriverBirthDatePicker =
    Future<DateTime?> Function(
      BuildContext context, {
      required DateTime initialDate,
      required DateTime firstDate,
      required DateTime lastDate,
    });

/// Mismo criterio de inyección para pruebas que
/// [driverOnboardingPhotoPickerOverride]: evita depender del
/// calendario nativo de Flutter dentro de los tests.
@visibleForTesting
DriverBirthDatePicker? driverOnboardingBirthDatePickerOverride;

Future<DateTime?> _pickDriverOnboardingBirthDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final override = driverOnboardingBirthDatePickerOverride;

  if (override != null) {
    return override(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: 'Fecha de nacimiento',
  );
}

/// Mismo criterio de edad mínima que `DriversService.assertAdult` en
/// Backend (años completos, sin redondear "casi 18" hacia arriba) —
/// solo replicado aquí como ayuda de UX; Backend sigue siendo la
/// fuente de verdad final.
bool isDriverOnboardingBirthDateAdult(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();

  var age = now.year - birthDate.year;

  final birthdayNotYetOccurred =
      now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day);

  if (birthdayNotYetOccurred) {
    age -= 1;
  }

  return age >= 18;
}

String formatDriverOnboardingIsoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');

  return '$year-$month-$day';
}

String _formatDisplayDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');

  return '$day/$month/$year';
}

/// Excepción interna: la creación del `DriverProfile` falló (o un
/// 409 no pudo confirmarse como ya-resuelto vía `GET drivers/me`).
/// Nunca se expone fuera de esta pantalla.
class _DriverProfileCreationFailedException implements Exception {
  const _DriverProfileCreationFailedException(this.message);

  final String message;
}

/// Paso 2 del onboarding de Driver: "Sobre ti".
///
/// Solo llega aquí `DriverSessionKind.noProfile` (ver
/// `driver_onboarding_routes.dart`): un `DriverProfile` ya existente
/// significa que este paso ya se completó, porque sus campos de
/// texto son obligatorios para crearlo.
///
/// Orden transaccional exigido por el contrato real de Backend
/// (`DRIVER-ONBOARDING-R3.4A`): `POST drivers/me` (crea el DRAFT)
/// SIEMPRE antes de `storage/uploads/presign` — Storage exige que el
/// `DriverProfile` ya exista para poder construir el `objectKey`
/// (`drivers/<driverProfileId>/profile/...`). Si la foto falla
/// después de crear el DRAFT, un reintento nunca repite el `POST`.
class DriverOnboardingAboutYouScreen extends ConsumerStatefulWidget {
  const DriverOnboardingAboutYouScreen({super.key});

  @override
  ConsumerState<DriverOnboardingAboutYouScreen> createState() =>
      _DriverOnboardingAboutYouScreenState();
}

class _DriverOnboardingAboutYouScreenState
    extends ConsumerState<DriverOnboardingAboutYouScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _documentNumberController = TextEditingController();
  final _emailController = TextEditingController();

  IdentityDocumentType _documentType = IdentityDocumentType.dni;
  DateTime? _birthDate;
  DriverPickedPhoto? _photo;

  bool _submitting = false;
  bool _pickingPhoto = false;
  String? _photoError;
  String? _birthDateError;

  /// El perfil ya se creó en esta sesión (POST exitoso, o confirmado
  /// vía `GET drivers/me` tras un 409). Evita repetir el `POST` en
  /// un reintento de la foto.
  bool _profileCreated = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _documentNumberController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  DateTime get _maxAdultBirthDate {
    final today = DateTime.now();

    return DateTime(today.year - 18, today.month, today.day);
  }

  Future<void> _pickBirthDate() async {
    if (_submitting) {
      return;
    }

    final maxDate = _maxAdultBirthDate;

    final picked = await _pickDriverOnboardingBirthDate(
      context,
      initialDate: _birthDate ?? maxDate,
      firstDate: DateTime(maxDate.year - 82),
      lastDate: maxDate,
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      _birthDate = picked;
      _birthDateError = null;
    });
  }

  Future<void> _openPhotoPicker() async {
    if (_pickingPhoto || _submitting) {
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => const _PhotoSourceSheet(),
    );

    if (source == null || !mounted) {
      return;
    }

    setState(() {
      _pickingPhoto = true;
    });

    try {
      final photo = await pickDriverOnboardingPhoto(source);

      if (!mounted) {
        return;
      }

      if (photo != null) {
        setState(() {
          _photo = photo;
          _photoError = null;
        });
      }
    } on DriverPhotoUnsupportedFormatException {
      if (!mounted) {
        return;
      }

      setState(() {
        _photoError = 'Selecciona una foto en formato JPG, PNG o WEBP.';
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }

      setState(() {
        _photoError =
            'No pudimos acceder a la cámara o galería. Revisa los permisos.';
      });
    } catch (error) {
      debugPrint('Error seleccionando foto Driver: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _photoError = 'No pudimos seleccionar la foto. Intenta nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _pickingPhoto = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final formValid = _formKey.currentState?.validate() ?? false;
    final birthDate = _birthDate;
    final photo = _photo;

    final birthDateValid =
        birthDate != null && isDriverOnboardingBirthDateAdult(birthDate);

    setState(() {
      _birthDateError = birthDate == null
          ? 'Selecciona tu fecha de nacimiento.'
          : (birthDateValid ? null : 'Debes tener al menos 18 años.');
      _photoError = photo == null ? 'Agrega una foto para continuar.' : null;
    });

    if (!formValid || !birthDateValid || photo == null) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
    });

    final authRepository = ref.read(authRepositoryProvider);
    final profileRepository = ref.read(driverProfileRepositoryProvider);
    final storageRepository = ref.read(driverStorageRepositoryProvider);
    final uploader = ref.read(driverPhotoUploaderProvider);

    try {
      if (!_profileCreated) {
        await _createProfile(authRepository, profileRepository, birthDate);
      }

      final presigned = await storageRepository.presignUpload(
        category: driverProfilePhotoStorageCategory,
        contentType: photo.contentType,
        fileSize: photo.bytes.length,
      );

      await uploader.upload(
        uploadUrl: presigned.uploadUrl,
        contentType: presigned.contentType,
        bytes: photo.bytes,
      );

      await storageRepository.completeUpload(
        category: driverProfilePhotoStorageCategory,
        objectKey: presigned.objectKey,
      );

      if (!mounted) {
        return;
      }

      context.go(DriverOnboardingRoutes.start);
    } on _DriverProfileCreationFailedException catch (error) {
      if (!mounted) {
        return;
      }

      _showError(error.message);
    } on DioException catch (_) {
      if (!mounted) {
        return;
      }

      _showError('No pudimos subir tu foto. Inténtalo nuevamente.');
    } catch (error) {
      debugPrint('Error inesperado completando Sobre ti: $error');

      if (!mounted) {
        return;
      }

      _showError('No pudimos completar tu solicitud. Inténtalo nuevamente.');
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  /// `POST drivers/me`. Un 409 no se asume como "ya resuelto" en
  /// silencio: se confirma con `GET drivers/me` antes de continuar.
  Future<void> _createProfile(
    AuthRepository authRepository,
    DriverProfileRepository profileRepository,
    DateTime birthDate,
  ) async {
    try {
      await profileRepository.createProfile(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        documentType: _documentType,
        documentNumber: _documentNumberController.text.trim().toUpperCase(),
        birthDate: formatDriverOnboardingIsoDate(birthDate),
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim().toLowerCase(),
      );

      _profileCreated = true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) {
        try {
          final existing = await authRepository.getDriverProfile();

          if (existing != null) {
            _profileCreated = true;
            return;
          }
        } on DioException {
          // No se pudo confirmar: cae al error genérico de abajo.
        }
      }

      throw const _DriverProfileCreationFailedException(
        'No pudimos guardar tus datos. Inténtalo nuevamente.',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exitToLogin() async {
    if (_submitting) {
      return;
    }

    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.logout();
    } catch (error) {
      debugPrint('Error cerrando sesión desde Sobre ti: $error');
    }

    if (!mounted) {
      return;
    }

    context.go(DriverOnboardingRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.cream,
      appBar: AppBar(
        backgroundColor: DriverPalette.cream,
        elevation: 0,
        leading: IconButton(
          key: const Key('about-you-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _submitting ? null : _exitToLogin,
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DriverOnboardingProgress(currentStep: 2),
                const SizedBox(height: 24),
                const Text(
                  'Sobre ti',
                  style: TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Cuéntanos un poco sobre ti para continuar con tu '
                  'solicitud de conductor.',
                  style: TextStyle(
                    color: DriverPalette.brown,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: _PhotoPicker(
                    photo: _photo,
                    enabled: !_submitting && !_pickingPhoto,
                    onTap: _openPhotoPicker,
                  ),
                ),
                if (_photoError != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _photoError!,
                      key: const Key('about-you-photo-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: DriverPalette.coral,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                TextFormField(
                  key: const Key('about-you-first-name-field'),
                  controller: _firstNameController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(label: 'Nombre'),
                  validator: _firstNameValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('about-you-last-name-field'),
                  controller: _lastNameController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.next,
                  decoration: _decoration(label: 'Apellidos'),
                  validator: _lastNameValidator,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<IdentityDocumentType>(
                        key: const Key('about-you-document-type-field'),
                        initialValue: _documentType,
                        decoration: _decoration(label: 'Tipo de documento'),
                        items: const [
                          DropdownMenuItem(
                            value: IdentityDocumentType.dni,
                            child: Text('DNI'),
                          ),
                          DropdownMenuItem(
                            value: IdentityDocumentType.foreignerCard,
                            child: Text('CE'),
                          ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() {
                                    _documentType = value;
                                  });
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        key: const Key('about-you-document-number-field'),
                        controller: _documentNumberController,
                        enabled: !_submitting,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _decoration(label: 'Número'),
                        validator: _documentNumberValidator,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                InkWell(
                  key: const Key('about-you-birth-date-field'),
                  onTap: _submitting ? null : _pickBirthDate,
                  borderRadius: BorderRadius.circular(16),
                  child: InputDecorator(
                    decoration: _decoration(
                      label: 'Fecha de nacimiento',
                      errorText: _birthDateError,
                    ),
                    child: Text(
                      _birthDate == null
                          ? 'Selecciona una fecha'
                          : _formatDisplayDate(_birthDate!),
                      style: TextStyle(
                        color: _birthDate == null
                            ? const Color(0xFF7C8A79)
                            : DriverPalette.greenPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('about-you-email-field'),
                  controller: _emailController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _decoration(
                    label: 'Correo electrónico (opcional)',
                  ),
                  validator: _emailValidator,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    key: const Key('about-you-submit-button'),
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: DriverPalette.greenPrimary,
                      foregroundColor: DriverPalette.cream,
                      disabledBackgroundColor: DriverPalette.greenPrimary
                          .withValues(alpha: 0.7),
                      disabledForegroundColor: DriverPalette.cream,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                      elevation: 0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _submitting
                          ? const Row(
                              key: ValueKey('about-you-loading'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: DriverPalette.cream,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text(
                                  'Guardando...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Continuar',
                              key: ValueKey('about-you-ready'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _firstNameValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.length < 2 || text.length > 80) {
      return 'Ingresa tu nombre (2 a 80 caracteres)';
    }

    return null;
  }

  String? _lastNameValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.length < 2 || text.length > 80) {
      return 'Ingresa tus apellidos (2 a 80 caracteres)';
    }

    return null;
  }

  String? _documentNumberValidator(String? value) {
    final text = value?.trim().toUpperCase() ?? '';

    if (!RegExp(r'^[A-Z0-9-]{8,20}$').hasMatch(text)) {
      return 'Ingresa un número de documento válido (8 a 20 caracteres)';
    }

    return null;
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
      return 'Ingresa un correo válido';
    }

    return null;
  }

  InputDecoration _decoration({required String label, String? errorText}) {
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return InputDecoration(
      labelText: label,
      errorText: errorText,
      labelStyle: const TextStyle(
        color: Color(0xFF7C8A79),
        fontWeight: FontWeight.w600,
      ),
      floatingLabelStyle: const TextStyle(
        color: DriverPalette.greenAvailable,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFFFBF7EA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      enabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE7E0CB)),
      ),
      disabledBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: Color(0xFFE7E0CB)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.greenAvailable, width: 1.8),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.orangeDeep),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: DriverPalette.orangeDeep, width: 1.8),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photo,
    required this.enabled,
    required this.onTap,
  });

  final DriverPickedPhoto? photo;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('about-you-photo-picker-trigger'),
      onTap: enabled ? onTap : null,
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: DriverPalette.greenPrimary, width: 2),
              image: photo != null
                  ? DecorationImage(
                      image: MemoryImage(photo!.bytes),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photo == null
                ? const Icon(
                    Icons.add_a_photo_outlined,
                    color: DriverPalette.greenPrimary,
                    size: 30,
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            photo == null ? 'Agregar foto' : 'Cambiar foto',
            style: const TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Text(
            'Foto clara de tu rostro',
            style: TextStyle(
              color: Color(0xFF7C8A79),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: DriverPalette.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Agregar foto',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DriverPalette.greenPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _PhotoSourceOption(
              key: const Key('photo-picker-camera-option'),
              icon: Icons.photo_camera_outlined,
              label: 'Tomar una foto',
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
            _PhotoSourceOption(
              key: const Key('photo-picker-gallery-option'),
              icon: Icons.photo_library_outlined,
              label: 'Elegir de galería',
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('photo-picker-cancel-button'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: DriverPalette.orangeDeep,
              ),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceOption extends StatelessWidget {
  const _PhotoSourceOption({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFBF7EA),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: DriverPalette.greenAvailable),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  color: DriverPalette.greenPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
