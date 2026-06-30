import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/models/message_attachment.dart';

/// In-chat video — shows a thumbnail with a play button; tapping opens a
/// fullscreen player (WhatsApp-style). The video streams from the authed
/// attachment URL with the bearer token attached.
class VideoBubble extends ConsumerWidget {
  final MessageAttachment attachment;
  const VideoBubble({super.key, required this.attachment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final token = await ref.read(secureStorageProvider).getToken();
        if (!context.mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FullscreenVideo(
            url: attachment.downloadUrl,
            token: token,
          ),
        ),);
      },
      child: Container(
        width: 240,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.movie_creation_outlined,
                color: Colors.white24, size: 48,),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 13),
                    const SizedBox(width: 3),
                    Text(
                      _sizeLabel(attachment.sizeBytes),
                      style: const TextStyle(color: Colors.white, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null) return 'Video';
    if (bytes > 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }
}

class _FullscreenVideo extends StatefulWidget {
  final String url;
  final String? token;
  const _FullscreenVideo({required this.url, this.token});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _vp;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _vp = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: {
          if (widget.token != null) 'Authorization': 'Bearer ${widget.token}',
        },
      );
      await _vp!.initialize();
      _chewie = ChewieController(
        videoPlayerController: _vp!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        aspectRatio: _vp!.value.aspectRatio,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _vp?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not play this video.\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),),
              )
            : _chewie != null
                ? Chewie(controller: _chewie!)
                : const CircularProgressIndicator(color: AppColors.teal),
      ),
    );
  }
}
