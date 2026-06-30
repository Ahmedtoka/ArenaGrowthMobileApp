import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_helper.dart';
import '../../data/models/attendance_snapshot.dart';
import '../../data/repositories/attendance_repository.dart';

/// Drives the dashboard attendance tile.
///
/// State machine on top of [AttendanceSnapshot]:
///   away   →  checkIn()        →  active
///   active →  breakStart()     →  break
///   break  →  breakEnd()       →  active
///   active/break → checkOut()  →  away
///
/// Every action tries for a GPS fix first. If none is available, the caller
/// can opt to send the action anyway with null coords (the server records
/// `is_matched=false` and the admin reviews these in the attendance report).
class AttendanceController extends AsyncNotifier<AttendanceSnapshot> {
  @override
  Future<AttendanceSnapshot> build() async {
    try {
      return await ref.read(attendanceRepositoryProvider).today();
    } catch (e) {
      if (kDebugMode) debugPrint('[attendance] initial fetch failed: $e');
      return AttendanceSnapshot.empty;
    }
  }

  /// Re-pull from server without showing the spinner — used after the
  /// user pulls to refresh.
  Future<void> refresh() async {
    try {
      final snap = await ref.read(attendanceRepositoryProvider).today();
      state = AsyncData(snap);
    } catch (e) {
      if (kDebugMode) debugPrint('[attendance] refresh failed: $e');
    }
  }

  /// Try for a GPS fix once.
  ///
  /// Returns:
  ///   - the fix on success
  ///   - null if [LocationUnavailableException] was thrown — the UI can
  ///     decide to retry, prompt the user, or push the action with no coords
  ///   - rethrows other exceptions
  Future<({double lat, double lng, int? accuracy})?> tryLocate() async {
    try {
      return await LocationHelper.tryGetOneShot();
    } on LocationUnavailableException {
      return null;
    }
  }

  Future<AttendanceActionResult> checkIn({
    ({double lat, double lng, int? accuracy})? fix,
    String? note,
  }) async {
    return _run((repo) => repo.checkIn(
          latitude: fix?.lat,
          longitude: fix?.lng,
          accuracyMeters: fix?.accuracy,
          note: note,
        ),);
  }

  Future<AttendanceActionResult> checkOut({
    ({double lat, double lng, int? accuracy})? fix,
  }) async {
    return _run((repo) => repo.checkOut(
          latitude: fix?.lat,
          longitude: fix?.lng,
          accuracyMeters: fix?.accuracy,
        ),);
  }

  Future<AttendanceActionResult> breakStart({
    ({double lat, double lng, int? accuracy})? fix,
  }) async {
    return _run((repo) => repo.breakStart(
          latitude: fix?.lat,
          longitude: fix?.lng,
          accuracyMeters: fix?.accuracy,
        ),);
  }

  Future<AttendanceActionResult> breakEnd({
    ({double lat, double lng, int? accuracy})? fix,
  }) async {
    return _run((repo) => repo.breakEnd(
          latitude: fix?.lat,
          longitude: fix?.lng,
          accuracyMeters: fix?.accuracy,
        ),);
  }

  /// "Go away" / "I'm back" — flips on-duty without ending the session.
  /// Grabs a best-effort GPS fix (never blocks the action if unavailable)
  /// so the admin Check-ins log shows WHERE the toggle happened.
  Future<AttendanceActionResult> setAvailability(bool available, {String? reason}) async {
    ({double lat, double lng, int? accuracy})? fix;
    try {
      fix = await LocationHelper.tryGetOneShot();
    } catch (_) {/* location optional for availability */}
    return _run((repo) => repo.setAvailability(
          available,
          reason: reason,
          lat: fix?.lat,
          lng: fix?.lng,
          accuracy: fix?.accuracy,
        ),);
  }

  Future<AttendanceActionResult> _run(
    Future<AttendanceSnapshot> Function(AttendanceRepository) action,
  ) async {
    final repo = ref.read(attendanceRepositoryProvider);
    final previous = state;
    try {
      final snap = await action(repo);
      state = AsyncData(snap);
      return AttendanceActionResult.success(snap);
    } catch (e) {
      if (kDebugMode) debugPrint('[attendance] action failed: $e');
      state = previous;
      return AttendanceActionResult.error(_extractMessage(e));
    }
  }

  String _extractMessage(Object e) {
    final str = e.toString();
    final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(str);
    if (match != null) return match.group(1)!;
    return 'Something went wrong. Please try again.';
  }
}

class AttendanceActionResult {
  final bool ok;
  final String? errorMessage;
  final AttendanceSnapshot? snapshot;

  const AttendanceActionResult._({
    required this.ok,
    this.errorMessage,
    this.snapshot,
  });

  factory AttendanceActionResult.success(AttendanceSnapshot snap) =>
      AttendanceActionResult._(ok: true, snapshot: snap);
  factory AttendanceActionResult.error(String message) =>
      AttendanceActionResult._(ok: false, errorMessage: message);
}

final attendanceControllerProvider =
    AsyncNotifierProvider<AttendanceController, AttendanceSnapshot>(
  AttendanceController.new,
);

/// Per-session opt-in flag: once the user clicks "Continue anyway" on the
/// "Location unavailable" prompt, we set this to true and stop showing the
/// dialog for the rest of the run. Resets when the app cold-starts so the
/// user gets one chance to fix their permissions / GPS before we go silent.
///
/// The value is read in [AttendanceCard] before showing the prompt.
final acceptedNoLocationProvider = StateProvider<bool>((_) => false);
