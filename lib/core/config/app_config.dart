class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get normalizedApiBaseUrl {
    final value = apiBaseUrl.trim();

    if (value.isEmpty) {
      throw StateError(
        'API_BASE_URL no fue configurada. '
        'Ejecuta Flutter usando --dart-define=API_BASE_URL=...',
      );
    }

    return value.endsWith('/') ? value : '$value/';
  }
}