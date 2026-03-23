import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  static const _tokenKey = 'jwt_token';
  static const _profileKey = 'user_profile';

  ApiClient._internal() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';

    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    // --- Request interceptor: attach JWT on every call ---
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        // 401 → clear stale token, caller handles redirect
        if (e.response?.statusCode == 401) {
          await clearToken();
        }
        return handler.next(e);
      },
    ));
  }

  // ─────────────────────────────────────────
  // Token helpers
  // ─────────────────────────────────────────

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<bool> get isLoggedIn async => (await getToken()) != null;

  // ─────────────────────────────────────────
  // Profile cache helpers
  // ─────────────────────────────────────────

  Future<void> saveProfile(Map<String, dynamic> profile) =>
      _storage.write(key: _profileKey, value: jsonEncode(profile));

  Future<Map<String, dynamic>?> getCachedProfile() async {
    final raw = await _storage.read(key: _profileKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // ─────────────────────────────────────────
  // AUTH
  // ─────────────────────────────────────────

  /// Returns the LinkedIn OAuth URL to open in a browser.
  Future<String> getLinkedInAuthUrl() async {
    final res = await _dio.get('/auth/linkedin');
    return res.data['auth_url'] as String;
  }

  /// Exchange the OAuth callback URL for a JWT + user profile.
  Future<Map<String, dynamic>> handleLinkedInCallback(String callbackUrl) async {
    // Parse params from signtone://auth/callback?access_token=...
    final uri = Uri.parse(callbackUrl);
    final token = uri.queryParameters['access_token'];
    if (token == null || token.isEmpty) {
      throw Exception('No access token in LinkedIn callback');
    }
    await saveToken(token);

    final user = {
      'name':         uri.queryParameters['name']     ?? '',
      'email':        uri.queryParameters['email']    ?? '',
      'profile_picture': uri.queryParameters['picture']  ?? '',
      'headline':     uri.queryParameters['headline'] ?? '',
      'linkedin_id':  uri.queryParameters['user_id']  ?? '',
    };
    await saveProfile(user);
    return {'access_token': token, 'user': user};
  }

  Future<void> logout() => clearAll();

  // ─────────────────────────────────────────
  // PROFILES
  // ─────────────────────────────────────────

  Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _dio.get('/profiles/me');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateProfessionalProfile(
      Map<String, dynamic> data) async {
    final res = await _dio.put('/profiles/me/professional', data: data);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updatePublicProfile(
      Map<String, dynamic> data) async {
    final res = await _dio.put('/profiles/me/public', data: data);
    return res.data as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────
  // SIGNALS
  // ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSignals() async {
    final res = await _dio.get('/signals');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  /// Match a detected frequency pair against registered beacons.
  /// [freqs] - list of dominant frequencies captured from mic (Hz).
  Future<Map<String, dynamic>?> matchSignal(List<double> freqs) async {
    try {
      final res = await _dio.post(
        '/signals/match',
        data: {'frequencies': freqs},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null; // no match
      rethrow;
    }
  }

  // ─────────────────────────────────────────
  // EVENTS
  // ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getEvents() async {
    final res = await _dio.get('/events');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getEvent(String eventId) async {
    final res = await _dio.get('/events/$eventId');
    return res.data as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────
  // REGISTRATIONS
  // ─────────────────────────────────────────

  /// Register for an event using a specific profile type.
  /// [profileType] - 'professional' or 'public'
  Future<Map<String, dynamic>> register({
    required String eventId,
    required String signalId,
    required String profileType,
  }) async {
    final res = await _dio.post('/registrations', data: {
      'event_id': eventId,
      'signal_id': signalId,
      'profile_type': profileType,
    });
    return res.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getMyRegistrations() async {
    final res = await _dio.get('/registrations/me');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  // ─────────────────────────────────────────
  // Generic helpers (for future endpoints)
  // ─────────────────────────────────────────

  Future<dynamic> get(String path, {Map<String, dynamic>? params}) async {
    final res = await _dio.get(path, queryParameters: params);
    return res.data;
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? data}) async {
    final res = await _dio.post(path, data: data);
    return res.data;
  }
}
