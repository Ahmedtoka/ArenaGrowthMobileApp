import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../../../core/widgets/authed_network_image.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/models/message_attachment.dart';
import '../../data/models/message_model.dart';
import 'seen_by_sheet.dart';
import 'video_bubble.dart';
import 'voice_bubble.dart';

/// WhatsApp-style chat bubble.
///
///   - Mine  → right-aligned, blue-tinted background
///   - Theirs → left-aligned, white background
///   - Burst → first message of a sender block shows the name; subsequent
///             ones from the same sender (within 5 min) hide name/avatar
///   - Reply → if [repliedTo] is provided, a quoted preview is shown on top
///   - Image attachments render thumbnails inside the bubble.
///   - File attachments render as a clickable row with icon + name.
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final bool showSenderName;
  final MessageModel? repliedTo;
  /// Tapped the sender's name → open the person actions popup (private chat /
  /// add task). Null for own messages.
  final VoidCallback? onSenderTap;
  final int myUserId;
  final void Function(String emoji)? onToggleReaction;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.showSenderName,
    this.repliedTo,
    this.onSenderTap,
    this.myUserId = 0,
    this.onToggleReaction,
  });

  @override
  Widget build(BuildContext context) {
    // Deleted message → faded, dashed placeholder with the time it was removed.
    if (message.isDeleted) {
      return _DeletedPlaceholder(isMine: isMine, deletedAt: message.deletedAt);
    }

    // Pinned messages get a warm amber tint (plus the red border + badge below)
    // so the pinned state is obvious at a glance, like the desktop.
    final bg = message.isPinned
        ? const Color(0xFFFFF8E1)
        : (isMine ? AppColors.outBubble : Colors.white);
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final accent = _accentForImportance(message.importanceStatus);
    final hasBody = (message.body ?? '').trim().isNotEmpty;
    final hasAttachments = message.attachments.isNotEmpty;
    // A voice-typed message's attachment is always a voice note, even if the
    // server mislabeled its mime (Android AAC-in-MP4 → `video/mp4`). Trust the
    // message type so the inline player renders for old + new recordings.
    final isVoiceMsg = message.type == MessageType.voice;
    final imageAttachments =
        message.attachments.where((a) => a.isImage && !isVoiceMsg).toList();
    final videoAttachments = message.attachments
        .where((a) => a.isVideo && !isVoiceMsg)
        .toList();
    final fileAttachments = message.attachments
        .where((a) => !a.isImage && !a.isVoice && !a.isVideo && !isVoiceMsg)
        .toList();
    final voiceAttachments = isVoiceMsg
        ? message.attachments.toList()
        : message.attachments.where((a) => a.isVoice).toList();

    // For incoming bubbles, attach an avatar to the LEFT — but only on the
    // FIRST message in a burst (the same condition that shows the name).
    // For replies in a thread we still want the avatar to keep the visual
    // anchor consistent.
    final showAvatar = !isMine && showSenderName && message.sender != null;

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMine ? 60 : (showAvatar ? 0 : 40),
          right: isMine ? 8 : 60,
        ),
          padding: EdgeInsets.symmetric(
            horizontal: imageAttachments.isNotEmpty ? 4 : 8,
            vertical: imageAttachments.isNotEmpty ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            // Pinned messages get a strong red border.
            border: message.isPinned
                ? Border.all(color: const Color(0xFFEF4444), width: 1.5)
                : null,
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 1,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Pin badge (top strip) ───────────────────
              if (message.isPinned)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.push_pin, size: 13, color: Color(0xFFEF4444)),
                      SizedBox(width: 3),
                      Text('Pinned',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444),),),
                    ],
                  ),
                ),
              if (showSenderName && !isMine && message.sender != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                  child: GestureDetector(
                    onTap: onSenderTap,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      message.sender!.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _parseHexColor(message.sender!.avatarColor) ??
                            AppColors.arenaBlue,
                      ),
                    ),
                  ),
                ),
              // ── Forwarded label ─────────────────────────
              if ((message.forwardedFrom ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shortcut,
                          size: 13, color: Color(0xFF8696A0),),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Forwarded from ${message.forwardedFrom}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF8696A0),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (repliedTo != null) _ReplyQuote(quoted: repliedTo!),

              // ── Image grid ──────────────────────────────
              for (final att in imageAttachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ImageAttachment(attachment: att),
                ),

              // ── File rows ───────────────────────────────
              // ── Videos ──────────────────────────────────
              for (final att in videoAttachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: VideoBubble(attachment: att),
                ),

              for (final att in fileAttachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _FileAttachment(attachment: att),
                ),

              // ── Voice notes ─────────────────────────────
              for (final att in voiceAttachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: VoiceBubble(
                    attachment: att,
                    message: message,
                    isMine: isMine,
                  ),
                ),

              // ── Body + footer ───────────────────────────
              if (hasBody)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: imageAttachments.isNotEmpty ? 6 : 2,
                  ),
                  // Pure-English / numeric messages render LTR, Arabic
                  // content renders RTL — auto-detected from the first
                  // strong-directional character of the body.
                  child: Directionality(
                    textDirection: detectBidiDirection(message.body),
                    child: Text(
                      message.body!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              // ── Link preview card ───────────────────────
              if (message.linkPreview != null &&
                  ((message.linkPreview!['title'] as String?)?.isNotEmpty == true ||
                      (message.linkPreview!['image'] as String?)?.isNotEmpty == true))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _LinkPreviewCard(preview: message.linkPreview!),
                ),
              if (hasBody || hasAttachments) const SizedBox(height: 2),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: imageAttachments.isNotEmpty ? 6 : 2,
                ),
                child: Align(
                  alignment: AlignmentDirectional.bottomEnd,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isGreen) ...[
                        const Icon(
                          Icons.push_pin,
                          size: 11,
                          color: AppColors.greenBorder,
                        ),
                        const SizedBox(width: 4),
                      ],
                      // Sprint P.2 — "edited" label next to the time when
                      // message.editedAt is set (PATCH /messages/{id}).
                      if (message.editedAt != null) ...[
                        const Text(
                          'edited',
                          style: TextStyle(
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                            color: AppColors.ink3,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '·',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.ink3,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _formatTime(message.createdAt),
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.ink3,
                        ),
                      ),
                      // Read receipt — only on my own real messages.
                      if (isMine && !message.isSystemCard) ...[
                        const SizedBox(width: 4),
                        _SeenIndicator(message: message),
                      ],
                    ],
                  ),
                ),
              ),

              // ── Reaction chips ──────────────────────────
              if (message.reactions.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(
                    top: 4,
                    left: imageAttachments.isNotEmpty ? 6 : 2,
                    right: imageAttachments.isNotEmpty ? 6 : 2,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final entry in message.reactionCounts.entries)
                        GestureDetector(
                          // Tap a reaction → who reacted with it.
                          onTap: () => _showReactors(
                            context,
                            entry.key,
                            message.reactorNames(entry.key),
                          ),
                          behavior: HitTestBehavior.opaque,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(entry.key,
                                  style: const TextStyle(fontSize: 16),),
                              if (entry.value > 1) ...[
                                const SizedBox(width: 2),
                                Text(
                                  '${entry.value}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink3,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

    if (showAvatar) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 60, top: 4, bottom: 2),
        child: Row(
          // start = avatar sits at the TOP of the bubble (WhatsApp / Slack
          // style). `end` was making it slide to the bottom on tall bubbles.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Nudge the avatar down a hair so its centre lines up with the
              // sender name, not with the very top of the bubble shadow.
              padding: const EdgeInsets.only(top: 2),
              child: UserAvatar(
                name: message.sender!.name,
                avatarUrl: message.sender!.avatarUrl,
                size: 32,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(child: bubble),
          ],
        ),
      );
    }

    return Align(alignment: align, child: bubble);
  }

  _ImportanceAccent? _accentForImportance(String status) {
    switch (status) {
      case MessageImportance.red:
        return const _ImportanceAccent(AppColors.redBg, AppColors.redBorder);
      case MessageImportance.orange:
        return const _ImportanceAccent(AppColors.orangeBg, AppColors.orangeBorder);
      case MessageImportance.green:
        return const _ImportanceAccent(AppColors.greenBg, AppColors.greenBorder);
      default:
        return null;
    }
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    return DateFormat('h:mm a').format(t.toLocal());
  }

  /// Small popup listing who reacted with [emoji].
  void _showReactors(BuildContext context, String emoji, List<String> names) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text('${names.length}',
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.ink3,),),
                ],
              ),
            ),
            const Divider(height: 1),
            for (final name in names)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(name, style: const TextStyle(fontSize: 14)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final value = int.tryParse(h, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}

/// Read-receipt ticks shown under my own messages:
///   - single grey ✓  → delivered, nobody has opened it yet
///   - double blue ✓✓ → at least one other member has seen it
/// Tapping opens a sheet listing exactly who has seen it ("Seen by who").
class _SeenIndicator extends ConsumerWidget {
  final MessageModel message;
  const _SeenIndicator({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final someSeen = message.seenByCount > 0;
    final allSeen = message.seenByAll;
    // none → grey single ✓ · some → grey double ✓✓ · all → blue double ✓✓
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => SeenBySheet.show(context, ref, message),
      child: Icon(
        someSeen ? Icons.done_all : Icons.done,
        size: 14,
        color: allSeen ? const Color(0xFF2235FF) : AppColors.ink3,
      ),
    );
  }
}

class _ImportanceAccent {
  final Color bg;
  final Color border;
  const _ImportanceAccent(this.bg, this.border);
}

class _DeletedPlaceholder extends StatelessWidget {
  final bool isMine;
  final DateTime? deletedAt;
  const _DeletedPlaceholder({required this.isMine, this.deletedAt});

  @override
  Widget build(BuildContext context) {
    final time = deletedAt != null
        ? ' · ${DateFormat('h:mm a').format(deletedAt!.toLocal())}'
        : '';
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: 2,
          bottom: 2,
          left: isMine ? 60 : 40,
          right: isMine ? 8 : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.block, size: 13, color: AppColors.ink3),
            const SizedBox(width: 5),
            Text(
              'This message was deleted$time',
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppColors.ink3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline image preview. Tapping opens a full-screen viewer.
class _ImageAttachment extends StatelessWidget {
  final MessageAttachment attachment;
  const _ImageAttachment({required this.attachment});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullScreen(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: 240,
          minHeight: 100,
          minWidth: 180,
        ),
        child: AuthedNetworkImage(
          url: attachment.downloadUrl,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ImageViewer(attachment: attachment),
      ),
    );
  }
}

class _ImageViewer extends ConsumerWidget {
  final MessageAttachment attachment;
  const _ImageViewer({required this.attachment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          attachment.originalName ?? 'Image',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () async {
              try {
                await ref.read(attachmentDownloaderProvider).downloadAndShare(
                      attachment.downloadUrl,
                      filename: attachment.originalName,
                    );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Share failed: $e')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(attachmentDownloaderProvider).downloadAndOpen(
                      attachment.downloadUrl,
                      filename: attachment.originalName,
                      mimeType: attachment.mimeType,
                    );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Download failed: $e')),
                );
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: AuthedNetworkImage(
            url: attachment.downloadUrl,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

/// File chip: icon + filename + size. Tap downloads via authed Dio and
/// opens with the OS default app.
class _FileAttachment extends ConsumerStatefulWidget {
  final MessageAttachment attachment;
  const _FileAttachment({required this.attachment});

  @override
  ConsumerState<_FileAttachment> createState() => _FileAttachmentState();
}

class _FileAttachmentState extends ConsumerState<_FileAttachment> {
  bool _busy = false;

  Future<void> _downloadAndOpen() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndOpen(
            widget.attachment.downloadUrl,
            filename: widget.attachment.originalName,
            mimeType: widget.attachment.mimeType,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open file: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(attachmentDownloaderProvider).downloadAndShare(
            widget.attachment.downloadUrl,
            filename: widget.attachment.originalName,
          );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    return InkWell(
      onTap: _busy ? null : _downloadAndOpen,
      onLongPress: _busy ? null : _share,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.arenaBlue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForMime(att.mimeType),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    att.originalName ?? 'File',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  if (att.sizeBytes != null)
                    Text(
                      _formatSize(att.sizeBytes!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink3,
                      ),
                    ),
                ],
              ),
            ),
            _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, color: AppColors.ink3, size: 18),
          ],
        ),
      ),
    );
  }

  IconData _iconForMime(String? mime) {
    if (mime == null) return Icons.insert_drive_file;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('zip') || mime.contains('rar')) return Icons.archive;
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description;
    }
    if (mime.contains('sheet') || mime.contains('excel')) {
      return Icons.table_chart;
    }
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Small quoted-message chip shown at the top of a bubble that is a reply.
class _ReplyQuote extends StatelessWidget {
  final MessageModel quoted;
  const _ReplyQuote({required this.quoted});

