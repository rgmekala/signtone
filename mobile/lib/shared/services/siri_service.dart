import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SiriService {
  static const _channel = MethodChannel('com.signtone.mobile/siri');

  static final SiriService _instance = SiriService._internal();
  factory SiriService() => _instance;
  SiriService._internal();

  // ── Request Siri permission ───────────────────────────────────────────────

  Future<bool> requestPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestSiriPermission');
      debugPrint('[Siri] Permission granted: $granted');
      return granted ?? false;
    } catch (e) {
      debugPrint('[Siri] Permission request error: $e');
      return false;
    }
  }

  // ── Donate beacon shortcut ────────────────────────────────────────────────
  // Called when a beacon is detected - teaches Siri the pattern
  // and surfaces a lock-screen suggestion

  Future<void> donateBeacon({
    required String eventName,
    required String eventId,
    required String beaconPayload,
  }) async {
    try {
      await _channel.invokeMethod('donateBeacon', {
        'event_name':     eventName,
        'event_id':       eventId,
        'beacon_payload': beaconPayload,
      });
      debugPrint('[Siri] Donated beacon for: $eventName');
    } catch (e) {
      debugPrint('[Siri] Donation error: $e');
      // Non-fatal - Siri integration is best-effort
    }
  }
}
