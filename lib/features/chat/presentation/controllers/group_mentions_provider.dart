import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_providers.dart';

/// One unanswered @mention on the current user inside a group.
class GroupMention {
  final int id;
  final int? messageId;
  final String actorName;
  final String? actorColor;
  final String snippet;
  final DateTime? at;

  const GroupMention({
    required this.id,
    required this.messageId,
    required this.actorName,
    required this.actorColor,
    required this.snippet,
    required this.at,
  });

  factory GroupMention.fromJson(Map<String, dynamic> j) => GroupMention(
        id: j['id'] as int,
        messageId: j['message_id'] as int?,
        actorName: (j['actor_name'] ?? '—').toString(),
        actorColor: j['actor_color'] as String?,
        snippet: (j['snippet'] ?? '').toString(),
        at: j['at'] != null ? DateTime.tryParse(j['at'].toString()) : null,
      );
}

/// The current user's OPEN mentions in a group. Auto-disposes; re-fetch by
/// invalidating after a reply so the badge/list clears.
final groupMentionsProvider =
    FutureProvider.autoDispose.family<List<GroupMention>, int>((ref, groupId) async {
  final rows = await ref.read(chatRepositoryProvider).listGroupMentions(groupId);
  return rows.map(GroupMention.fromJson).toList();
});
