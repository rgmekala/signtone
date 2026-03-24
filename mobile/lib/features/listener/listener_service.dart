import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants.dart';
import '../matching/match_service.dart';
import '../../shared/services/siri_service.dart';

// ─────────────────────────────────────────
// Listener States
// ─────────────────────────────────────────
enum ListenerState { idle, listening, detecting, matched, error }

// ─────────────────────────────────────────
// ListenerService
// ─────────────────────────────────────────
class ListenerService extends ChangeNotifier {
  final _recorder = AudioRecorder();
  final _matcher  = MatchService();

  ListenerState _state = ListenerState.idle;
  Map<String, dynamic>? _matchData;
  String? _errorMessage;

  StreamSubscription<Uint8List>? _audioSub;
  final List<int>    _audioBuffer   = [];
  final List<double> _collectBuffer = [];

  // Sliding window config
  // Window must be > beacon duration (5.92s for EVT001)
  // Step = how often we send to backend
  static const _windowMs = 8000;
  static const _stepMs   = 2000;

  int get _windowSamples => (AppConstants.sampleRateHz * _windowMs / 1000).round();
  int get _stepSamples   => (AppConstants.sampleRateHz * _stepMs   / 1000).round();

  int  _samplesSinceLastSend = 0;
  bool _isSending            = false;

  // chunk size in bytes = duration * sampleRate * 2 bytes (16-bit PCM)
  int get _chunkBytes =>
      (AppConstants.audioChunkDurationMs / 1000 *
              AppConstants.sampleRateHz *
              2)
          .round();

  // ─────────────────────────────────────────
  // Getters
  // ─────────────────────────────────────────
  ListenerState get state             => _state;
  Map<String, dynamic>? get matchData => _matchData;
  String? get errorMessage            => _errorMessage;
  bool get isListening =>
      _state == ListenerState.listening ||
      _state == ListenerState.detecting;

  // ─────────────────────────────────────────
  // Start
  // ─────────────────────────────────────────
  Future<void> start() async {
    var status = await Permission.microphone.status;
    print('[Mic] Current status: $status');

    if (status.isDenied || status.isRestricted) {
      status = await Permission.microphone.request();
      print('[Mic] After request: $status');
    }

    if (status.isPermanentlyDenied) {
      _setState(ListenerState.error);
      _errorMessage = 'Microphone access denied. Please enable it in Settings.';
      await openAppSettings();
      return;
    }

    if (!status.isGranted) {
      _setState(ListenerState.error);
      _errorMessage = 'Microphone permission denied.';
      return;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: AppConstants.sampleRateHz,
          numChannels: 1,
        ),
      );

      _audioBuffer.clear();
      _collectBuffer.clear();
      _samplesSinceLastSend = 0;
      _isSending            = false;
      _setState(ListenerState.listening);

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
    _collectBuffer.clear();
    _samplesSinceLastSend = 0;
    _isSending            = false;
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
    if (_audioBuffer.length < _chunkBytes) return;

    final chunk = Uint8List.fromList(_audioBuffer.sublist(0, _chunkBytes));
    _audioBuffer.removeRange(0, _chunkBytes);
    _processChunk(chunk);
  }

  // ─────────────────────────────────────────
  // Chunk processor - sliding window
  // ─────────────────────────────────────────
  // Keeps a rolling 8s buffer of audio.
  // Every 2s sends the full buffer to backend.
  // Beacon is always fully captured regardless
  // of when it starts relative to our window.
  // ─────────────────────────────────────────
  Future<void> _processChunk(Uint8List chunk) async {
    final samples = _pcmToFloat(chunk);
    final energy  = _rmsEnergy(samples);
    debugPrint('[Listener] chunk received, energy: $energy, freqs checked');

    // Accumulate into rolling buffer
    _collectBuffer.addAll(samples);
    _samplesSinceLastSend += samples.length;

    // Trim buffer to window size
    if (_collectBuffer.length > _windowSamples) {
      _collectBuffer.removeRange(0, _collectBuffer.length - _windowSamples);
    }

    // Send every _stepMs, only when buffer is full, only when not already sending
    if (_samplesSinceLastSend < _stepSamples) return;
    if (_collectBuffer.length < _windowSamples) return;
    if (_isSending) return;

    _samplesSinceLastSend = 0;

    // Skip quiet windows
    final rms = _rmsEnergy(_collectBuffer);
    debugPrint('[Listener] window rms: $rms (${_collectBuffer.length} samples)');
    if (rms < 0.0005) {
      debugPrint('[Listener] window too quiet, skipping');
      return;
    }

    final toSend = List<double>.from(_collectBuffer);
    debugPrint('[Listener] sending ${toSend.length} samples to backend');

    _isSending = true;
    _setState(ListenerState.detecting);

    final result = await _matcher.matchSamples(toSend);
    _isSending = false;
     
     if (result != null) {
        _matchData = result;
        _setState(ListenerState.matched);
        await _audioSub?.cancel();
        _audioSub = null;
        await _recorder.pause();

        // Donate to Siri so it learns the pattern and shows suggestions
        SiriService().donateBeacon(
        );
           eventName:     result['event_name']?.toString()     ?? '',
           eventId:       result['event_id']?.toString()       ?? '',
           beaconPayload: result['beacon_payload']?.toString() ?? '',
     }
     else {
      if (_state == ListenerState.detecting) {
        _setState(ListenerState.listening);
      }
    }
  }

  // ─────────────────────────────────────────
  // Signal processing helpers
  // ─────────────────────────────────────────

  List<double> _pcmToFloat(Uint8List bytes) {
    final samples = <double>[];
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < bytes.length - 1; i += 2) {
      final sample = data.getInt16(i, Endian.little);
      samples.add(sample / 32768.0);
    }
    return samples;
  }

  double _rmsEnergy(List<double> samples) {
    if (samples.isEmpty) return 0;
    final sum = samples.fold(0.0, (acc, s) => acc + s * s);
    return sum / samples.length;
  }

  double _dbToLinear(double db) => pow10(db / 20.0);

  double pow10(double x) => x == 0 ? 1.0 : _exp10(x);

  double _exp10(double x) {
    const ln10 = 2.302585092994046;
    return _exp(x * ln10);
  }

  double _exp(double x) {
    double result = 1.0, term = 1.0;
    for (var i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }

  double _goertzel(List<double> samples, double targetFreq) {
    final n     = samples.length;
    final k     = (n * targetFreq / AppConstants.sampleRateHz).round();
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
    x = x % (2 * 3.141592653589793);
    double result = 1.0, term = 1.0;
    for (var i = 1; i <= 8; i++) {
      term *= -x * x / ((2 * i - 1) * (2 * i));
      result += term;
    }
    return result;
  }

  // ─────────────────────────────────────────
  // Error / state helpers
  // ─────────────────────────────────────────
  void _onAudioError(Object error) {
    _errorMessage = error.toString();
    _setState(ListenerState.error);
  }

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
