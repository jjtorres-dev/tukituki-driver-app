import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/router/driver_onboarding_routes.dart';
import '../../../../core/theme/driver_palette.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/driver_document_repository.dart';
import '../../data/driver_photo_uploader.dart';
import '../../data/driver_storage_repository.dart';
import '../../domain/driver_document.dart';
import 'driver_onboarding_about_you_screen.dart'
    show
        driverOnboardingAllowedPhotoContentTypes,
        formatDriverOnboardingIsoDate;
import 'driver_onboarding_progress.dart';

/// Archivo ya leído en memoria (foto o PDF), listo para preview local
/// (solo imágenes, ver [isPdf]) y para subir.
class DriverPickedDocumentFile {
  const DriverPickedDocumentFile({
    required this.bytes,
    required this.contentType,
    this.fileName,
  });

  final Uint8List bytes;
  final String contentType;
  final String? fileName;

  bool get isPdf => contentType == 'application/pdf';
}

const Map<String, String> _imageExtensionContentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
};

/// El archivo seleccionado no está en un formato que Backend acepta
/// para documentos (`DOCUMENT_MIME_TYPES` en `storage-category.
/// policy.ts`: imágenes JPG/PNG/WEBP + PDF).
class DriverDocumentUnsupportedFormatException implements Exception {
  const DriverDocumentUnsupportedFormatException();
}

/// El selector de PDF devolvió un archivo sin bytes disponibles
/// (defensivo: no debería ocurrir con `withData: true`).
class DriverDocumentFileUnavailableException implements Exception {
  const DriverDocumentFileUnavailableException();
}

typedef DriverDocumentImagePicker =
    Future<DriverPickedDocumentFile?> Function(ImageSource source);

/// Punto de inyección mínimo para pruebas, mismo criterio que
/// `driverOnboardingPhotoPickerOverride` en "Sobre ti": evita acoplar
/// esta pantalla a `image_picker` dentro de los tests.
@visibleForTesting
DriverDocumentImagePicker? driverOnboardingDocumentImagePickerOverride;

Future<DriverPickedDocumentFile?> pickDriverOnboardingDocumentImage(
  ImageSource source,
) {
  final override = driverOnboardingDocumentImagePickerOverride;

  if (override != null) {
    return override(source);
  }

  return _pickDocumentImageFromDevice(source);
}

Future<DriverPickedDocumentFile?> _pickDocumentImageFromDevice(
  ImageSource source,
) async {
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
  final contentType = xFile.mimeType ?? _guessImageContentType(xFile.path);

  if (contentType == null ||
      !driverOnboardingAllowedPhotoContentTypes.contains(contentType)) {
    throw const DriverDocumentUnsupportedFormatException();
  }

  return DriverPickedDocumentFile(bytes: bytes, contentType: contentType);
}

String? _guessImageContentType(String path) {
  final dotIndex = path.lastIndexOf('.');

  if (dotIndex == -1 || dotIndex == path.length - 1) {
    return null;
  }

  final extension = path.substring(dotIndex + 1).toLowerCase();

  return _imageExtensionContentTypes[extension];
}

typedef DriverDocumentPdfPicker = Future<DriverPickedDocumentFile?> Function();

/// Mismo criterio de inyección que
/// [driverOnboardingDocumentImagePickerOverride]: evita acoplar los
/// tests a `file_picker`.
@visibleForTesting
DriverDocumentPdfPicker? driverOnboardingDocumentPdfPickerOverride;

Future<DriverPickedDocumentFile?> pickDriverOnboardingDocumentPdf() {
  final override = driverOnboardingDocumentPdfPickerOverride;

  if (override != null) {
    return override();
  }

  return _pickDocumentPdfFromDevice();
}

