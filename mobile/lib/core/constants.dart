import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  AppConstants._(); // prevent instantiation

  // ─────────────────────────────────────────
  // App info
  // ─────────────────────────────────────────
  static const String appName    = 'Signtone';
  static const String appTagline = 'Hear it. Sign it. Done.';
  static const String appVersion = '1.0.0';

  // ─────────────────────────────────────────
  // API
  // ─────────────────────────────────────────
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';

  static String get healthUrl  => '$baseUrl/health';
  static String get authUrl    => '$baseUrl/auth/linkedin';
  static String get profileUrl => '$baseUrl/profiles/me';

  // ─────────────────────────────────────────
  // LinkedIn OAuth
  // ─────────────────────────────────────────
  // The backend handles the OAuth flow.
  // The app only needs to know the custom URL scheme
  // that LinkedIn redirects back to after login.
  static const String linkedInCallbackScheme = 'signtone';
  static const String linkedInCallbackUrl    = 'signtone://auth/callback';

  // ─────────────────────────────────────────
  // Audio listener
  // ─────────────────────────────────────────

  /// How long (ms) each audio chunk is before being sent for matching.
  static const int audioChunkDurationMs = 3000;

  /// Minimum signal strength to attempt a match (avoids noise triggers).
  static const double signalThresholdDb = -40.0;

  /// Sample rate expected by the backend beacon decoder.
  static const int sampleRateHz = 22050;

  /// BFSK frequency band used by Signtone beacons (18-20 kHz).
  /// Must match beacon_service.py on the backend.
  static const double beaconFreqLow  = 18000.0; // Hz - bit 0
  static const double beaconFreqHigh = 19000.0; // Hz - bit 1

  // ─────────────────────────────────────────
  // Profile types
  // ─────────────────────────────────────────
  static const String profileTypeProfessional = 'professional';
  static const String profileTypePublic       = 'public';

  // ─────────────────────────────────────────
  // Secure storage keys
  // ─────────────────────────────────────────
  static const String storageKeyToken   = 'jwt_token';
  static const String storageKeyProfile = 'user_profile';

  // ─────────────────────────────────────────
  // UI timing
  // ─────────────────────────────────────────

  /// How long the confirmation card stays visible before auto-dismissing.
  static const int confirmationAutoDismissSec = 30;

  /// Splash screen display duration before routing to home.
  static const int splashDurationMs = 2000;

  // ─────────────────────────────────────────
  // Route names  (used by router.dart)
  // ─────────────────────────────────────────
  static const String routeSplash       = '/';
  static const String routeLogin        = '/login';
  static const String routeHome         = '/home';
  static const String routeConfirm      = '/confirm';
  static const String routeHistory      = '/history';
  static const String routeProfile      = '/profile';
  static const String routeEditProfile  = '/profile/edit';
}
