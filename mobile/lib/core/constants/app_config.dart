import 'package:flutter/foundation.dart';

/// Centralized environment and API configuration for RootU mobile.
///
/// In Development:
///   Connects to local backend via USB reverse proxy (`http://127.0.0.1:3000`).
///
/// In Production:
///   Defaults to production domain, or can be passed at build time with:
///   `flutter build apk --dart-define=API_BASE_URL=https://api.rootu.app`
class AppConfig {
  AppConfig._();

  /// Root API host URL (without trailing slash).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://api.rootu.app'
        : 'http://127.0.0.1:3000',
  );

  /// Full endpoint for Authentication API.
  static String get authBaseUrl => '$apiBaseUrl/api/v1/auth';

  /// WebSocket URL for Realtime Gateway.
  static const String wsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: kReleaseMode
        ? 'wss://realtime.rootu.app/ws'
        : 'ws://127.0.0.1:3001/ws',
  );
}
