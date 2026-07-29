import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../../features/attendance/data/models/attendance_snapshot.dart';
import '../../features/attendance/presentation/controllers/attendance_controller.dart';

/// ── Work gate ───────────────────────────────────────────────────────────
///
/// The single rule for the whole app: an employee may only perform a
/// MUTATING action (send a message, react/pin, start/deliver/complete a task,
/// request clarification, log a social item, create a group or personal task…)
/// while they are **checked-in AND active** — not on break, not away, not
/// checked-out. Until then they can browse and read only.
///
/// Call it at the very top of every action handler:
///
/// ```dart
/// if (!await ref.ensureCheckedIn(context)) return;
/// ```
///
/// Returns `true` when the user is active (proceed). Otherwise it shows a
/// popup explaining they must check in; tapping the primary button sends them
/// to **My Account** to check in, and it returns `false`.
extension AttendanceGuard on WidgetRef {
  Future<bool> ensureCheckedIn(BuildContext context) async {
    // Use the last-known snapshot; if it hasn't loaded yet (e.g. deep-linked
    // straight into a screen) fetch it once so we never false-block someone
    // who is actually active.
    var snap = read(attendanceControllerProvider).valueOrNull;
    if (snap == null) {
      try {
        snap = await read(attendanceControllerProvider.future);
      } catch (_) {/* fall through to "off" */}
    }

    final status = snap?.status ?? AttendanceStatus.off;
    if (status == AttendanceStatus.active) return true; // ✅ allowed

    if (!context.mounted) return false;

    final reason = switch (status) {
      AttendanceStatus.breakTime => 'You\'re on a break right now.',
      AttendanceStatus.away => 'You\'re marked as away right now.',
      _ => 'You\'re not checked in right now.',
    };

    final goCheckIn = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.badge_outlined,
            color: AppColors.arenaBlue, size: 34),
        title: const Text('Check in first'),
        content: Text(
          '$reason\n\n'
          'You need to be checked in and active to do anything here — send '
          'messages, start or deliver tasks, or log activity. Until then you '
          'can only view.\n\n'
          'Check in from My Account and you\'re good to go.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.arenaBlue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Check in'),
          ),
        ],
      ),
    );

    if (goCheckIn == true && context.mounted) {
      context.push('/profile'); // My Account — has the check-in card
    }
    return false; // blocked either way
  }
}
