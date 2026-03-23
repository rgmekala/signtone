import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants.dart';
import '../matching/match_service.dart';

// ─────────────────────────────────────────
// Listener States
// ─────────────────────────────────────────
enum ListenerState { idle, listening, detecting, matched, error }

// ─────────────────────────────────────────
// ListenerService
// ─────────────────────────────────────────
class ListenerService extends ChangeNotifier {
  final _recorder  = AudioRecorder();
  final _matcher   = MatchService();

  ListenerState _state     = ListenerState.idle;
  Map<String, dynamic>? _matchData;
  String? _errorMessage;

  StreamSubscription<Uint8List>? _audioSub;
  final List<int> _audioBuffer = [];

  // chunk size in bytes = duration * sampleRate * 2 bytes (16-bit PCM)
  int get _chunkBytes =>
      (AppConstants.audioChunkDurationMs / 1000 *
              AppConstants.sampleRateHz *
              2)
          .round();

  // ─────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────
  ListenerState get state        => _state;
  Map<String, dynamic>? get matchData => _matchData;
  String? get errorMessage       => _errorMessage;
  bool get isListening =>
      _state == ListenerState.listening ||
      _state == ListenerState.detecting;

  // ─────────────────────────────────────────
  // Start
  // ─────────────────────────────────────────
  Future<void> start() async {
    // 1. Check / request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _setState(ListenerState.error);
      _errorMessage = status.isPermanentlyDenied
          ? 'Microphone access denied. Please enable it in Settings.'
          : 'Microphone permission denied.';
      return;
    }

    try {
      // 2. Start raw PCM stream directly - skip hasPermission() check
      //    which can fail on simulator even when permission is granted
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AppConstants.sampleRateHz,
          numChannels: 1,
        ),
      );

      _audioBuffer.clear();
      _setState(ListenerState.listening);

      // 4. Accumulate bytes → process every chunkBytes
      _audioSub = stream.listen(
        _onAudioData,
        onError: _onAudioError,
        cancelOnError: false,
      );
    } catch (e) {
      _setState(ListenerState.error);
      _errorMessage = 'Failed to start microphone: $e';
    }
  }

  // ─────────────────────────────────────────
  // Stop
  // ─────────────────────────────────────────
  Future<void> stop() async {
    await _audioSub?.cancel();
    _audioSub = null;
    await _recorder.stop();
    _audioBuffer.clear();
    _matchData = null;
    _setState(ListenerState.idle);
  }

  // ─────────────────────────────────────────
  // Reset after confirmation screen dismissed
  // ─────────────────────────────────────────
  Future<void> resetAndResume() async {
    _matchData = null;
    await stop();
    await start();
  }

  // ─────────────────────────────────────────
  // Audio data handler
  // ─────────────────────────────────────────
  void _onAudioData(Uint8List bytes) {
    _audioBuffer.addAll(bytes);

    // Wait until we have a full chunk before processing
    if (_audioBuffer.length < _chunkBytes) return;

    final chunk = Uint8List.fromList(
      _audioBuffer.sublist(0, _chunkBytes),
    );
    _audioBuffer.removeRange(0, _chunkBytes);

    _processChunk(chunk);
  }

  Future<void> _processChunk(Uint8List chunk) async {
    // 1. Convert raw PCM bytes → normalized float samples [-1.0, 1.0]
    final samples = _pcmToFloat(chunk);

    // 2. Quick energy gate - skip silent frames to save API calls
    final energy = _rmsEnergy(samples);
    if (energy < _dbToLinear(AppConstants.signalThresholdDb)) return;

    // 3. Detect dominant frequencies in the beacon band (18-20 kHz)
    final freqs = _detectBeaconFrequencies(samples);
    if (freqs.isEmpty) return;

    // 4. Transition to detecting and call the match API
    _setState(ListenerState.detecting);

    final result = await _matcher.matchFrequencies(freqs);

    if (result != null) {
      _matchData = result;
      _setState(ListenerState.matched);
      // Pause recording while user is on confirmation screen
      await _audioSub?.cancel();
      _audioSub = null;
      await _recorder.pause();
    } else {
      // No match - go back to listening
      if (_state == ListenerState.detecting) {
        _setState(ListenerState.listening);
      }
    }
  }

  // ─────────────────────────────────────────
  // Signal processing helpers
  // ─────────────────────────────────────────

  /// Convert 16-bit little-endian PCM bytes → float32 samples.
  List<double> _pcmToFloat(Uint8List bytes) {
    final samples = <double>[];
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final sample = data.getInt16(i, Endian.little);
      samples.add(sample / 32768.0);
    }
    return samples;
  }

  /// RMS energy of a sample window.
  double _rmsEnergy(List<double> samples) {
    if (samples.isEmpty) return 0;
    final sum = samples.fold(0.0, (acc, s) => acc + s * s);
    return (sum / samples.length) < 0 ? 0 : (sum / samples.length);
  }

  /// Convert dB threshold to linear amplitude.
  double _dbToLinear(double db) => pow10(db / 20.0);

  double pow10(double x) {
    // Simple 10^x without dart:math import
    return x == 0 ? 1.0 : _exp10(x);
  }

  double _exp10(double x) {
    // 10^x = e^(x * ln10), ln10 ≈ 2.302585
    const ln10 = 2.302585092994046;
    return _exp(x * ln10);
  }

  // Taylor series e^x - accurate enough for our threshold range
  double _exp(double x) {
    double result = 1.0, term = 1.0;
    for (var i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  /// Goertzel algorithm - efficient single-frequency detector.
  /// Much lighter than a full FFT for just two target frequencies.
  double _goertzel(List<double> samples, double targetFreq) {
    final n = samples.length;
    final k = (n * targetFreq / AppConstants.sampleRateHz).round();
    final omega = 2.0 * 3.141592653589793 * k / n;
    final coeff = 2.0 * _cos(omega);

    double s0 = 0, s1 = 0, s2 = 0;
    for (final sample in samples) {
      s0 = sample + coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }
    return s1 * s1 + s2 * s2 - coeff * s1 * s2;
  }

  double _cos(double x) {
    // Taylor series cos(x) - sufficient for Goertzel coefficient
    x = x % (2 * 3.141592653589793);
    double result = 1.0, term = 1.0;
    for (var i = 1; i <= 8; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  /// Returns list of beacon frequencies that exceed the detection threshold.
  List<double> _detectBeaconFrequencies(List<double> samples) {
    final detected = <double>[];
    const minPower = 0.001; // tunable - reduce if misses, raise if false positives

    final targets = [
      AppConstants.beaconFreqLow,
      AppConstants.beaconFreqHigh,
    ];

    for (final freq in targets) {
      final power = _goertzel(samples, freq);
      if (power > minPower) detected.add(freq);
    }

    return detected;
  }

  // ─────────────────────────────────────────
  // Error handler
  // ─────────────────────────────────────────
  void _onAudioError(Object error) {
    _errorMessage = error.toString();
    _setState(ListenerState.error);
  }

  // ─────────────────────────────────────────
  // State helper
  // ─────────────────────────────────────────
  void _setState(ListenerState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
