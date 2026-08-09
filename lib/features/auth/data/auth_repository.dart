import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(secureStorageProvider),
  );
});

class AuthRepository {
  AuthRepository(
    this._dio,
    this._storage,
  );

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<void> login({
    required String phoneE164,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      'auth/login',
      data: {
        'phoneE164': phoneE164,
        'password': password,
      },
    );

    final data = response.data;

    if (data == null) {
      throw Exception(
        'El backend devolvió una respuesta vacía.',
      );
    }

    final accessToken = data['accessToken'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    final sessionId = data['sessionId'] as String?;

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      throw Exception(
        'La respuesta de inicio de sesión es inválida.',
      );
    }

    try {
      await _storage.write(
        key: StorageKeys.accessToken,
        value: accessToken,
      );

      await _storage.write(
        key: StorageKeys.refreshToken,
        value: refreshToken,
      );

      await _storage.write(
        key: StorageKeys.sessionId,
        value: sessionId,
      );
    } catch (_) {
      await clearSession();
      rethrow;
    }
  }

  Future<bool> hasSession() async {
    final accessToken = await _storage.read(
      key: StorageKeys.accessToken,
    );

    final refreshToken = await _storage.read(
      key: StorageKeys.refreshToken,
    );

    final sessionId = await _storage.read(
      key: StorageKeys.sessionId,
    );

    return accessToken != null &&
        accessToken.isNotEmpty &&
        refreshToken != null &&
        refreshToken.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty;
  }

  Future<bool> isDriver() async {
    final response =
        await _dio.get<Map<String, dynamic>>(
      'auth/me',
    );

    final data = response.data;

    if (data == null) {
      return false;
    }

    final rawRoles = data['roles'];

    if (rawRoles is! List) {
      return false;
    }

    final roles = rawRoles
        .map((role) => role.toString())
        .toList();

    return roles.contains('DRIVER');
  }

  Future<void> logout() async {
    try {
      await _dio.post<void>(
        'auth/logout',
      );
    } on DioException {
      // El logout remoto es best-effort.
      //
      // Si el access token ya venció, la sesión fue
      // revocada o el backend no está disponible,
      // igualmente debemos cerrar la sesión local.
    } finally {
      await clearSession();
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(
      key: StorageKeys.accessToken,
    );

    await _storage.delete(
      key: StorageKeys.refreshToken,
    );

    await _storage.delete(
      key: StorageKeys.sessionId,
    );
  }
}