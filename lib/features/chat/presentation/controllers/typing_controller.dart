import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import 'chat_providers.dart';

part 'typing_controller.g.dart';

/// Snapshot of who is currently typing in a brand-group chat.
class TypingState {
  /// Map of userId → (name, lastSeenAt). Stale entries (older than 5s) get
  /// pruned automatically by the controller.
  final Map<int, ({String name, DateTime at})> users;
  const TypingState(this.users);

  List<String> get names => users.values.map((u) => u.name).toList();
  bool get hasAny => users.isNotEmpty;
}

/// Tracks "who is typing" in a given group via the `TypingChanged` event
/// broadcast on the Reverb channel. Local typing state is broadcast back
/// through a small HTTP endpoint (POST /api/team/groups/{id}/typing).
@riverpod
class TypingController extends _$TypingController {
  Timer? _pruneTimer;
  Timer? _myStopTimer;
  StreamSubscription? _sub;
  bool _lastNotifiedTyping = false;

  @override
  TypingState build(int groupId) {
    final reverb = ref.read(reverbClientProvider);

    _sub = reverb.events.listen((event) {
      if (event.channelName != 'private-brand-group.$groupId') return;
      if (event.eventName != 'TypingChanged') return;
      _onIncomingTyping(event.rawData);
    });

    // Prune stale typers every 2s.
    _pruneTimer = Timer.periodic(const Duration(seconds: 2), (_) => _prune());

    ref.onDispose(() {
      _sub?.cancel();
      _pruneTimer?.cancel();
      _myStopTimer?.cancel();
      // Best-effort tell others I left the chat.
      if (_lastNotifiedTyping) _sendTypingHttp(false);
    });

    return const TypingState({});
  }

  void _onIncomingTyping(String rawData) {
    try {
      final payload = jsonDecode(rawData) as Map<String, dynamic>;
      final userId = (payload['user_id'] as num?)?.toInt();
      final name = payload['user_name'] as String?;
      final isTyping = payload['is_typing'] as bool? ?? true;
      final me = ref.read(authControllerProvider).valueOrNull?.id;

      if (userId == null || name == null) return;
      if (userId == me) return; // ignore my own echo

      final current = Map<int, ({String name, DateTime at})>.from(state.users);
      if (isTyping) {
        current[userId] = (name: name, at: DateTime.now());
      } else {
        current.remove(userId);
      }
      state = TypingState(current);
    } catch (e) {
      if (kDebugMode) debugPrint('[typing] parse failed: $e');
    }
  }

  void _prune() {
    final now = DateTime.now();
    final pruned = <int, ({String name, DateTime at})>{};
    for (final e in state.users.entries) {
      if (now.difference(e.value.at) < const Duration(seconds: 5)) {
        pruned[e.key] = e.value;
      }
    }
    if (pruned.length != state.users.length) {
      state = TypingState(pruned);
    }
  }

  /// Call when the local user types. Sends "started" AT MOST ONCE per window —
  /// the stop timer is NOT reset on every keystroke, so a burst of typing
  /// produces a single request then auto-clears. (The receiver also prunes
  /// stale typers after 5s, so a dropped "stop" is harmless.)
  void notifyTyping() {
    if (_lastNotifiedTyping) return; // already announced this typing burst
    _lastNotifiedTyping = true;
    _sendTypingHttp(true);

    _myStopTimer?.cancel();
    _myStopTimer = Timer(const Duration(seconds: 6), () {
      _lastNotifiedTyping = false;
      _sendTypingHttp(false);
    });
  }

  /// Call when the user sends a message — cancels the pending "stop typing"
  /// and immediately broadcasts that they stopped.
  void notifyStopped() {
    _myStopTimer?.cancel();
    if (_lastNotifiedTyping) {
      _lastNotifiedTyping = false;
      _sendTypingHttp(false);
    }
  }

  Future<void> _sendTypingHttp(bool isTyping) async {
    try {
      final client = ref.read(dioClientProvider);
      await client.post(
        ApiConstants.groupTyping(groupId),
        data: {'is_typing': isTyping},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[typing] http failed: $e');
    }
  }
}
