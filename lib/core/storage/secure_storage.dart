import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

class StorageKeys {
  const StorageKeys._();

  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const sessionId = 'session_id';
}