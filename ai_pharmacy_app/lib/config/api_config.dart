/// Central API configuration.
///
/// Override via --dart-define=BACKEND_URL=...
///
/// Development:
///   flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:5000
///
/// LAN testing:
///   flutter run -d chrome --dart-define=BACKEND_URL=http://10.x.x.x:5000
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'http://localhost:5000',
  );
}
