/// Compile-time environment configuration.
///
/// Pass values at run/build time via `--dart-define`, e.g.:
///   flutter run --dart-define=API_BASE_URL=https://abc123.ngrok-free.app/api
///
/// Defaults match local-emulator-friendly XAMPP setup.
class Env {
  Env._();

  /// Base URL for the Laravel API. Includes the `/api` suffix.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api',
  );

  /// Reverb (Pusher-protocol) WebSocket host — usually the same host
  /// as the API without the `/api` suffix or scheme.
  static const String reverbHost = String.fromEnvironment(
    'REVERB_HOST',
    defaultValue: '10.0.2.2',
  );

  static const int reverbPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 8080,
  );

  /// WebSocket scheme — must be `ws` (insecure) or `wss` (TLS).
  /// NOT `http`/`https` — the underlying WebSocketChannel will reject those.
  static const String reverbScheme = String.fromEnvironment(
    'REVERB_SCHEME',
    defaultValue: 'ws',
  );

  // IMPORTANT: must match the backend's `.env` REVERB_APP_KEY exactly.
  // If they don't match, the WebSocket "subscribe" handshake fails silently
  // — connection looks up but no events arrive.
  static const String reverbAppKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: 'teamos-local-dev-key',
  );

  /// Build mode flag for ad-hoc gating (optional).
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'development',
  );

  static bool get isProduction => appEnv == 'production';
}
