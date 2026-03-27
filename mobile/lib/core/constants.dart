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
  static const String linkedInCallbackScheme = 'signtone';
  static const String linkedInCallbackUrl    = 'signtone://auth/callback';

  // ─────────────────────────────────────────
  // Audio listener
  // ─────────────────────────────────────────

  /// How long (ms) each audio chunk is before being sent for matching.
  static const int audioChunkDurationMs = 80;

  /// Minimum signal strength to attempt a match.
  static const double signalThresholdDb = -60.0;

  /// Sample rate expected by the backend beacon decoder.
  static const int sampleRateHz = 44100;

  // ── Ultrasonic profile (15-17 kHz) ───────────────────────────────────────
  // Inaudible, short range (~30m), for quiet/small venues
  static const double beaconFreqSync      = 15000.0;
  static const double beaconFreqLow       = 16000.0;
  static const double beaconFreqHigh      = 17000.0;

  // ── Audible profile (C major - 262/330/392 Hz) ───────────────────────────
  // Soft whistle tone, long range (~300m), for large venues
  // Sounds: pleasant, minimal, purposeful
  static const double beaconAudibleSync   = 262.0;   // C4
  static const double beaconAudibleLow    = 330.0;   // E4
  static const double beaconAudibleHigh   = 392.0;   // G4

  // ── Bandpass ranges ───────────────────────────────────────────────────────
  static const double bandpassUltrasonicLow  = 13500.0;
  static const double bandpassUltrasonicHigh = 17500.0;
  static const double bandpassAudibleLow     = 200.0;
  static const double bandpassAudibleHigh    = 500.0;

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
  static const int confirmationAutoDismissSec = 30;
  static const int splashDurationMs           = 2000;

  // ─────────────────────────────────────────
  // Route names
  // ─────────────────────────────────────────
  static const String routeSplash      = '/';
  static const String routeLogin       = '/login';
  static const String routeHome        = '/home';
  static const String routeConfirm     = '/confirm';
  static const String routeHistory     = '/history';
  static const String routeProfile     = '/profile';
  static const String routeEditProfile = '/profile/edit';
}
