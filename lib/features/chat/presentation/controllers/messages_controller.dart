import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../data/models/message_model.dart';
import 'chat_providers.dart';
import 'groups_controller.dart';

part 'messages_controller.g.dart';

/// Per-group message list. Loads initial page on subscribe, then merges in
/// new messages received via Reverb in realtime.
@riverpod
class MessagesController extends _$MessagesController {
  StreamSubscription? _realtimeSub;

  // ─── Infinite scroll-back state ───────────────────────────────────
  /// False once a backward page returns fewer than requested (no older left).
  bool hasMoreOlder = true;
  bool _loadingOlder = false;

  @override
  Future<List<MessageModel>> build(int groupId) async {
    final repo = ref.read(chatRepositoryProvider);

    // Subscribe to realtime for this group.
    _wireRealtime(groupId);

    // NOTE: do NOT call unsubscribeFromBrandGroup here on dispose. The
    // dart_pusher_channels library has stateful subscription tracking on the
    // socket; unsubscribing then re-subscribing in the same socket lifetime
    // makes the second subscribe a no-op (Pusher server thinks the channel
    // is still subscribed). Keeping the channel alive until logout means
    // re-entering the chat works without a re-handshake.
    ref.onDispose(() {
      _realtimeSub?.cancel();
      _incomingDebounce?.cancel();
    });

    final messages = await repo.getMessages(groupId, limit: 50);

    // Opening this chat means I've read everything. Mark all as read so the
    // unread badge on the chats list collapses to 0 (refresh the list once).
    _markRead(groupId, refreshList: true);

    return messages;
  }

  Timer? _incomingDebounce;

  /// Tell the server "I've read everything up to the latest message in this
  /// group". [refreshList] re-pulls the chats list so the unread badge clears
  /// — only needed when first opening the chat. On every incoming realtime
  /// message we pass false (the debounced bootstrap invalidator handles the
  /// list), otherwise we'd refetch /me/groups on every keystroke-fast message.
  void _markRead(int groupId, {bool refreshList = false}) {
    final repo = ref.read(chatRepositoryProvider);
    repo.markGroupRead(groupId).then((_) {
      if (refreshList) ref.invalidate(groupsControllerProvider);
    }).catchError((e) {
      if (kDebugMode) debugPrint('[messages] markGroupRead failed: $e');
    });
  }

  void _wireRealtime(int groupId) {
    final reverb = ref.read(reverbClientProvider);
    // Fire-and-forget subscribe.
    reverb.subscribeToBrandGroup(groupId).catchError((_) {});
    _realtimeSub = reverb.events.listen((event) {
      if (event.channelName != 'private-brand-group.$groupId') return;
      if (event.eventName == 'MessageSent') {
        _onIncomingMessage(event.rawData);
      } else if (event.eventName == 'MessageDeleted') {
        _onDeletedMessage(event.rawData);
      } else if (event.eventName == 'MessageUpdated') {
        _onUpdatedMessage(event.rawData);
      } else if (event.eventName == '__reconnected') {
        // Connection dropped and recovered — Pusher does not replay missed
        // messages, so pull the latest page and merge in anything we missed.
        _refetchAfterReconnect(groupId);
      }
    });
  }