Future<DriverPickedDocumentFile?> _pickDocumentPdfFromDevice() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );

  if (file == null) {
    // El usuario canceló el selector de archivos: no es un error.
    return null;
  }

  final Uint8List bytes;

  try {
    bytes = await file.readAsBytes();
  } catch (_) {
    throw const DriverDocumentFileUnavailableException();
  }

  return DriverPickedDocumentFile(
    bytes: bytes,
    contentType: 'application/pdf',
    fileName: file.name,
  );
}

typedef DriverDocumentDatePicker =
    Future<DateTime?> Function(
      BuildContext context, {
      required DateTime initialDate,
      required DateTime firstDate,
      required DateTime lastDate,
      required String helpText,
    });

/// Mismo criterio de inyección que
/// `driverOnboardingBirthDatePickerOverride` en "Sobre ti": evita
/// depender del calendario nativo dentro de los tests.
@visibleForTesting
DriverDocumentDatePicker? driverOnboardingDocumentDatePickerOverride;

Future<DateTime?> _pickDriverOnboardingDocumentDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  required String helpText,
}) {
  final override = driverOnboardingDocumentDatePickerOverride;

  if (override != null) {
    return override(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
    );
  }

  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
  );
}

String _formatDisplayDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');

  return '$day/$month/$year';
}

DateTime? _parseIsoDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }

  final parts = value.split('-');

  if (parts.length != 3) {
    return null;
  }

  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);

  if (year == null || month == null || day == null) {
    return null;
  }

  return DateTime.utc(year, month, day);
}

String _slugForType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return 'license';
    case DriverDocumentType.soat:
      return 'soat';
    case DriverDocumentType.vehicleRegistration:
      return 'vehicle-registration';
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return 'unknown';
  }
}

String _titleForType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return 'Licencia de conducir';
    case DriverDocumentType.soat:
      return 'SOAT';
    case DriverDocumentType.vehicleRegistration:
      return 'Tarjeta de propiedad / TIV';
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return '';
  }
}

String _descriptionForType(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driverLicense:
      return 'Licencia de conducir vigente.';
    case DriverDocumentType.soat:
      return 'Certificado SOAT vigente.';
    case DriverDocumentType.vehicleRegistration:
      return 'Tarjeta de identificación vehicular de tu mototaxi.';
    case DriverDocumentType.dniFront:
    case DriverDocumentType.dniBack:
    case DriverDocumentType.profilePhoto:
    case DriverDocumentType.unknown:
      return '';
  }
}

const _documentNumberPattern = r'^[A-Z0-9./-]{3,50}$';

/// Estado editable de un documento del Paso 4, uno por cada tipo de
/// `requiredDriverOnboardingDocumentTypes`. Vive en el `State` de la
/// pantalla (no es un `StatefulWidget` propio) para mantener el flujo
/// de guardado (`_saveCard`) simple y con un único punto de
/// `setState`.
class _DocumentCardState {
  _DocumentCardState(this.type)
    : documentNumberController = TextEditingController();

  final DriverDocumentType type;
  final TextEditingController documentNumberController;

  DriverDocument? persisted;
  DriverPickedDocumentFile? pendingFile;

  DateTime? issuedAt;
  DateTime? expiresAt;

  bool picking = false;
  bool saving = false;

  String? fileError;
  String? documentNumberError;
  String? issuedAtError;
  String? expiresAtError;

  /// Mensaje de estado post-guardado: éxito silencioso (`null`),
  /// "archivo cargado pero faltan datos" (fallo de PATCH tras un
  /// complete exitoso) o error genérico.
  String? statusMessage;

  /// `DRIVER-ONBOARDING-R3.7`: el usuario pidió editar la metadata de
  /// un documento ya completo (botón "Editar datos") sin reemplazar
  /// el archivo. Se resetea a `false` tras un guardado exitoso que
  /// deje la tarjeta completa de nuevo.
  bool editingMetadata = false;

  bool get requiresExpiresAt =>
      type == DriverDocumentType.driverLicense ||
      type == DriverDocumentType.soat;

  bool get hasAnyFile => pendingFile != null || (persisted?.hasFile ?? false);

