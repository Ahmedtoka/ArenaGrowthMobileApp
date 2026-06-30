import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';
import 'chat_providers.dart';
import 'groups_controller.dart';
import 'typing_controller.dart';

/// ─── Group subscriber ──────────────────────────────────────────
/// Subscribes every group to Reverb and keeps each group's typing controller
/// alive (so "X is typing…" shows in the chats list without opening the chat).
///
/// IMPORTANT: this only re-runs when the *set of group IDs* changes — NOT when
/// a preview/timestamp/unread-count updates. Previously it watched the whole
/// groups list, so every incoming message re-subscribed all channels, which
/// (combined with a per-message groups refetch) created a storm that janked the
/// main thread and dropped realtime events.
final _groupSubscriberProvider = Provider<void>((ref) {
  final auth = ref.watch(authControllerProvider).valueOrNull;
  if (auth == null) return;

  // Derive a stable key from just the sorted IDs so `select` only fires the
  // rebuild when groups are actually added/removed.
  final idsCsv = ref.watch(
    groupsControllerProvider.select((async) {
      final ids = (async.valueOrNull ?? const [])
          .map((g) => g.id)
          .toList()
        ..sort();
      return ids.join(',');
    }),
  );
  if (idsCsv.isEmpty) return;

  final ids = idsCsv.split(',').map(int.parse);
  final reverb = ref.read(reverbClientProvider);
  for (final id in ids) {
    reverb.subscribeToBrandGroup(id).catchError((_) {});
    ref.watch(typingControllerProvider(id));
  }
});

/// ─── Event handler ─────────────────────────────────────────────
/// Keeps the chats list (preview / timestamp / unread badge) live when a
/// message arrives anywhere — by updating the affected group IN-MEMORY from
/// the broadcast payload, with NO `/me/groups` network call. This removed the
/// per-message refetch flood that was overloading the server.
final _eventInvalidatorProvider = Provider<void>((ref) {
  final auth = ref.watch(authControllerProvider).valueOrNull;
  if (auth == null) return;
  final myId = auth.id;

  final reverb = ref.read(reverbClientProvider);
  Timer? reconnectRefresh;
  final sub = reverb.events.listen((event) {
    if (!event.channelName.startsWith('private-brand-group.')) return;
    if (event.eventName == '__reconnected') {
      // Socket dropped + recovered: the chats list may have missed updates
      // (Pusher doesn't replay). Refresh ONCE for the whole batch of
      // __reconnected events (debounced) instead of once per group.
      reconnectRefresh?.cancel();
      reconnectRefresh = Timer(const Duration(milliseconds: 600), () {
        ref.invalidate(groupsControllerProvider);
      });
      return;
    }
    if (event.eventName != 'MessageSent') return;
    try {
      final payload = jsonDecode(event.rawData) as Map<String, dynamic>;
      ref
          .read(groupsControllerProvider.notifier)
          .applyIncomingMessage(payload, myUserId: myId);
    } catch (_) {/* ignore malformed payloads */}
  });

  ref.onDispose(() {
    reconnectRefresh?.cancel();
    sub.cancel();
  });
});

/// Top-level bootstrap — watched once by the home shell.
final realtimeBootstrapProvider = Provider<void>((ref) {
  ref.watch(_groupSubscriberProvider);
  ref.watch(_eventInvalidatorProvider);
});
