import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/constants.dart';
import '../../shared/services/api_client.dart';

// ─────────────────────────────────────────
// Auth method
// ─────────────────────────────────────────
enum AuthMethod { guest, google, linkedin }

// ─────────────────────────────────────────
// Auth status
// ─────────────────────────────────────────
enum AuthStatus { unknown, authenticated, unauthenticated }

// ─────────────────────────────────────────
// UserProfile
// ─────────────────────────────────────────
class UserProfile {
  final String displayName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final AuthMethod authMethod;
  final String? headline;
  final String? linkedInId;

  const UserProfile({
    required this.displayName,
    required this.email,
    this.phone,
    this.avatarUrl,
    required this.authMethod,
    this.headline,
    this.linkedInId,
  });

  bool get canRegisterForConferences =>
      authMethod == AuthMethod.google ||
      authMethod == AuthMethod.linkedin;

  String get authMethodLabel => switch (authMethod) {
        AuthMethod.guest    => 'Guest',
        AuthMethod.google   => 'Google',
        AuthMethod.linkedin => 'LinkedIn',
      };

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'email':        email,
        'phone':        phone,
        'avatar_url':   avatarUrl,
        'auth_method':  authMethod.name,
        'headline':     headline,
        'linkedin_id':  linkedInId,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        displayName: j['display_name'] as String? ?? '',
        email:       j['email']        as String? ?? '',
        phone:       j['phone']        as String?,
        avatarUrl:   j['avatar_url']   as String?,
        authMethod:  AuthMethod.values.firstWhere(
          (m) => m.name == j['auth_method'],
          orElse: () => AuthMethod.guest,
        ),
        headline:   j['headline']    as String?,
        linkedInId: j['linkedin_id'] as String?,
      );
}