  bool get isComplete =>
      pendingFile == null && isDriverDocumentComplete(persisted);

  void dispose() {
    documentNumberController.dispose();
  }
}

enum _DocumentPickSource { camera, gallery, pdf }

/// Paso 4 del onboarding de Driver: "Tus documentos".
///
/// Solo llega aquí `DriverSessionKind.draftDocumentsIncomplete` (ver
/// `driver_onboarding_routes.dart`): los 3 documentos requeridos ya
/// completos (archivo + metadata) significa que este paso ya terminó,
/// así que ese caso va directo a [DriverOnboardingRoutes.start]
/// (foundation de Paso 5).
///
/// Decisiones de producto ya cerradas (`DRIVER-ONBOARDING-R3.6`):
/// selector cámara/galería/PDF por documento, metadata capturada
/// dentro de este mismo paso (nunca diferida a Paso 5), sin preview/
/// renderizador visual de PDF (solo ícono + nombre de archivo; las
/// imágenes sí pueden mostrar una miniatura local).
///
/// El reemplazo de archivo NO usa `DELETE` — Backend reemplaza
/// automáticamente el `fileObjectKey` al hacer `complete` sobre la
/// misma categoría (verificado en `DRIVER-ONBOARDING-R3.6A`,
/// `completeDocumentUpload` en `driver-documents.service.ts`), y
/// preserva la metadata existente en el reemplazo.
class DriverOnboardingDocumentsScreen extends ConsumerStatefulWidget {
  const DriverOnboardingDocumentsScreen({super.key});

  @override
  ConsumerState<DriverOnboardingDocumentsScreen> createState() =>
      _DriverOnboardingDocumentsScreenState();
}

