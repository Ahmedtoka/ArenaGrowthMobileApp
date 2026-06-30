import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/providers/app_providers.dart';

/// Snapshot of the user's "I'm Active / I'm Away" status. Mirrors
/// `users.is_on_duty` + `users.on_duty_since` on the server.
class DutyState {
  final bool isOnDuty;
  final DateTime? since;
  const DutyState({required this.isOnDuty, this.since});

  DutyState copyWith({bool? isOnDuty, DateTime? since}) =>
      DutyState(isOnDuty: isOnDuty ?? this.isOnDuty, since: since ?? this.since);
}

/// Holds the duty toggle in memory + posts changes to the server.
class DutyController extends Notifier<DutyState> {
  @override
  DutyState build() {
    // Best-effort initial fetch on app start.
    Future.microtask(_refresh);
    return const DutyState(isOnDuty: false);
  }

  Future<void> _refresh() async {
    try {
      final client = ref.read(dioClientProvider);
      final res = await client.get('/auth/me');
      final data = res.data;
      // /auth/me returns the user under either `data.user` or top-level.
      final user = (data is Map<String, dynamic>)
          ? (data['user'] is Map<String, dynamic>
              ? data['user'] as Map<String, dynamic>
              : data)
          : null;
      if (user == null) return;
      final onDuty = user['is_on_duty'] == true;
      final sinceStr = user['on_duty_since'] as String?;
      state = DutyState(
        isOnDuty: onDuty,
        since: sinceStr != null ? DateTime.tryParse(sinceStr) : null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[duty] refresh failed: $e');
    }
  }

  /// Toggle on-duty state. Optimistically flips local state, then posts,
  /// reverting on failure.
  Future<bool> setOnDuty(bool onDuty) async {
    final previous = state;
    state = DutyState(isOnDuty: onDuty, since: onDuty ? DateTime.now() : null);
    try {
      final client = ref.read(dioClientProvider);
      final res = await client.post(
        ApiConstants.myDuty,
        data: {'on_duty': onDuty},
      );
      final data = res.data as Map<String, dynamic>;
      final sinceStr = data['on_duty_since'] as String?;
      state = DutyState(
        isOnDuty: data['is_on_duty'] == true,
        since: sinceStr != null ? DateTime.tryParse(sinceStr) : null,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[duty] toggle failed: $e');
      state = previous;
      return false;
    }
  }
}

final dutyControllerProvider =
    NotifierProvider<DutyController, DutyState>(DutyController.new);
