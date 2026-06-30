import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/message_model.dart';

/// Actions the user picks from the long-press bottom sheet.
enum MessageAction {
  reply,
  createTask,
  pin,
  markRed,
  markGreen,
  revert,
  copy,
  share, // Sprint Q.1 — share through the native share sheet
  edit, // Sprint P.2 — edit own message body
  seenBy, // who has seen this message + when
  delete,
}

/// WhatsApp-style quick reactions shown at the top of the long-press sheet.
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Long-press action sheet for a message bubble.
///
/// The set of actions adapts to the message state:
///   - Mark Red is hidden if already red
///   - Mark Green is hidden if already green
///   - Revert only appears if currently red / orange / green
///   - Copy only appears if there's a non-empty body
class MessageActionsSheet extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final int myUserId;
  final void Function(String emoji)? onReact;

  const MessageActionsSheet({
    super.key,
    required this.message,
    required this.isMine,
    this.myUserId = 0,
    this.onReact,
  });

  /// Convenience: shows the sheet and resolves to the picked action (or null
  /// if the user dismissed it). Tapping a quick-reaction fires [onReact] and
  /// dismisses without returning an action.
  static Future<MessageAction?> show(
    BuildContext context, {
    required MessageModel message,
    required bool isMine,
    int myUserId = 0,
    void Function(String emoji)? onReact,
  }) {
    return showModalBottomSheet<MessageAction>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => MessageActionsSheet(
        message: message,
        isMine: isMine,
        myUserId: myUserId,
        onReact: onReact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasBody = (message.body ?? '').trim().isNotEmpty;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.ink3.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ── Quick reactions row (WhatsApp-style) ─────────
          if (!message.isSystemCard && onReact != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final emoji in kQuickReactions)
                    _ReactionButton(
                      emoji: emoji,
                      active: message.didReact(emoji, myUserId),
                      onTap: () {
                        onReact!(emoji);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          if (!message.isSystemCard && onReact != null)
            const Divider(height: 1),

          // ── Reply ────────────────────────────────────────
          _ActionTile(
            icon: Icons.reply,
            label: 'Reply',
            onTap: () => Navigator.pop(context, MessageAction.reply),
          ),

          // ── Pin ──────────────────────────────────────────
          if (!message.isSystemCard)
            _ActionTile(
              icon: Icons.push_pin_outlined,
              label: 'Pin / Unpin',
              onTap: () => Navigator.pop(context, MessageAction.pin),
            ),

          // ── Add Task ─────────────────────────────────────
          if (hasBody)
            _ActionTile(
              icon: Icons.add_task,
              label: 'Add task',
              iconColor: AppColors.arenaBlue,
              onTap: () => Navigator.pop(context, MessageAction.createTask),
            ),

          // ── Copy ─────────────────────────────────────────
          if (hasBody)
            _ActionTile(
              icon: Icons.copy,
              label: 'Copy text',
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: message.body!));
                if (context.mounted) {
                  Navigator.pop(context, MessageAction.copy);
                }
              },
            ),

          // ── Share (Sprint Q.1) — text, image, file, voice ─
          if (!message.isSystemCard)
            _ActionTile(
              icon: Icons.share,
              label: 'Share via…',
              iconColor: AppColors.arenaBlue,
              onTap: () => Navigator.pop(context, MessageAction.share),
            ),

          // ── Seen by (my own non-system messages) ─────────
          if (isMine && !message.isSystemCard)
            _ActionTile(
              icon: Icons.done_all,
              label: 'Seen by',
              iconColor: const Color(0xFF2235FF),
              onTap: () => Navigator.pop(context, MessageAction.seenBy),
            ),

          // ── Edit (own messages only, no system cards) ────
          if (isMine && hasBody && !message.isSystemCard)
            _ActionTile(
              icon: Icons.edit,
              label: 'Edit message',
              onTap: () => Navigator.pop(context, MessageAction.edit),
            ),

          // ── Delete (own messages only) ───────────────────
          if (isMine)
            _ActionTile(
              icon: Icons.delete_outline,
              label: 'Delete message',
              iconColor: AppColors.arenaRed,
              onTap: () => Navigator.pop(context, MessageAction.delete),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.ink2),
      title: Text(
        label,
        style: const TextStyle(fontSize: 15, color: AppColors.ink),
      ),
      onTap: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ReactionButton extends StatelessWidget {
  final String emoji;
  final bool active;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? AppColors.arenaBlue.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}
