import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/message_attachment.dart';
import '../../data/models/message_model.dart';
import '../controllers/chat_providers.dart';

/// Voice message bubble — play/pause + progress + duration.
///
/// audioplayers ^6.x can't attach Bearer headers to a streaming URL on
/// Android, so we pre-download the file with the authed Dio client and
/// play it from a local temp file. Cached per attachment id between
/// playbacks for the lifetime of the cache dir.
class VoiceBubble extends ConsumerStatefulWidget {
  final MessageAttachment attachment;
  final MessageModel message;
  final bool isMine;

  const VoiceBubble({
    super.key,
    required this.attachment,
    required this.message,
    required this.isMine,
  });

  @override
  ConsumerState<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends ConsumerState<VoiceBubble> {
  late final AudioPlayer _player;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  String? _localPath;
  bool _playRecorded = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      // Some codecs (notably WebM/Opus from the web recorder) emit a bogus
      // zero duration before metadata loads. Ignore those so they don't wipe
      // the real duration (from payload) and freeze the progress bar at 0.
      if (mounted && d > Duration.zero) setState(() => _total = d);
    });
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });

    final ms = widget.message.payload?['duration_ms'];
    if (ms is int && ms > 0) {
      _total = Duration(milliseconds: ms);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<String> _ensureLocalFile() async {
    if (_localPath != null && await File(_localPath!).exists()) {
      return _localPath!;
    }
    final dir = await getTemporaryDirectory();
    final ext = _extFromMime(widget.attachment.mimeType) ?? 'm4a';
    final localPath =
        p.join(dir.path, 'voice_${widget.attachment.id}.$ext');
    final f = File(localPath);
    if (!await f.exists()) {
      final client = ref.read(dioClientProvider);
      final res = await client.dio.get<List<int>>(
        widget.attachment.downloadUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': '*/*'},
        ),
      );
      await f.writeAsBytes(res.data ?? const <int>[]);
    }
    _localPath = localPath;
    return localPath;
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() => _loading = true);
    try {
      final path = await _ensureLocalFile();
      await _player.play(DeviceFileSource(path));
      // Record a play receipt once — only for OTHER people's voice notes.
      if (!widget.isMine && !_playRecorded) {
        _playRecorded = true;
        ref
            .read(chatRepositoryProvider)
            .markPlayed(widget.message.id)
            .catchError((_) {});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not play audio: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _extFromMime(String? mime) {
    if (mime == null) return null;
    if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
      return 'm4a';
    }
    if (mime.contains('mpeg')) return 'mp3';
    if (mime.contains('ogg')) return 'ogg';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('wav')) return 'wav';
    return 'm4a';
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / _total.inMilliseconds;
    final iconColor =
        widget.isMine ? AppColors.arenaBlueDark : AppColors.arenaBlue;
    final shownDuration =
        _playing || _position > Duration.zero ? _position : _total;

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _loading ? null : _toggle,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    )
                  : Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 22,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    backgroundColor: AppColors.ink3.withValues(alpha: 0.25),
                    valueColor: AlwaysStoppedAnimation(iconColor),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.mic, size: 12, color: AppColors.ink3),
                    const SizedBox(width: 4),
                    Text(
                      _fmt(shownDuration),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

