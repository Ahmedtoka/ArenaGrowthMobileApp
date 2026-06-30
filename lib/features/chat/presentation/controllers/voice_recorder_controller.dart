import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// State of an active voice recording.
class VoiceRecordingState {
  final bool isRecording;
  final Duration duration;
  final String? filePath;

  const VoiceRecordingState({
    required this.isRecording,
    required this.duration,
    this.filePath,
  });

  VoiceRecordingState copyWith({
    bool? isRecording,
    Duration? duration,
    String? filePath,
  }) {
    return VoiceRecordingState(
      isRecording: isRecording ?? this.isRecording,
      duration: duration ?? this.duration,
      filePath: filePath ?? this.filePath,
    );
  }

  static const idle = VoiceRecordingState(
    isRecording: false,
    duration: Duration.zero,
  );
}

/// Wraps the `record` plugin so the composer can start/stop/cancel a
/// hold-to-record interaction.
///
/// One recorder instance per composer; recreated on each new chat screen.
class VoiceRecorder extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _ticker;
  Stopwatch? _stopwatch;
  VoiceRecordingState _state = VoiceRecordingState.idle;

  VoiceRecordingState get state => _state;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begin recording. Returns false if mic permission is denied.
  Future<bool> start() async {
    if (_state.isRecording) return true;
    final granted = await _recorder.hasPermission();
    if (!granted) return false;

    final dir = await getTemporaryDirectory();
    final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final path = p.join(dir.path, filename);

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _state = _state.copyWith(duration: _stopwatch!.elapsed);
      notifyListeners();
    });

    _state = VoiceRecordingState(
      isRecording: true,
      duration: Duration.zero,
      filePath: path,
    );
    notifyListeners();
    return true;
  }

  /// Stop recording. Returns the recorded file + duration, or null if
  /// recording was too short (<400ms) and discarded.
  Future<({File file, Duration duration})?> stop() async {
    if (!_state.isRecording) return null;
    _ticker?.cancel();
    _ticker = null;
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;
    _stopwatch?.stop();
    _stopwatch = null;

    final path = await _recorder.stop();
    final wasState = _state;
    _state = VoiceRecordingState.idle;
    notifyListeners();

    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    // Drop micro-recordings (likely accidental taps).
    if (elapsed < const Duration(milliseconds: 400)) {
      await file.delete().catchError((_) => file);
      return null;
    }

    return (file: file, duration: elapsed);
  }

  /// Cancel without producing a result (deletes the partial file).
  Future<void> cancel() async {
    if (!_state.isRecording) return;
    _ticker?.cancel();
    _ticker = null;
    _stopwatch?.stop();
    _stopwatch = null;

    final path = await _recorder.stop();
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }
    }
    _state = VoiceRecordingState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch?.stop();
    _recorder.dispose();
    super.dispose();
  }
}
