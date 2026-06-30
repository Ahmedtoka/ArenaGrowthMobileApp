import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/message_model.dart';

/// WhatsApp-style reply banner that appears above the composer while the user
/// is composing a reply. Shows the original message in a gray rounded box
/// with a colored left rail, sender name, body, and a Show more / less toggle
/// for long messages (Sprint K).
class ReplyBanner extends StatefulWidget {
  final MessageModel replyingTo;
  final VoidCallback onCancel;

  const ReplyBanner({
    super.key,
    required this.replyingTo,
    required this.onCancel,
  });

  @override
  State<ReplyBanner> createState() => _ReplyBannerState();
}

class _ReplyBannerState extends State<ReplyBanner> {
  static const int _previewLimit = 120;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final senderName = widget.replyingTo.sender?.name ?? 'User';
    final body =
        (widget.replyingTo.body ?? _typeFallback(widget.replyingTo.type)).trim();
    final isLong = body.length > _previewLimit;
    final shownBody =
        (!isLong || _expanded) ? body : '${body.substring(0, _previewLimit)}…';

    return Container(
      color: AppColors.appBg,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: const Border(
              // Left rail — WhatsApp convention for reply previews.
              left: BorderSide(color: AppColors.arenaBlue, width: 4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.reply,
                            size: 12, color: AppColors.arenaBlue,),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            senderName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.arenaBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shownBody,
                      maxLines: _expanded ? 8 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: AppColors.ink2,
                      ),
                    ),
                    if (isLong)
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _expanded ? 'Show less' : 'Show more',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.arenaBlue,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.ink3,
                onPressed: widget.onCancel,
                tooltip: 'Cancel reply',
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
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
