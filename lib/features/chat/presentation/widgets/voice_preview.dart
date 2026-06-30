import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// WhatsApp-style preview pill shown after the user finishes a recording but
/// before sending. They can play it back, delete (discard), or send.
class VoicePreview extends StatefulWidget {
  final File file;
  final Duration duration;
  final VoidCallback onDelete;
  final VoidCallback onSend;
  final bool sending;

  const VoicePreview({
    super.key,
    required this.file,
    required this.duration,
    required this.onDelete,
    required this.onSend,
    this.sending = false,
  });

  @override
  State<VoicePreview> createState() => _VoicePreviewState();
}

class _VoicePreviewState extends State<VoicePreview> {
  late final AudioPlayer _player;
  bool _playing = false;
  Duration _pos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _pos = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(DeviceFileSource(widget.file.path));
    }
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds == 0
        ? 0.0
        : _pos.inMilliseconds / widget.duration.inMilliseconds;
    final shown = _playing || _pos > Duration.zero ? _pos : widget.duration;

    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.appBg,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppColors.arenaRed,
              tooltip: 'Delete recording',
              onPressed: widget.sending ? null : widget.onDelete,
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: widget.sending ? null : _toggle,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: AppColors.arenaBlue,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 4,
                            child: LinearProgressIndicator(
                              value: progress.clamp(0.0, 1.0),
                              backgroundColor:
                                  AppColors.ink3.withValues(alpha: 0.2),
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.arenaBlue,),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.mic,
                                  size: 12, color: AppColors.ink3,),
                              const SizedBox(width: 4),
                              Text(
                                _fmt(shown),
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.ink3,),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: AppColors.arenaBlue,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.sending ? null : widget.onSend,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: widget.sending
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
