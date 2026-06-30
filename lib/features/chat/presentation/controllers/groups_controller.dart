import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/brand_group_model.dart';
import '../../data/models/last_message_preview.dart';
import 'chat_providers.dart';

part 'groups_controller.g.dart';

/// Loads the user's chats list. Use `ref.invalidate(groupsControllerProvider)`
/// to refresh after sending a message or pull-to-refresh.
///
/// NOT keepAlive so logout + re-login doesn't reuse a stale failed state.
@riverpod
class GroupsController extends _$GroupsController {
  @override
  Future<List<BrandGroupModel>> build() async {
    final repo = ref.read(chatRepositoryProvider);
    return repo.listMyGroups();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(chatRepositoryProvider);
      return repo.listMyGroups();
    });
  }

  /// Update ONE group's preview / timestamp / unread badge in-memory straight
  /// from a Reverb broadcast payload — NO network call. This replaces the
  /// per-message `/me/groups` refetch that was flooding the server, and keeps
  /// the chats list live for free.
  void applyIncomingMessage(
    Map<String, dynamic> payload, {
    required int myUserId,
    int? openGroupId,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final gid = payload['brand_group_id'] as int?;
    if (gid == null) return;
    final idx = current.indexWhere((g) => g.id == gid);
    if (idx < 0) return; // not in my list — a periodic refresh will reconcile

    final senderId = payload['user_id'] as int?;
    final isMine = senderId == myUserId;
    final isOpen = openGroupId == gid;
    final createdAt =
        DateTime.tryParse((payload['created_at'] ?? '') as String? ?? '');

    final g = current[idx];
    final updated = g.copyWith(
      lastMessage: LastMessagePreview(
        id: (payload['id'] as int?) ?? 0,
        bodyExcerpt: payload['body'] as String?,
        type: (payload['type'] as String?) ?? 'text',
        senderId: senderId,
        senderName: payload['sender_name'] as String?,
        createdAt: createdAt,
      ),
      lastMessageAt: createdAt ?? g.lastMessageAt,
      unreadCount:
          (isMine || isOpen) ? g.unreadCount : g.unreadCount + 1,
    );

    final list = [...current];
    list[idx] = updated;
    // Pinned first, then most-recent activity on top.
    list.sort((a, b) {
      if (a.pinnedAt != null && b.pinnedAt == null) return -1;
      if (a.pinnedAt == null && b.pinnedAt != null) return 1;
      final at = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    state = AsyncData(list);
  }
}