  @override
  Widget build(BuildContext context) {
    final senderName = quoted.sender?.name ?? 'User';
    final body = quoted.body?.trim().isNotEmpty == true
        ? quoted.body!
        : _typeFallback(quoted.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          right: BorderSide(color: AppColors.arenaBlue, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.arenaBlue,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }

  String _typeFallback(String type) {
    return switch (type) {
      MessageType.voice => '🎤 Voice message',
      MessageType.image => '📷 Photo',
      MessageType.file => '📎 File',
      MessageType.poll => '📊 Poll',
      MessageType.taskCard => '✅ Task',
      MessageType.meetingCard => '📅 Meeting',
      _ => '',
    };
  }
}

/// Open Graph link-preview card (title / description / image / site).
class _LinkPreviewCard extends StatelessWidget {
  final Map<String, dynamic> preview;
  const _LinkPreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final image = preview['image'] as String?;
    final title = preview['title'] as String?;
    final desc = preview['description'] as String?;
    final site = preview['site'] as String?;
    final url = preview['url'] as String?;

    return GestureDetector(
      onTap: () async {
        if (url == null) return;
        final uri = Uri.tryParse(url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null && image.isNotEmpty)
              CachedNetworkImage(
                imageUrl: image,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                placeholder: (_, __) => Container(height: 140, color: const Color(0xFFF1F1F1)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (site != null && site.isNotEmpty)
                    Text(site.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.3,
                            color: Color(0xFF8696A0),),),
                  if (title != null && title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111B21),
                              height: 1.25,),),
                    ),
                  if (desc != null && desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF54656F),
                              height: 1.3,),),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
