import 'package:flutter/foundation.dart';
import '../../shared/services/api_client.dart';

// ─────────────────────────────────────────
// MatchResult
// ─────────────────────────────────────────
class MatchResult {
  final String signalId;
  final String eventId;
  final String eventName;
  final String eventDescription;
  final String eventType;
  final String organizerName;
  final DateTime? eventDate;
  final double confidence;
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
    // Safe string extractor - handles String, List, null
    String s(dynamic v, [String fallback = '']) {
      if (v == null) return fallback;
      if (v is String) return v;
      if (v is List) return v.isNotEmpty ? v.first.toString() : fallback;
      return v.toString();
    }

    return MatchResult(
      signalId:         s(json['signal_id']),
      eventId:          s(json['event_id']),
      eventName:        s(json['event_name'],        'Unknown Event'),
      eventDescription: s(json['event_description']),
      eventType:        s(json['event_type'],        'conference'),
      organizerName:    s(json['organizer_name']),
      confidence:       (json['confidence'] as num?)?.toDouble() ?? 0.0,
      eventDate: json['event_date'] != null
          ? DateTime.tryParse(json['event_date'].toString())
          : null,
      raw: json,
    );
  }

  bool get isHighConfidence => confidence >= 0.75;

  String get eventTypeLabel => switch (eventType) {
        'sweepstake' => 'Sweepstake',
        'broadcast'  => 'Broadcast',
        _            => 'Conference',
      };

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

  bool get isMatching        => _isMatching;
  MatchResult? get lastMatch => _lastMatch;
  String? get errorMessage   => _errorMessage;

  /// Send a pre-decoded beacon payload string to the backend.
  Future<Map<String, dynamic>?> matchPayload(String beaconPayload) async {
    if (_isMatching) return null;
    _isMatching = true;
    _errorMessage = null;
    notifyListeners();
    try {
      debugPrint('[MatchService] sending beacon_payload: $beaconPayload');
      final raw = await _api.matchPayload(beaconPayload);
      if (raw == null || raw['matched'] == false) {
        debugPrint('[MatchService] no match: ${raw?['message']}');
        _isMatching = false;
        notifyListeners();
        return null;
      }
      final result = MatchResult.fromJson(raw);
      _lastMatch = result;
      _isMatching = false;
      notifyListeners();
      return result.toArgs();
    } catch (e) {
      debugPrint('[MatchService] matchPayload error: $e');
      _errorMessage = 'Match failed: $e';
      _isMatching = false;
      notifyListeners();
      return null;
    }
  }

  /// Send raw PCM samples to backend for server-side BFSK decode.
  Future<Map<String, dynamic>?> matchSamples(List<double> samples) async {
    if (_isMatching) return null;
    _isMatching = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final raw = await _api.matchSamples(samples);
      if (raw == null || raw['matched'] == false) {
        debugPrint('[MatchService] no match: ${raw?['message']}');
        _isMatching = false;
        notifyListeners();
        return null;
      }
      final result = MatchResult.fromJson(raw);
      _lastMatch = result;
      _isMatching = false;
      notifyListeners();
      return result.toArgs();
    } catch (e) {
      debugPrint('[MatchService] matchSamples error: $e');
      _errorMessage = 'Match failed: $e';
      _isMatching = false;
      notifyListeners();
      return null;
    }
  }

  /// Legacy: send detected frequencies (no longer primary path).
  Future<Map<String, dynamic>?> matchFrequencies(
      List<double> frequencies) async {
    if (_isMatching) return null;
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
      if (!result.isHighConfidence) {
        debugPrint('[MatchService] Low confidence (${result.confidence}) - ignored');
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

  /// Register for the matched event.
  Future<RegistrationResult> register({
    required String eventId,
    required String signalId,
    required String profileType,
  }) async {
    try {
      final raw = await _api.register(
        eventId:     eventId,
        signalId:    signalId,
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
    // Handle error map returned from api_client catch block
    if (json.containsKey('error')) {
      return RegistrationResult(
        success:      false,
        errorMessage: json['error'] as String?,
      );
    }
    return RegistrationResult(
      success:        (json['success'] as bool?) ?? true,
      registrationId: json['id'] as String?,
      message:        json['message'] as String?,
    );
  }

  factory RegistrationResult.error(String msg) => RegistrationResult(
        success:      false,
        errorMessage: msg,
      );
}
