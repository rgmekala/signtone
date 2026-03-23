import 'package:flutter/foundation.dart';
import '../../shared/services/api_client.dart';

// ─────────────────────────────────────────
// MatchResult - typed wrapper around
// the raw API response
// ─────────────────────────────────────────
class MatchResult {
  final String signalId;
  final String eventId;
  final String eventName;
  final String eventDescription;
  final String eventType;      // 'conference' | 'sweepstake' | 'broadcast'
  final String organizerName;
  final DateTime? eventDate;
  final double confidence;     // 0.0 - 1.0 from vector search score
  final Map<String, dynamic> raw;

  const MatchResult({
    required this.signalId,
    required this.eventId,
    required this.eventName,
    required this.eventDescription,
    required this.eventType,
    required this.organizerName,
    this.eventDate,
    required this.confidence,
    required this.raw,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      signalId:         json['signal_id']         as String? ?? '',
      eventId:          json['event_id']           as String? ?? '',
      eventName:        json['event_name']         as String? ?? 'Unknown Event',
      eventDescription: json['event_description'] as String? ?? '',
      eventType:        json['event_type']         as String? ?? 'conference',
      organizerName:    json['organizer_name']     as String? ?? '',
      confidence:       (json['confidence'] as num?)?.toDouble() ?? 0.0,
      eventDate: json['event_date'] != null
          ? DateTime.tryParse(json['event_date'] as String)
          : null,
      raw: json,
    );
  }

  /// True if the match score is strong enough to show a confirmation.
  bool get isHighConfidence => confidence >= 0.75;

  /// Human-readable event type label.
  String get eventTypeLabel => switch (eventType) {
        'sweepstake' => 'Sweepstake',
        'broadcast'  => 'Broadcast',
        _            => 'Conference',
      };

  /// Icon name hint for the UI layer.
  String get eventTypeIcon => switch (eventType) {
        'sweepstake' => 'emoji_events_rounded',
        'broadcast'  => 'radio_rounded',
        _            => 'business_center_rounded',
      };

  Map<String, dynamic> toArgs() => raw;
}

// ─────────────────────────────────────────
// MatchService
// ─────────────────────────────────────────
class MatchService extends ChangeNotifier {
  final _api = ApiClient();

  bool _isMatching = false;
  MatchResult? _lastMatch;
  String? _errorMessage;

  bool get isMatching       => _isMatching;
  MatchResult? get lastMatch => _lastMatch;
  String? get errorMessage  => _errorMessage;

  // ─────────────────────────────────────────
  // Core match call
  // ─────────────────────────────────────────

  /// Send detected frequencies to the backend.
  /// Returns a [MatchResult] on success, null if no match.
  Future<Map<String, dynamic>?> matchFrequencies(
      List<double> frequencies) async {
    if (_isMatching) return null; // debounce concurrent calls

    _isMatching = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _api.matchSignal(frequencies);
      if (raw == null) {
        _isMatching = false;
        notifyListeners();
        return null;
      }

      final result = MatchResult.fromJson(raw);

      // Only accept high-confidence matches
      if (!result.isHighConfidence) {
        debugPrint(
            '[MatchService] Low confidence (${result.confidence}) - ignored');
        _isMatching = false;
        notifyListeners();
        return null;
      }

      _lastMatch = result;
      _isMatching = false;
      notifyListeners();
      return result.toArgs();
    } catch (e) {
      _errorMessage = 'Match failed: $e';
      _isMatching = false;
      notifyListeners();
      return null;
    }
  }

  // ─────────────────────────────────────────
  // Register for the matched event
  // ─────────────────────────────────────────

  /// Called from ConfirmCard when the user taps "Register".
  /// [profileType] - 'professional' | 'public'
  Future<RegistrationResult> register({
    required String eventId,
    required String signalId,
    required String profileType,
  }) async {
    try {
      final raw = await _api.register(
        eventId: eventId,
        signalId: signalId,
        profileType: profileType,
      );
      return RegistrationResult.fromJson(raw);
    } catch (e) {
      return RegistrationResult.error(e.toString());
    }
  }

  void clearLastMatch() {
    _lastMatch = null;
    notifyListeners();
  }
}

// ─────────────────────────────────────────
// RegistrationResult
// ─────────────────────────────────────────
class RegistrationResult {
  final bool success;
  final String? registrationId;
  final String? message;
  final String? errorMessage;

  const RegistrationResult({
    required this.success,
    this.registrationId,
    this.message,
    this.errorMessage,
  });

  factory RegistrationResult.fromJson(Map<String, dynamic> json) {
    return RegistrationResult(
      success:        (json['success'] as bool?) ?? true,
      registrationId: json['registration_id'] as String?,
      message:        json['message'] as String?,
    );
  }

  factory RegistrationResult.error(String msg) => RegistrationResult(
        success: false,
        errorMessage: msg,
      );
}
