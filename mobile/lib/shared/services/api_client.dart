import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final _storage = const FlutterSecureStorage();

  static const _tokenKey   = 'jwt_token';
  static const _profileKey = 'user_profile';

  ApiClient._internal() {
    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';

    _dio = Dio(BaseOptions(
      baseUrl:         baseUrl,
      connectTimeout:  const Duration(seconds: 10),
      receiveTimeout:  const Duration(seconds: 30),
      followRedirects: true,
      maxRedirects:    3,
      headers: {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {
          // Plugin not ready yet on cold start - skip token attachment
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
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

  Future<String> getLinkedInAuthUrl() async {
    final res = await _dio.get('/auth/linkedin');
    return res.data['auth_url'] as String;
  }

  Future<Map<String, dynamic>> handleLinkedInCallback(String callbackUrl) async {
    final uri   = Uri.parse(callbackUrl);
    final token = uri.queryParameters['access_token'];
    if (token == null || token.isEmpty) {
      throw Exception('No access token in LinkedIn callback');
    }
    await saveToken(token);

    final user = {
      'name':            uri.queryParameters['name']     ?? '',
      'email':           uri.queryParameters['email']    ?? '',
      'profile_picture': uri.queryParameters['picture']  ?? '',
      'headline':        uri.queryParameters['headline'] ?? '',
      'linkedin_id':     uri.queryParameters['user_id']  ?? '',
    };
    await saveProfile(user);
    return {'access_token': token, 'user': user};
  }

  Future<Map<String, dynamic>> guestLogin({
    required String name,
    required String email,
    String? phone,
  }) async {
    final res = await _dio.post('/auth/guest', data: {
      'name':  name,
      'email': email,
      if (phone != null) 'phone': phone,
    });
    return res.data as Map<String, dynamic>;
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

  /// Send raw PCM float samples to backend for BFSK decoding.
  Future<Map<String, dynamic>?> matchSamples(List<double> samples) async {
    try {
      print('[ApiClient] matchSamples: sending ${samples.length} samples');
      final res = await _dio.post(
        '/signals/match',
        data: {
          'samples':     samples,
          'sample_rate': 44100,
        },
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      print('[ApiClient] matchSamples error: ${e.response?.data}');
      rethrow;
    }
  }

  /// Send a pre-decoded beacon payload string to the backend.
  Future<Map<String, dynamic>?> matchPayload(String beaconPayload) async {
    try {
      final res = await _dio.post(
        '/signals/match',
        data: {'beacon_payload': beaconPayload},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      print('[ApiClient] matchPayload error: ${e.response?.data}');
      rethrow;
    }
  }

  /// Legacy: send detected frequencies (no longer primary path).
  Future<Map<String, dynamic>?> matchSignal(List<double> freqs) async {
    try {
      final res = await _dio.post(
        '/signals/match',
        data: {'frequencies': freqs},
      );
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
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

  Future<Map<String, dynamic>> register({
    required String eventId,
    required String signalId,
    required String profileType,
  }) async {
    final payload = {
      'event_id':        eventId,
      'beacon_payload':  signalId,
      'profile_override': profileType,
    };
    print('[ApiClient] register payload: $payload');
    try {
      final res = await _dio.post('/registrations/', data: payload);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      // Return error detail as a map so MatchService can show friendly message
      final detail = e.response?.data?['detail'] as String?
          ?? e.message
          ?? 'Registration failed';
      return {'success': false, 'error': detail};
    }
  }

  Future<List<Map<String, dynamic>>> getMyRegistrations() async {
    final res = await _dio.get('/registrations/user/me');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  // ─────────────────────────────────────────
  // Generic helpers
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
