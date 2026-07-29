import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/text_direction_util.dart';
import '../../data/models/brand_group_model.dart';
import '../controllers/groups_controller.dart';
import '../controllers/typing_controller.dart';

class ChatsListTab extends ConsumerWidget {
  const ChatsListTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsControllerProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(groupsControllerProvider.notifier).refresh(),
      child: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) {
          final msg = e.toString().toLowerCase();
          final isConnIssue = msg.contains('connection') ||
              msg.contains('socket') ||
              msg.contains('timeout') ||
              msg.contains('could not');
          return ListView(
            children: [
              const SizedBox(height: 80),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        isConnIssue ? Icons.wifi_off : Icons.error_outline,
                        size: 56,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isConnIssue
                            ? 'Could not connect to the server'
                            : 'Error loading chats',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      if (isConnIssue)
                        Text(
                          'Make sure the server is running',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        Text(
                          e.toString(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => ref
                            .read(groupsControllerProvider.notifier)
                            .refresh(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
        data: (groups) {
          if (groups.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.chat_outlined, size: 56, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('No chats yet'),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              indent: 76,
              color: AppColors.divider,
            ),
            itemBuilder: (ctx, i) => _GroupRow(group: groups[i]),
          );
        },
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  final BrandGroupModel group;

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandColor = _parseHexColor(group.brand?.primaryColor) ?? AppColors.teal;
    final lastMessage = group.lastMessage;
    // Watch typing for THIS group so the preview swaps to "X is typing..." live.
    final typing = ref.watch(typingControllerProvider(group.id));
    final preview = typing.hasAny
        ? _typingPreview(typing.names)
        : _previewText(lastMessage);
    final time = lastMessage?.createdAt ?? group.lastMessageAt;
    final unread = group.unreadCount;
    final isPinned = group.pinnedAt != null;
    final previewColor =
        typing.hasAny ? AppColors.arenaBlue : AppColors.ink2;
    final previewWeight =
        typing.hasAny ? FontWeight.w600 : FontWeight.w400;

    return InkWell(
      onTap: () => context.push('/chat/${group.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Avatar — custom-group PHOTO first, then brand LOGO, then the
            // colored initial. (DMs keep the person's initial.)
            if (!group.isDirect &&
                ((group.photoUrl?.isNotEmpty ?? false) ||
                    (group.brand?.logoUrl?.isNotEmpty ?? false)))
              ClipOval(
                child: CachedNetworkImage(
                  imageUrl: (group.photoUrl?.isNotEmpty ?? false)
                      ? group.photoUrl!
                      : group.brand!.logoUrl!,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: brandColor,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _avatarLetter(group),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: brandColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _avatarLetter(group),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(width: 12),
            // Title + preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Red @ — I have an unanswered mention in this group.
                      if (group.openMentionCount > 0)
                        const Padding(
                          padding: EdgeInsets.only(right: 5),
                          child: Icon(Icons.alternate_email,
                              size: 16, color: Color(0xFFEF4444)),
                        ),
                      Expanded(
                        child: Text(
                          group.displayName,
                          textDirection: detectBidiDirection(group.displayName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (time != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            _formatTime(time),
                            style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 ? AppColors.teal : AppColors.ink3,
                              fontWeight:
                                  unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          textDirection: detectBidiDirection(preview),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: previewColor,
                            fontWeight: previewWeight,
                            fontStyle: typing.hasAny
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                      ),
                      if (isPinned)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 14,
                            color: AppColors.ink3,
                          ),
                        ),
                      if (unread > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          constraints: const BoxConstraints(minWidth: 22),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.teal,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _avatarLetter(BrandGroupModel g) {
    final source = g.isDirect
        ? g.displayName
        : (g.brand?.name.isNotEmpty == true ? g.brand!.name : g.name);
    final cleaned = source.trim();
    if (cleaned.isEmpty) return '?';
    return cleaned.characters.first.toUpperCase();
  }

  /// Preview text shown when someone is actively typing in this group —
  /// takes precedence over the last-message preview.
  String _typingPreview(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return '⌨️ ${names.first} is typing...';
    if (names.length == 2) return '⌨️ ${names[0]} and ${names[1]} are typing...';
    return '⌨️ ${names.first} and ${names.length - 1} others are typing...';
  }

  String _previewText(dynamic last) {
    if (last == null) return 'No messages yet';
    final body = last.bodyExcerpt as String?;
    if (body == null || body.isEmpty) {
      switch (last.type as String) {
        case 'voice':
          return '🎤 Voice message';
        case 'image':
          return '📷 Photo';
        case 'file':
          return '📎 File';
        case 'poll':
          return '📊 Poll';
        case 'task_card':
          return '✅ New task';
        case 'meeting_card':
          return '📅 Meeting';
        default:
          return '';
      }
    }
    final senderName = last.senderName as String?;
    if (senderName != null && senderName.isNotEmpty) {
      return '$senderName: $body';
    }
    return body;
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final isToday = t.year == now.year && t.month == now.month && t.day == now.day;
    if (isToday) {
      return DateFormat('h:mm a').format(t.toLocal());
    }
    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = t.year == yesterday.year &&
        t.month == yesterday.month &&
        t.day == yesterday.day;
    if (isYesterday) return 'Yesterday';
    if (now.difference(t).inDays < 7) {
      return DateFormat.E('en').format(t.toLocal());
    }
    return DateFormat('d/M/y').format(t.toLocal());
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