class _DriverOnboardingDocumentsScreenState
    extends ConsumerState<DriverOnboardingDocumentsScreen> {
  late final Map<DriverDocumentType, _DocumentCardState> _cards = {
    for (final type in requiredDriverOnboardingDocumentTypes)
      type: _DocumentCardState(type),
  };

  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  @override
  void dispose() {
    for (final card in _cards.values) {
      card.dispose();
    }
    super.dispose();
  }

  bool get _anyCardBusy =>
      _cards.values.any((card) => card.saving || card.picking);

  bool get _allComplete => _cards.values.every((card) => card.isComplete);

  Future<void> _loadDocuments() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });

    final authRepository = ref.read(authRepositoryProvider);

    try {
      final documents = await authRepository.getMyDocuments();

      if (!mounted) {
        return;
      }

      setState(() {
        for (final document in documents) {
          final card = _cards[document.type];

          if (card == null) {
            continue;
          }

          card.persisted = document;
          card.documentNumberController.text = document.documentNumber ?? '';
          card.issuedAt = _parseIsoDate(document.issuedAt);
          card.expiresAt = _parseIsoDate(document.expiresAt);
        }

        _loading = false;
      });
    } catch (error) {
      debugPrint('Error cargando documentos Driver: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _loadError = true;
      });
    }
  }

  Future<void> _openSourceSheet(_DocumentCardState card) async {
    if (card.picking || card.saving) {
      return;
    }

    final source = await showModalBottomSheet<_DocumentPickSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DocumentSourceSheet(),
    );

    if (source == null || !mounted) {
      return;
    }

    setState(() {
      card.picking = true;
      card.fileError = null;
    });

    try {
      DriverPickedDocumentFile? picked;

      switch (source) {
        case _DocumentPickSource.camera:
          picked = await pickDriverOnboardingDocumentImage(ImageSource.camera);
        case _DocumentPickSource.gallery:
          picked = await pickDriverOnboardingDocumentImage(ImageSource.gallery);
        case _DocumentPickSource.pdf:
          picked = await pickDriverOnboardingDocumentPdf();
      }

      if (!mounted) {
        return;
      }

      if (picked != null) {
        setState(() {
          card.pendingFile = picked;
          card.statusMessage = null;
        });
      }
    } on DriverDocumentUnsupportedFormatException {
      if (!mounted) {
        return;
      }

      setState(() {
        card.fileError =
            'Selecciona una foto en formato JPG, PNG o WEBP, o un '
            'archivo PDF.';
      });
    } on DriverDocumentFileUnavailableException {
      if (!mounted) {
        return;
      }

      setState(() {
        card.fileError = 'No pudimos leer el archivo seleccionado.';
      });
    } on PlatformException {
      if (!mounted) {
        return;
      }

      setState(() {
        card.fileError =
            'No pudimos acceder a la cámara, galería o archivos. Revisa '
            'los permisos.';
      });
    } catch (error) {
      debugPrint('Error seleccionando documento Driver (${card.type}): $error');

      if (!mounted) {
        return;
      }

      setState(() {
        card.fileError =
            'No pudimos seleccionar el archivo. Intenta '
            'nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          card.picking = false;
        });
      }
    }
  }

  Future<void> _pickDate(
    _DocumentCardState card, {
    required bool isExpiresAt,
  }) async {
    if (card.saving) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final initialDate = isExpiresAt
        ? (card.expiresAt ?? card.issuedAt ?? today)
        : (card.issuedAt ?? today);

    final firstDate = isExpiresAt
        ? (card.issuedAt ?? DateTime(today.year - 20))
        : DateTime(today.year - 20);

    final lastDate = isExpiresAt ? DateTime(today.year + 20) : today;

    final picked = await _pickDriverOnboardingDocumentDate(
      context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: lastDate.isBefore(firstDate) ? firstDate : lastDate,
      helpText: isExpiresAt ? 'Fecha de vencimiento' : 'Fecha de emisión',
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      if (isExpiresAt) {
        card.expiresAt = picked;
        card.expiresAtError = null;
      } else {
        card.issuedAt = picked;
        card.issuedAtError = null;
      }
    });
  }

  Future<void> _saveCard(_DocumentCardState card) async {
    if (card.saving || card.picking) {
      return;
    }

    final documentNumberRaw = card.documentNumberController.text
        .trim()
        .toUpperCase();
    final documentNumberValid = RegExp(
      _documentNumberPattern,
    ).hasMatch(documentNumberRaw);

    final issuedAt = card.issuedAt;
    final expiresAt = card.expiresAt;

    final now = DateTime.now();
    final todayUtc = DateTime.utc(now.year, now.month, now.day);

    setState(() {
      card.documentNumberError = documentNumberValid
          ? null
          : 'Ingresa un número de documento válido (3 a 50 caracteres).';

      card.issuedAtError = issuedAt == null
          ? 'Selecciona la fecha de emisión.'
          : (issuedAt.isAfter(todayUtc)
                ? 'La fecha de emisión no puede ser futura.'
                : null);

      if (card.requiresExpiresAt) {
        if (expiresAt == null) {
          card.expiresAtError = 'Selecciona la fecha de vencimiento.';
        } else if (issuedAt != null && !expiresAt.isAfter(issuedAt)) {
          card.expiresAtError =
              'La fecha de vencimiento debe ser posterior a la de emisión.';
        } else if (expiresAt.isBefore(todayUtc)) {
          card.expiresAtError =
              'Este documento ya venció. Actualiza la fecha de '
              'vencimiento.';
        } else {
          card.expiresAtError = null;
        }
      } else {
        card.expiresAtError = null;
      }

      if (!card.hasAnyFile) {
        card.fileError = 'Agrega un archivo para continuar.';
      }
    });

    final hasFieldErrors =
        card.documentNumberError != null ||
        card.issuedAtError != null ||
        card.expiresAtError != null;

    if (hasFieldErrors || !card.hasAnyFile) {
      return;
    }

    setState(() {
      card.saving = true;
      card.statusMessage = null;
    });

    final authRepository = ref.read(authRepositoryProvider);
    final storageRepository = ref.read(driverStorageRepositoryProvider);
    final uploader = ref.read(driverPhotoUploaderProvider);
    final documentRepository = ref.read(driverDocumentRepositoryProvider);

    try {
      if (card.pendingFile != null) {
        final file = card.pendingFile!;
        final category = storageCategoryForDriverDocumentType(card.type);

        final presigned = await storageRepository.presignUpload(
          category: category,
          contentType: file.contentType,
          fileSize: file.bytes.length,
        );

        await uploader.upload(
          uploadUrl: presigned.uploadUrl,
          contentType: presigned.contentType,
          bytes: file.bytes,
        );

        await storageRepository.completeUpload(
          category: category,
          objectKey: presigned.objectKey,
        );

        final documents = await authRepository.getMyDocuments();

        DriverDocument? match;

        for (final document in documents) {
          if (document.type == card.type) {
            match = document;
            break;
          }
        }

        if (!mounted) {
          return;
        }

        setState(() {
          card.persisted = match;
          card.pendingFile = null;
        });
      }

      final documentId = card.persisted?.id;

      if (documentId == null || documentId.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          card.statusMessage =
              'No pudimos confirmar tu archivo. Inténtalo nuevamente.';
        });
        return;
      }

      final updated = await documentRepository.updateDocumentMetadata(
        documentId: documentId,
        documentNumber: documentNumberRaw,
        issuedAt: formatDriverOnboardingIsoDate(issuedAt!),
        expiresAt: card.requiresExpiresAt
            ? formatDriverOnboardingIsoDate(expiresAt!)
            : null,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        card.persisted = updated;
        card.statusMessage = null;
        card.editingMetadata = false;
      });
    } on DioException catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        card.statusMessage = card.persisted?.hasFile == true
            ? 'El archivo se cargó, pero faltan datos por guardar.'
            : 'No pudimos subir el archivo. Inténtalo nuevamente.';
      });
    } catch (error) {
      debugPrint(
        'Error inesperado guardando documento Driver (${card.type}): $error',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        card.statusMessage =
            'No pudimos guardar el documento. Inténtalo nuevamente.';
      });
    } finally {
      if (mounted) {
        setState(() {
          card.saving = false;
        });
      }
    }
  }

  Future<void> _continue() async {
    if (!_allComplete || _anyCardBusy) {
      return;
    }

    final authRepository = ref.read(authRepositoryProvider);
    final freshState = await authRepository.resolveSessionState();

    if (!mounted) {
      return;
    }

    goToDriverSessionRoute(context, freshState);
  }

  /// Reachable both desde el routing normal de onboarding
  /// (`context.go`, sin pila) y empujada desde "Editar" en "Revisar y
  /// enviar" (`context.push`, con pila — `DRIVER-ONBOARDING-R3.7`).
  /// `Navigator.canPop()` distingue ambos casos sin necesitar
  /// argumentos nuevos: si hay pila, solo vuelve atrás; si no, es el
  /// comportamiento de siempre (cerrar sesión).
  Future<void> _handleBack() async {
    if (_anyCardBusy) {
      return;
    }

    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }

    await _exitToLogin();
  }

  Future<void> _exitToLogin() async {
    final repository = ref.read(authRepositoryProvider);

    try {
      await repository.logout();
    } catch (error) {
      debugPrint('Error cerrando sesión desde Tus documentos: $error');
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
          key: const Key('documents-back-button'),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: DriverPalette.greenPrimary,
          ),
          onPressed: _anyCardBusy ? null : _handleBack,
        ),
      ),
      body: SafeArea(top: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('documents-loading'),
        child: CircularProgressIndicator(color: DriverPalette.greenPrimary),
      );
    }

    if (_loadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('documents-load-error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'No pudimos cargar tus documentos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DriverPalette.greenPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('documents-retry-button'),
                onPressed: _loadDocuments,
                style: FilledButton.styleFrom(
                  backgroundColor: DriverPalette.greenPrimary,
                  foregroundColor: DriverPalette.cream,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DriverOnboardingProgress(currentStep: 4),
          const SizedBox(height: 24),
          const Text(
            'Tus documentos',
            style: TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Sube tu licencia, SOAT y tarjeta de propiedad para poder '
            'enviar tu solicitud.',
            style: TextStyle(
              color: DriverPalette.brown,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          for (final type in requiredDriverOnboardingDocumentTypes) ...[
            _buildCard(_cards[type]!),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: FilledButton(
              key: const Key('documents-continue-button'),
              onPressed: (_allComplete && !_anyCardBusy) ? _continue : null,
              style: FilledButton.styleFrom(
                backgroundColor: DriverPalette.greenPrimary,
                foregroundColor: DriverPalette.cream,
                disabledBackgroundColor: DriverPalette.greenPrimary.withValues(
                  alpha: 0.4,
                ),
                disabledForegroundColor: DriverPalette.cream,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Continuar',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(_DocumentCardState card) {
    final slug = _slugForType(card.type);

    return Container(
      key: Key('documents-$slug-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E0CB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titleForType(card.type),
            style: const TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _descriptionForType(card.type),
            style: const TextStyle(
              color: DriverPalette.brown,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (!card.hasAnyFile)
            _AddDocumentButton(
              cardKey: Key('documents-$slug-add-button'),
              enabled: !card.picking && !card.saving,
              onTap: () => _openSourceSheet(card),
            )
          else
            _buildFileRow(card, slug),
          if (card.fileError != null) ...[
            const SizedBox(height: 8),
            Text(
              card.fileError!,
              key: Key('documents-$slug-file-error'),
              style: const TextStyle(
                color: DriverPalette.coral,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (card.isComplete && !card.editingMetadata) ...[
            const SizedBox(height: 12),
            Row(
              key: Key('documents-$slug-complete-badge'),
              children: [
                const Icon(
                  Icons.check_circle,
                  color: DriverPalette.greenAvailable,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Documento cargado',
                  style: TextStyle(
                    color: DriverPalette.greenPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  key: Key('documents-$slug-edit-data-button'),
                  onPressed: card.saving || card.picking
                      ? null
                      : () => setState(() {
                          card.editingMetadata = true;
                        }),
                  style: TextButton.styleFrom(
                    foregroundColor: DriverPalette.greenAvailable,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Editar datos'),
                ),
              ],
            ),
          ] else if (card.hasAnyFile) ...[
            const SizedBox(height: 12),
            _buildMetadataForm(card, slug),
          ],
          if (card.statusMessage != null) ...[
            const SizedBox(height: 10),
            Text(
              card.statusMessage!,
              key: Key('documents-$slug-status-message'),
              style: const TextStyle(
                color: DriverPalette.orangeDeep,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFileRow(_DocumentCardState card, String slug) {
    final pending = card.pendingFile;

    final fileName =
        pending?.fileName ??
        (card.persisted?.hasFile == true ? 'Archivo cargado' : '');

    return Row(
      children: [
        _buildFileThumbnail(card),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            fileName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DriverPalette.greenPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          key: Key('documents-$slug-change-button'),
          onPressed: (card.picking || card.saving)
              ? null
              : () => _openSourceSheet(card),
          style: TextButton.styleFrom(
            foregroundColor: DriverPalette.greenAvailable,
          ),
          child: const Text('Cambiar'),
        ),
      ],
    );
  }

  Widget _buildFileThumbnail(_DocumentCardState card) {
    final pending = card.pendingFile;

    if (pending != null && !pending.isPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          pending.bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    }

    // No hay preview/renderizador para PDF (decisión de producto
    // R3.6). Los documentos ya persistidos tampoco muestran preview
    // de imagen: esta pantalla nunca vuelve a descargar el archivo
    // remoto, solo usa los bytes recién elegidos localmente.
    final icon = pending != null && pending.isPdf
        ? Icons.picture_as_pdf_outlined
        : Icons.description_outlined;

    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriverPalette.greenPrimary),
      ),
      child: Icon(icon, color: DriverPalette.greenPrimary),
    );
  }

  Widget _buildMetadataForm(_DocumentCardState card, String slug) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: Key('documents-$slug-number-field'),
          controller: card.documentNumberController,
          enabled: !card.saving,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) {
            if (card.documentNumberError != null) {
              setState(() {
                card.documentNumberError = null;
              });
            }
          },
          decoration: _decoration(
            label: 'Número de documento',
            errorText: card.documentNumberError,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          key: Key('documents-$slug-issued-at-field'),
          onTap: card.saving ? null : () => _pickDate(card, isExpiresAt: false),
          borderRadius: BorderRadius.circular(16),
          child: InputDecorator(
            decoration: _decoration(
              label: 'Fecha de emisión',
              errorText: card.issuedAtError,
            ),
            child: Text(
              card.issuedAt == null
                  ? 'Selecciona una fecha'
                  : _formatDisplayDate(card.issuedAt!),
              style: TextStyle(
                color: card.issuedAt == null
                    ? const Color(0xFF7C8A79)
                    : DriverPalette.greenPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (card.requiresExpiresAt) ...[
          const SizedBox(height: 12),
          InkWell(
            key: Key('documents-$slug-expires-at-field'),
            onTap: card.saving
                ? null
                : () => _pickDate(card, isExpiresAt: true),
            borderRadius: BorderRadius.circular(16),
            child: InputDecorator(
              decoration: _decoration(
                label: 'Fecha de vencimiento',
                errorText: card.expiresAtError,
              ),
              child: Text(
                card.expiresAt == null
                    ? 'Selecciona una fecha'
                    : _formatDisplayDate(card.expiresAt!),
                style: TextStyle(
                  color: card.expiresAt == null
                      ? const Color(0xFF7C8A79)
                      : DriverPalette.greenPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton(
            key: Key('documents-$slug-save-button'),
            onPressed: card.saving ? null : () => _saveCard(card),
            style: FilledButton.styleFrom(
              backgroundColor: DriverPalette.greenAvailable,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
            child: card.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Guardar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ],
    );
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
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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

class _AddDocumentButton extends StatelessWidget {
  const _AddDocumentButton({
    required this.cardKey,
    required this.enabled,
    required this.onTap,
  });

  final Key cardKey;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: cardKey,
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, color: DriverPalette.greenPrimary),
              SizedBox(width: 10),
              Text(
                'Agregar documento',
                style: TextStyle(
                  color: DriverPalette.greenPrimary,
                  fontSize: 14,
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

class _DocumentSourceSheet extends StatelessWidget {
  const _DocumentSourceSheet();

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
              'Agregar documento',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DriverPalette.greenPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _DocumentSourceOption(
              key: const Key('document-picker-camera-option'),
              icon: Icons.photo_camera_outlined,
              label: 'Tomar una foto',
              onTap: () =>
                  Navigator.of(context).pop(_DocumentPickSource.camera),
            ),
            const SizedBox(height: 8),
            _DocumentSourceOption(
              key: const Key('document-picker-gallery-option'),
              icon: Icons.photo_library_outlined,
              label: 'Elegir de galería',
              onTap: () =>
                  Navigator.of(context).pop(_DocumentPickSource.gallery),
            ),
            const SizedBox(height: 8),
            _DocumentSourceOption(
              key: const Key('document-picker-pdf-option'),
              icon: Icons.picture_as_pdf_outlined,
              label: 'Elegir archivo PDF',
              onTap: () => Navigator.of(context).pop(_DocumentPickSource.pdf),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('document-picker-cancel-button'),
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

class _DocumentSourceOption extends StatelessWidget {
  const _DocumentSourceOption({
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