// ─────────────────────────────────────────
// AuthService
// ─────────────────────────────────────────
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage      = const FlutterSecureStorage();
  final _api          = ApiClient();
  final _googleSignIn = GoogleSignIn(
    clientId: '396737061744-tniqshag7j1m8k3k9o4657ugic6244jh.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  static const _profileKey = 'signtone_user_profile';

  AuthStatus   _status = AuthStatus.unknown;
  UserProfile? _profile;
  String?      _errorMessage;

  // ─────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────
  AuthStatus   get status       => _status;
  UserProfile? get profile      => _profile;
  String?      get errorMessage => _errorMessage;
  bool get isAuthenticated      => _status == AuthStatus.authenticated;

  String  get displayName   => _profile?.displayName ?? 'User';
  String? get avatarUrl     => _profile?.avatarUrl;
  String? get email         => _profile?.email;
  bool get canDoConferences => _profile?.canRegisterForConferences ?? false;

  Map<String, dynamic>? get user => _profile?.toJson();

  // ─────────────────────────────────────────
  // Initialize
  // ─────────────────────────────────────────
  Future<void> initialize() async {
    try {
      final raw = await _storage.read(key: _profileKey);
      if (raw != null) {
        _profile = UserProfile.fromJson(jsonDecode(raw));
        _status  = AuthStatus.authenticated;
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // 1. Guest login
  // ─────────────────────────────────────────
  Future<bool> loginAsGuest({
    required String displayName,
    required String email,
    String? phone,
  }) async {
    _errorMessage = null;
    try {
      final result = await _api.guestLogin(
        name:  displayName.trim(),
        email: email.trim().toLowerCase(),
        phone: phone?.trim(),
      );
      final token = result['access_token'] as String?;
      if (token != null) {
        await _api.saveToken(token);
        debugPrint('[Auth] Guest JWT saved');
      }
      final profile = UserProfile(
        displayName: displayName.trim(),
        email:       email.trim().toLowerCase(),
        phone:       phone?.trim(),
        authMethod:  AuthMethod.guest,
      );
      await _saveProfile(profile);
      return true;
    } catch (e) {
      debugPrint('[Auth] Guest login error: $e');
      try {
        final profile = UserProfile(
          displayName: displayName.trim(),
          email:       email.trim().toLowerCase(),
          phone:       phone?.trim(),
          authMethod:  AuthMethod.guest,
        );
        await _saveProfile(profile);
        return true;
      } catch (_) {
        _errorMessage = 'Could not save profile. Please try again.';
        notifyListeners();
        return false;
      }
    }
  }

  // ─────────────────────────────────────────
  // 2. Google Sign-In
  // ─────────────────────────────────────────
  Future<bool> loginWithGoogle() async {
    _errorMessage = null;
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;

      // Create backend user + get JWT so registration works
      try {
        final result = await _api.guestLogin(
          name:  account.displayName ?? account.email.split('@').first,
          email: account.email,
        );
        final token = result['access_token'] as String?;
        if (token != null) {
          await _api.saveToken(token);
          debugPrint('[Auth] Google JWT saved');
        }
      } catch (e) {
        debugPrint('[Auth] Google backend login error: $e');
        // Non-fatal - continue with local profile
      }

      final profile = UserProfile(
        displayName: account.displayName ?? account.email.split('@').first,
        email:       account.email,
        avatarUrl:   account.photoUrl,
        authMethod:  AuthMethod.google,
      );
      await _saveProfile(profile);
      return true;
    } on PlatformException catch (e) {
      _errorMessage = e.code == 'sign_in_canceled'
          ? 'Sign-in cancelled.'
          : 'Google sign-in failed. Please try again.';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Google sign-in failed. Please try again.';
      notifyListeners();
      return false;
    }
  }

  // ─────────────────────────────────────────
  // 3. LinkedIn OAuth
  // ─────────────────────────────────────────
  Future<bool> loginWithLinkedIn() async {
    _errorMessage = null;
    try {
      final authUrl     = await _api.getLinkedInAuthUrl();
      final callbackUrl = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: AppConstants.linkedInCallbackScheme,
      );
      final result = await _api.handleLinkedInCallback(callbackUrl);
      final u = result['user'] as Map<String, dynamic>? ?? {};

      final profile = UserProfile(
        displayName: u['name']            as String? ?? '',
        email:       u['email']           as String? ?? '',
        avatarUrl:   u['profile_picture'] as String?,
        authMethod:  AuthMethod.linkedin,
        headline:    u['headline']        as String?,
        linkedInId:  u['linkedin_id']     as String?,
      );
      await _saveProfile(profile);
      return true;
    } on PlatformException catch (e) {
      _errorMessage = (e.code == 'CANCELED' ||
              (e.message ?? '').toLowerCase().contains('cancel'))
          ? 'Sign-in cancelled.'
          : 'LinkedIn sign-in failed. Please try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'LinkedIn sign-in failed. Please try again.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ─────────────────────────────────────────
  // Update profile
  // ─────────────────────────────────────────
  Future<void> updateProfile({
    String? displayName,
    String? phone,
  }) async {
    if (_profile == null) return;
    final updated = UserProfile(
      displayName: displayName ?? _profile!.displayName,
      email:       _profile!.email,
      phone:       phone ?? _profile!.phone,
      avatarUrl:   _profile!.avatarUrl,
      authMethod:  _profile!.authMethod,
      headline:    _profile!.headline,
      linkedInId:  _profile!.linkedInId,
    );
    await _saveProfile(updated);
  }

  Future<void> refreshProfile() async {
    if (_profile?.authMethod != AuthMethod.linkedin) return;
    try {
      final raw = await _api.getMyProfile();
      final updated = UserProfile(
        displayName: raw['name']            as String? ?? _profile!.displayName,
        email:       raw['email']           as String? ?? _profile!.email,
        avatarUrl:   raw['profile_picture'] as String? ?? _profile!.avatarUrl,
        authMethod:  AuthMethod.linkedin,
        headline:    raw['headline']        as String?,
        linkedInId:  raw['linkedin_id']     as String?,
      );
      await _saveProfile(updated);
    } catch (_) {}
  }

  // ─────────────────────────────────────────
  // Logout
  // ─────────────────────────────────────────
  Future<void> logout() async {
    if (_profile?.authMethod == AuthMethod.google) {
      try { await _googleSignIn.signOut(); } catch (_) {}
    }
    await _api.clearToken();
    await _storage.delete(key: _profileKey);
    _profile      = null;
    _errorMessage = null;
    _status       = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ─────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────
  Future<void> _saveProfile(UserProfile profile) async {
    await _storage.write(
      key:   _profileKey,
      value: jsonEncode(profile.toJson()),
    );
    _profile = profile;
    _status  = AuthStatus.authenticated;
    notifyListeners();
  }
}
