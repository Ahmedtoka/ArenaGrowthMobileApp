import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../data/background_ping_service.dart';
import '../../data/models/attendance_snapshot.dart';
import 'attendance_controller.dart';

/// Sprint #106 — lifecycle-aware coordinator for the Android background
/// foreground service.
///
/// We CANNOT run the foreground `PingService` (main isolate) and the
/// `BackgroundPingService` (background isolate) at the same time — both
/// hit Geolocator and the plugin crashes when two isolates fight over it.
///
/// So the rule is: ONE poller at a time.
///   - app FOREGROUND + at-work → foreground PingService runs, bg service OFF
///   - app BACKGROUND/HIDDEN + at-work → bg service ON, foreground PingService
///                                       paused by the OS anyway
///
/// Mount once at the top of the widget tree via
/// `AppLifecycleBackgroundPingBootstrap(child: ...)`. It listens to the
/// AppLifecycleState + the attendance snapshot and flips the bg service
/// in lockstep.
class AppLifecycleBackgroundPingBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  const AppLifecycleBackgroundPingBootstrap({super.key, required this.child});

  @override
  ConsumerState<AppLifecycleBackgroundPingBootstrap> createState() =>
      _State();
}

class _State extends ConsumerState<AppLifecycleBackgroundPingBootstrap>
    with WidgetsBindingObserver {
  bool _bgRunning = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Timer? _debounce;
  // Transient pauses caused by a file/image picker or a permission prompt
  // also drop the app into `paused` state. Don't fire the background service
  // unless the pause lasts at least this long — gives Geolocator time to
  // see ONE poller, not two competing engines.
  static const _bgStartDebounce = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort stop on dispose so we never leave a zombie service.
    BackgroundPingService.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _reconcile();
  }

  Future<void> _reconcile() async {
    // CONTINUOUS background location streaming is DISABLED by product decision
    // (no live tracking). We never START the background poller anymore; we only
    // ever make sure it's STOPPED. Location is captured at attendance events +
    // the admin's on-demand request only.
    const shouldRun = false;

    // Coming BACK to foreground (or user checked out) — kill immediately so
    // the foreground PingService can take over without a Geolocator clash.
    if (!shouldRun) {
      _debounce?.cancel();
      _debounce = null;
      if (_bgRunning) {
        await BackgroundPingService.stop();
        _bgRunning = false;
      }
      return;
    }

    // Going to background — wait `_bgStartDebounce` before launching the bg
    // service. Transient pauses (file picker, image picker, OS overlays)
    // resolve in under a second; a real "user left the app" lasts longer.
    if (!_bgRunning && _debounce == null) {
      _debounce = Timer(_bgStartDebounce, () async {
        _debounce = null;
        // Re-check both flags — the app may have come back during the wait.
        if (_lifecycle == AppLifecycleState.resumed) return;
        final stillAtWork = ref
                .read(attendanceControllerProvider)
                .valueOrNull
                ?.status
                .isAtWork ??
            false;
        if (!stillAtWork) return;
        final token = await ref.read(secureStorageProvider).getToken();
        if (token == null || token.isEmpty) return;
        await BackgroundPingService.start(bearerToken: token);
        _bgRunning = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the attendance snapshot so a checkout while backgrounded also
    // tears down the service on next foreground.
    ref.listen<AsyncValue>(attendanceControllerProvider, (_, __) => _reconcile());
    return widget.child;
  }
}