  /// Fills the gap after a websocket drop: fetches the latest page and merges
  /// any messages we don't already have (keeps older paginated history).
  Future<void> _refetchAfterReconnect(int groupId) async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final fresh = await repo.getMessages(groupId, limit: 50);
      final current = state.valueOrNull ?? const [];
      final known = current.map((m) => m.id).toSet();
      final missing = fresh.where((m) => !known.contains(m.id)).toList();
      if (missing.isEmpty) return;
      final merged = [...current, ...missing]
        ..sort((a, b) => a.id.compareTo(b.id));
      state = AsyncData(merged);
      _markRead(groupId);
      if (kDebugMode) {
        debugPrint('[messages] reconnect refetch merged ${missing.length} missed message(s)');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[messages] reconnect refetch failed: $e');
    }
  }

  void _onIncomingMessage(String rawData) {
    try {
      final payload = jsonDecode(rawData) as Map<String, dynamic>;
      final newId = payload['id'] as int;
      final current = state.valueOrNull ?? const [];
      if (current.any((m) => m.id == newId)) return; // dedupe optimistic copy

      // INSTANT: append a message built straight from the broadcast payload so
      // it shows the moment the event arrives — no server round-trip.
      final quick = _fromBroadcast(payload);
      if (quick != null) {
        state = AsyncData([...current, quick]);
      }

      // The broadcast payload is slim (no attachments/reactions/sender avatar).
      // For media messages we still pull the full row to fill those in; plain
      // text needs nothing more.
      final type = (payload['type'] as String?) ?? 'text';
      if (quick == null || type != MessageType.text) {
        _fetchAndInsert(newId);
      }

      _markRead(groupId);
    } catch (e, st) {
      if (kDebugMode) debugPrint('[messages] event parse failed: $e\n$st');
    }
  }

  /// Build a display-ready MessageModel from the slim Reverb broadcast payload.
  MessageModel? _fromBroadcast(Map<String, dynamic> p) {
    try {
      final id = p['id'] as int?;
      final gid = p['brand_group_id'] as int?;
      final uid = p['user_id'] as int?;
      if (id == null || gid == null || uid == null) return null;
      return MessageModel(
        id: id,
        brandGroupId: gid,
        userId: uid,
        type: (p['type'] as String?) ?? MessageType.text,
        body: p['body'] as String?,
        replyToId: p['reply_to_id'] as int?,
        // Carry the FULL payload from the broadcast so system cards
        // (task_card / received / completed / clarification) render their
        // real content the instant they arrive — instead of a blank card
        // that only filled in after the debounced refetch.
        payload: p['payload'] is Map<String, dynamic>
            ? p['payload'] as Map<String, dynamic>
            : null,
        importanceStatus:
            (p['importance_status'] as String?) ?? MessageImportance.normal,
        createdAt: DateTime.tryParse((p['created_at'] ?? '') as String? ?? ''),
        sender: MessageSender(
          id: uid,
          name: (p['sender_name'] as String?) ?? '',
          avatarColor: p['sender_avatar_color'] as String?,
          avatarUrl: p['sender_avatar_url'] as String?,
          initials: p['sender_initials'] as String?,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _onDeletedMessage(String rawData) {
    try {
      final payload = jsonDecode(rawData) as Map<String, dynamic>;
      final id = payload['id'] as int;
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(_markDeleted(current, id));
    } catch (_) {}
  }

  /// A message changed in place (link preview finished, body edited) — patch
  /// it without adding a new bubble.
  void _onUpdatedMessage(String rawData) {
    try {
      final payload = jsonDecode(rawData) as Map<String, dynamic>;
      final id = payload['id'] as int;
      final current = state.valueOrNull;
      if (current == null) return;
      final lp = payload['link_preview'];
      state = AsyncData([
        for (final m in current)
          if (m.id == id)
            m.copyWith(
              linkPreview: lp is Map<String, dynamic> ? lp : m.linkPreview,
              body: (payload['body'] as String?) ?? m.body,
            )
          else
            m,
      ]);
    } catch (_) {}
  }

  /// Replace a message with a tombstone (keeps it in place as a placeholder).
  List<MessageModel> _markDeleted(List<MessageModel> list, int id) => [
        for (final m in list)
          if (m.id == id)
            m.copyWith(
              deletedAt: m.deletedAt ?? DateTime.now(),
              body: null,
              attachments: const [],
              reactions: const [],
            )
          else
            m,
      ];

  void _fetchAndInsert(int messageId) {
    // Debounce: a burst of incoming messages coalesces into ONE refetch of the
    // latest page instead of one network round-trip per message.
    _incomingDebounce?.cancel();
    _incomingDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final repo = ref.read(chatRepositoryProvider);
        final fresh = await repo.getMessages(groupId, limit: 50);
        state = AsyncData(fresh);
        // I'm actively looking at this chat → mark read (no list refetch; the
        // debounced bootstrap invalidator keeps the chats list fresh).
        _markRead(groupId);
      } catch (e) {
        if (kDebugMode) debugPrint('[messages] refresh after event failed: $e');
      }
    });
  }

  /// Send a text message. `replyToId` makes it a reply. Optimistically appends
  /// to state, then refreshes the chats list so its preview/timestamp updates.
  Future<void> sendText(
    String body, {
    int? replyToId,
    List<int>? mentions,
  }) async {
    if (body.trim().isEmpty) return;
    final repo = ref.read(chatRepositoryProvider);
    final sent = await repo.sendText(
      groupId,
      body: body.trim(),
      replyToId: replyToId,
      mentions: mentions,
    );

    final current = state.valueOrNull ?? const [];
    if (!current.any((m) => m.id == sent.id)) {
      state = AsyncData([...current, sent]);
    }

    ref.invalidate(groupsControllerProvider);
  }

  /// Upload an image or file. The backend infers the type from the mime.
  /// Optimistically appends the returned message to state.
  Future<void> sendFile(
    File file, {
    String? caption,
    int? replyToId,
    List<int>? mentions,
  }) async {
    final repo = ref.read(chatRepositoryProvider);
    final sent = await repo.sendFile(
      groupId,
      file: file,
      caption: caption,
      replyToId: replyToId,
      mentions: mentions,
    );

    final current = state.valueOrNull ?? const [];
    if (!current.any((m) => m.id == sent.id)) {
      state = AsyncData([...current, sent]);
    }

    ref.invalidate(groupsControllerProvider);
  }

  /// Upload a voice note (recorded via the mic in the composer).
  Future<void> sendVoice(
    File file, {
    required Duration duration,
    int? replyToId,
  }) async {
    final repo = ref.read(chatRepositoryProvider);
    final sent = await repo.sendVoice(
      groupId,
      file: file,
      durationMs: duration.inMilliseconds,
      replyToId: replyToId,
    );

    final current = state.valueOrNull ?? const [];
    if (!current.any((m) => m.id == sent.id)) {
      state = AsyncData([...current, sent]);
    }

    ref.invalidate(groupsControllerProvider);
  }

  /// Mark a message Red — flagged for follow-up.
  Future<void> markRed(int messageId) => _applyAction(
        messageId,
        (repo) => repo.markRed(messageId),
      );

  /// Mark a message Green — approved / closed. Backend also auto-pins it.
  Future<void> markGreen(int messageId) => _applyAction(
        messageId,
        (repo) => repo.markGreen(messageId),
      );

  /// Clear R/O/G back to normal.
  Future<void> revert(int messageId) => _applyAction(
        messageId,
        (repo) => repo.revert(messageId),
      );

  /// Toggle an emoji reaction; merges the server's updated reactions back in.
  Future<void> react(int messageId, String emoji) => _applyAction(
        messageId,
        (repo) => repo.toggleReaction(messageId, emoji),
      );

  /// Toggle pin for a message (returns the new pinned state) AND reflect it in
  /// local state immediately so the bubble flips to the pinned look (red border
  /// + pin badge) without waiting for a full reload.
  Future<bool> pin(int messageId) async {
    final repo = ref.read(chatRepositoryProvider);
    final nowPinned = await repo.togglePin(messageId);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData([
        for (final m in current)
          if (m.id == messageId) m.copyWith(isPinned: nowPinned) else m,
      ]);
    }
    return nowPinned;
  }

  /// Ensure [messageId] is present in local state, paging backwards (older
  /// messages) up to a few times if necessary. Returns true once it's loaded.
  /// Used by "jump to pinned message" so older pins can be reached.
  Future<bool> ensureLoaded(int messageId) async {
    var current = state.valueOrNull;
    if (current == null) return false;
    if (current.any((m) => m.id == messageId)) return true;

    final repo = ref.read(chatRepositoryProvider);
    for (var i = 0; i < 8; i++) {
      if (current!.isEmpty) break;
      final oldestId =
          current.map((m) => m.id).reduce((a, b) => a < b ? a : b);
      final older =
          await repo.getMessages(groupId, before: oldestId, limit: 50);
      if (older.isEmpty) break;
      final seen = current.map((m) => m.id).toSet();
      final merged = [
        ...older.where((m) => !seen.contains(m.id)),
        ...current,
      ];
      state = AsyncData(merged);
      current = merged;
      if (merged.any((m) => m.id == messageId)) return true;
    }
    return current!.any((m) => m.id == messageId);
  }

  /// Scroll-to-top pagination: pull the next page of OLDER messages (cursor =
  /// the oldest loaded id, so it stays fast even on huge groups) and PREPEND
  /// them. Returns how many were actually added so the screen can preserve the
  /// scroll position. Safe to call repeatedly — it self-throttles and stops
  /// once the server has no more history.
  Future<int> loadOlder() async {
    if (_loadingOlder || !hasMoreOlder) return 0;
    final current = state.valueOrNull;
    if (current == null || current.isEmpty) return 0;

    _loadingOlder = true;
    try {
      final oldestId = current.map((m) => m.id).reduce((a, b) => a < b ? a : b);
      final repo = ref.read(chatRepositoryProvider);
      final older = await repo.getMessages(groupId, before: oldestId, limit: 30);

      if (older.length < 30) hasMoreOlder = false;

      final seen = current.map((m) => m.id).toSet();
      final fresh = older.where((m) => !seen.contains(m.id)).toList();
      if (fresh.isEmpty) {
        hasMoreOlder = false;
        return 0;
      }
      state = AsyncData([...fresh, ...current]);
      return fresh.length;
    } catch (_) {
      return 0; // keep hasMoreOlder so a later scroll can retry
    } finally {
      _loadingOlder = false;
    }
  }

  /// Calls the action, then replaces the message in state with the server's
  /// updated copy (preserves order).
  Future<void> _applyAction(
    int messageId,
    Future<MessageModel> Function(dynamic repo) call,
  ) async {
    final repo = ref.read(chatRepositoryProvider);
    final updated = await call(repo);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final m in current)
        if (m.id == messageId) _mergePreservingSender(m, updated) else m,
    ]);
  }

  MessageModel _mergePreservingSender(MessageModel old, MessageModel fresh) {
    return fresh.sender == null ? fresh.copyWith(sender: old.sender) : fresh;
  }

  /// Soft-delete a message. Removes it from the local state on success.
  Future<void> deleteMessage(int messageId) async {
    final repo = ref.read(chatRepositoryProvider);
    await repo.deleteMessage(messageId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(_markDeleted(current, messageId));
    ref.invalidate(groupsControllerProvider);
  }

  /// Sprint P.2 — edit own message body and replace it in local state.
  Future<void> editMessage(int messageId, String newBody) async {
    final repo = ref.read(chatRepositoryProvider);
    final updated = await repo.editMessage(messageId, newBody);
    if (updated == null) return;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final m in current)
        if (m.id == messageId) _mergePreservingSender(m, updated) else m,
    ]);
  }

  /// Manual refresh (pull-to-refresh).
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      final repo = ref.read(chatRepositoryProvider);
      return repo.getMessages(groupId, limit: 50);
    });
  }
}
