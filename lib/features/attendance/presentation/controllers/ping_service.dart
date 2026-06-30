import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_helper.dart';
import '../../data/models/attendance_snapshot.dart';
import '../../data/ping_repository.dart';
import 'attendance_controller.dart';

/// Foreground-only location ping streaming.
///
/// Lifecycle (driven entirely off [AttendanceSnapshot.status]):
///   off    → timer stopped, buffer cleared
///   active │
///   break  │── timer running, sample every 60s, flush every 5 min
///   away   │
///
/// This is the *foreground* implementation. When the OS suspends the app
/// (user backgrounded it for a while, or killed it), the timer pauses.
/// Sprint E.3.D will add a foreground service so this keeps running while
/// the app is closed.
///
/// Wired into [bootstrapPingServiceProvider] which the home screen watches.
class PingService {
  PingService(this._ref);

  final Ref _ref;
  Timer? _sampleTimer;
  Timer? _flushTimer;
  final List<PendingPing> _buffer = [];
  bool _running = false;

  /// Re-evaluate whether the timer should be running based on the latest
  /// attendance snapshot. Called by the watcher provider on every state
  /// transition.
  void reconcileWith(AttendanceStatus status) {
    // CONTINUOUS location streaming is DISABLED by product decision. Location
    // is now captured ONLY at attendance events (check-in / out / break /
    // away) by their own endpoints, plus the admin's on-demand "Get current
    // location" button. This kills the every-30s GPS + ping flood that was
    // loading the server. Keep this as a stop-only guard in case a timer was
    // ever running.
    if (_running) _stop();
  }

  void _start() {
    if (_running) return;
    _running = true;
    if (kDebugMode) debugPrint('[ping] streaming started');

    // Sample immediately + flush so the Live Tracker shows the marker
    // within ~5 seconds of check-in.
    () async {
      await _sampleOnce();
      await _flushOnce();
    }();

    // Sample every 30s, flush every 2 minutes. That's a ping every ~30s
    // on the dashboard side, which is plenty for "where is everyone now".
    _sampleTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sampleOnce(),
    );
    _flushTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _flushOnce(),
    );
  }

  void _stop() {
    if (!_running) return;
    _running = false;
    _sampleTimer?.cancel();
    _flushTimer?.cancel();
    _sampleTimer = null;
    _flushTimer = null;

    // Last-ditch flush of whatever we have so we don't lose the final
    // few samples.
    unawaited(_flushOnce());
    if (kDebugMode) debugPrint('[ping] streaming stopped');
  }

  Future<void> _sampleOnce() async {
    try {
      ({double lat, double lng, int? accuracy})? fix;
      try {
        fix = await LocationHelper.tryGetOneShot();
      } catch (e) {
        if (kDebugMode) debugPrint('[ping] sample failed: $e');
      }

      // DEV-only fallback: emulators don't deliver GPS reliably, so we
      // simulate a slow walk around Arena HQ so the Live Tracker can be
      // exercised end-to-end. Production builds skip this — a real device
      // either gets a fix or drops the ping silently.
      if (fix == null && kDebugMode) {
        fix = _devSyntheticFix();
        debugPrint('[ping] DEV synthetic fix '
            '(${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)})');
      }

      if (fix == null) {
        if (kDebugMode) debugPrint('[ping] sample: no fix, skipping');
        return;
      }

      _buffer.add(PendingPing(
        latitude: fix.lat,
        longitude: fix.lng,
        accuracyMeters: fix.accuracy,
        reportedAt: DateTime.now(),
      ),);
      if (kDebugMode) {
        debugPrint('[ping] sample #${_buffer.length} '
            '(${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)})');
      }

      // Auto-flush early when the buffer fills up, so a long offline
      // stretch doesn't bloat the request.
      if (_buffer.length >= 5) {
        unawaited(_flushOnce());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ping] sample unexpected: $e');
    }
  }

  /// Drifts the dev "position" by a few meters every sample so the Live
  /// Tracker map shows movement rather than a stationary marker.
  int _devTick = 0;
  ({double lat, double lng, int? accuracy}) _devSyntheticFix() {
    _devTick++;
    // 0.00005 degrees ≈ 5 m — looks like a slow walk on the map.
    final dx = (_devTick % 20) * 0.00005;
    final dy = ((_devTick ~/ 20) % 10) * 0.00005;
    return (
      lat: LocationHelper.devArenaHqLat + dy,
      lng: LocationHelper.devArenaHqLng + dx,
      accuracy: 12,
    );
  }

  Future<void> _flushOnce() async {
    if (_buffer.isEmpty) return;
    final batch = List<PendingPing>.from(_buffer);
    _buffer.clear();

    try {
      final repo = _ref.read(pingRepositoryProvider);
      final result = await repo.flush(batch);
      if (kDebugMode) {
        debugPrint('[ping] flushed ${batch.length} → '
            'accepted=${result.accepted} reason=${result.reason ?? '-'}');
      }
      // If the server tells us the user is no longer checked in, stop
      // streaming — we missed a check-out event.
      if (result.reason == 'not_checked_in' && _running) {
        _stop();
      }
    } catch (e) {
      // On failure, push the batch back to the front so it's retried on
      // the next flush. Avoid duplicating: only re-buffer if room.
      if (_buffer.length < 40) {
        _buffer.insertAll(0, batch);
      }
      if (kDebugMode) debugPrint('[ping] flush failed: $e');
    }
  }
}

final pingServiceProvider = Provider<PingService>((ref) {
  final svc = PingService(ref);
  ref.onDispose(svc._stop);
  return svc;
});

/// Watches the attendance snapshot and tells the [PingService] to start/
/// stop accordingly. Mount with `ref.watch(bootstrapPingServiceProvider)`
/// once high in the widget tree (e.g. the home screen).
///
/// Sprint #106 note — the Android background foreground service is NOT
/// auto-started here anymore. Two isolates both polling Geolocator at the
/// same time crashes the FlutterGeolocator plugin. The lifecycle-aware
/// start/stop (foreground→stop, background→start) lives in
/// [AppLifecycleBackgroundPingBootstrap] which the home screen mounts.
final bootstrapPingServiceProvider = Provider<void>((ref) {
  final asyncSnap = ref.watch(attendanceControllerProvider);
  asyncSnap.whenData((snap) {
    ref.read(pingServiceProvider).reconcileWith(snap.status);
  });
});
