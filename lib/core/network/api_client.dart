import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../storage/secure_storage.dart';

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.normalizedApiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    _SafeNetworkLogger(),
  );

  dio.interceptors.add(
    AuthInterceptor(
      dio,
      storage,
    ),
  );

  return dio;
});

class _SafeNetworkLogger extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      debugPrint(
        'API -> ${options.method} '
        '${options.uri.path}',
      );
    }

    handler.next(options);
  }

  @override
  void onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      debugPrint(
        'API <- ${response.statusCode} '
        '${response.requestOptions.method} '
        '${response.requestOptions.uri.path}',
      );
    }

    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    if (kDebugMode) {
      debugPrint(
        'API !! ${err.response?.statusCode ?? '-'} '
        '${err.requestOptions.method} '
        '${err.requestOptions.uri.path} '
        'type=${err.type}',
      );
    }

    handler.next(err);
  }
}

class AuthInterceptor extends Interceptor {
  AuthInterceptor(
    this._dio,
    this._storage,
  );

  static const String _authRetryKey =
      '_auth_retry_attempted';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  Future<bool>? _refreshFuture;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_shouldSkipAuthHeader(options.path)) {
      options.headers.remove('Authorization');
      handler.next(options);
      return;
    }

    final accessToken = await _storage.read(
      key: StorageKeys.accessToken,
    );

    if (accessToken != null &&
        accessToken.isNotEmpty) {
      options.headers['Authorization'] =
          'Bearer $accessToken';
    } else {
      options.headers.remove('Authorization');
    }

    handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final requestOptions = err.requestOptions;

    if (statusCode != 401 ||
        _shouldSkipRefresh(requestOptions.path)) {
      handler.next(err);
      return;
    }

    final alreadyRetried =
        requestOptions.extra[_authRetryKey] == true;

    if (alreadyRetried) {
      await _clearSession();
      handler.next(err);
      return;
    }

    final refreshed =
        await _refreshSession();

    if (!refreshed) {
      await _clearSession();
      handler.next(err);
      return;
    }

    final newAccessToken = await _storage.read(
      key: StorageKeys.accessToken,
    );

    if (newAccessToken == null ||
        newAccessToken.isEmpty) {
      await _clearSession();
      handler.next(err);
      return;
    }

    requestOptions.headers['Authorization'] =
        'Bearer $newAccessToken';

    requestOptions.extra[_authRetryKey] = true;

    try {
      final response =
          await _dio.fetch<dynamic>(
        requestOptions,
      );

      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'AUTH RETRY ERROR: $error',
        );
      }

      handler.next(err);
    }
  }

  bool _shouldSkipAuthHeader(
    String path,
  ) {
    return path.contains('auth/login') ||
        path.contains('auth/refresh') ||
        path.contains('auth/register') ||
        path.contains('auth/otp/');
  }

  bool _shouldSkipRefresh(
    String path,
  ) {
    return path.contains('auth/login') ||
        path.contains('auth/refresh') ||
        path.contains('auth/register') ||
        path.contains('auth/otp/');
  }

  Future<bool> _refreshSession() async {
    final existingRefresh =
        _refreshFuture;

    if (existingRefresh != null) {
      return existingRefresh;
    }

    final future = _performRefresh();
    _refreshFuture = future;

    try {
      return await future;
    } finally {
      if (identical(
        _refreshFuture,
        future,
      )) {
        _refreshFuture = null;
      }
    }
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await _storage.read(
      key: StorageKeys.refreshToken,
    );

    if (refreshToken == null ||
        refreshToken.isEmpty) {
      return false;
    }

    final refreshDio = Dio(
      BaseOptions(
        baseUrl:
            AppConfig.normalizedApiBaseUrl,
        connectTimeout:
            const Duration(seconds: 10),
        receiveTimeout:
            const Duration(seconds: 10),
        sendTimeout:
            const Duration(seconds: 10),
        headers: const {
          'Accept': 'application/json',
          'Content-Type':
              'application/json',
        },
      ),
    );

    try {
      final response =
          await refreshDio
              .post<Map<String, dynamic>>(
        'auth/refresh',
        data: {
          'refreshToken': refreshToken,
        },
      );

      final data = response.data;

      if (data == null) {
        return false;
      }

      final accessToken =
          data['accessToken'] as String?;

      final newRefreshToken =
          data['refreshToken'] as String?;

      final sessionId =
          data['sessionId'] as String?;

      if (accessToken == null ||
          accessToken.isEmpty ||
          newRefreshToken == null ||
          newRefreshToken.isEmpty ||
          sessionId == null ||
          sessionId.isEmpty) {
        return false;
      }

      await _storage.write(
        key: StorageKeys.accessToken,
        value: accessToken,
      );

      await _storage.write(
        key: StorageKeys.refreshToken,
        value: newRefreshToken,
      );

      await _storage.write(
        key: StorageKeys.sessionId,
        value: sessionId,
      );

      return true;
    } on DioException {
      return false;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          'AUTH REFRESH ERROR: $error',
        );
      }

      return false;
    }
  }

  Future<void> _clearSession() async {
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