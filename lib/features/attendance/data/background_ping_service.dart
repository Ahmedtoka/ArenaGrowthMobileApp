import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dio/dio.dart';

import '../../../core/config/env.dart';

/// Sprint #106 — true background location pings (Android foreground service).
///
/// `flutter_background_service` spawns a SECOND Dart isolate inside an Android
/// foreground service that survives the app being backgrounded / screen
/// turned off. From that isolate we read GPS once a minute and POST each
/// fix to the same `/attendance/pings` endpoint the foreground service uses.
///
/// iOS is intentionally **not** wired up here — iOS doesn't allow a generic
/// foreground service. iOS background updates are best-effort via the
/// existing `PingService` while the app is in the foreground.
///
/// Lifecycle:
///   1. App start → [initialize] configures the service (no-op on iOS).
///   2. User checks in (or duty toggle goes Active) → [start] kicks the
///      foreground service. The persistent notification confirms streaming.
///   3. User goes Away / checks out → [stop] tears the service down.
class BackgroundPingService {
  BackgroundPingService._();

  static const String _prefsTokenKey = 'auth_token';
  static const String _prefsBaseKey = 'arena_api_base';

  static FlutterBackgroundService get _svc => FlutterBackgroundService();

  /// Hook from main.dart BEFORE runApp. Safe to call on iOS (no-op).
  ///
  /// IMPORTANT (#31 — "location once at check-in, NO background"): we no
  /// longer run a background foreground-service. This method now exists ONLY
  /// to KILL any leftover service started by an older build. Older releases
  /// ran a sticky FOREGROUND service; on Android 14+ Android tries to restart
  /// it and the foreground-notification post throws
  /// `CannotPostForegroundServiceNotificationException` → instant crash on
  /// launch. We reconfigure with `isForegroundMode: false` (so any restart is
  /// a harmless background service, never a crashing foreground one) and then
  /// stop it outright.
  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    try {
      await _svc.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: false,
          // NOT foreground — this is the whole fix. A leftover sticky service
          // restarts as a plain background service with no notification to
          // reject, so the Android-14 startForeground crash can't happen.
          isForegroundMode: false,
          notificationChannelId: 'arena_location_ping',
          initialNotificationTitle: 'Arena',
          initialNotificationContent: 'Idle',
          foregroundServiceNotificationId: 991,
        ),
        iosConfiguration: IosConfiguration(),
      );
      // Kill any leftover instance from a previous (foreground) build.
      if (await _svc.isRunning()) {
        _svc.invoke('stop');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[bg-ping] init/cleanup failed: $e');
    }
  }

  /// Start the persistent foreground service. Persists the bearer token
  /// + API base in SharedPreferences so the background isolate (which
  /// can't read Riverpod providers) can authenticate.
  ///
  /// All `_svc` calls are wrapped in try/catch — the platform channel can
  /// throw `JSONMethodCodec.decodeEnvelope … null` on certain emulator /
  /// device combinations (the service binder isn't ready yet, or the
  /// plugin returns null instead of a real envelope). Letting that bubble
  /// up triggers the global error handler popup and looks like a crash.
  static Future<void> start({
    required String bearerToken,
    String? apiBaseOverride,
  }) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, bearerToken);
    await prefs.setString(
        _prefsBaseKey, apiBaseOverride ?? Env.apiBaseUrl,);
    try {
      if (await _svc.isRunning()) return;
      await _svc.startService();
    } catch (e) {
      // ignore: avoid_print
      print('[bg] start failed (non-fatal): $e');
    }
  }

  /// Stop the service — call when user checks out / goes Away.
  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      if (await _svc.isRunning()) {
        _svc.invoke('stop');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[bg] stop failed (non-fatal): $e');
    }
  }
}

/// Entry-point that runs INSIDE the background isolate. Has no access to
/// Riverpod or the main app's BuildContext — everything (auth token, API
/// base URL) is read from SharedPreferences.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  // Live-stop control from the UI isolate.
  service.on('stop').listen((_) => service.stopSelf());

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(BackgroundPingService._prefsTokenKey);
  final base = prefs.getString(BackgroundPingService._prefsBaseKey)
      ?? Env.apiBaseUrl;
  if (token == null || token.isEmpty) {
    service.stopSelf();
    return;
  }

  final dio = Dio(BaseOptions(
    baseUrl: base,
    headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    },
    connectTimeout: const Duration(seconds: 8),
    sendTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 12),
  ),);

  // Sample every minute. Cheaper on battery than the foreground 30s cadence
  // because the user isn't actively staring at the dashboard.
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await dio.post('/team/attendance/pings', data: {
        'pings': [
          {
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy_meters': pos.accuracy.round(),
            'is_app_foreground': false,
            'reported_at': DateTime.now().toUtc().toIso8601String(),
          }
        ],
      },);
    } catch (e) {
      // Quiet failure — next minute will retry. Service stays alive.
      if (kDebugMode) debugPrint('[bg-ping] tick failed: $e');
    }
  });

  // Update the persistent notification every minute so the user can see it's alive.
  if (service is AndroidServiceInstance) {
    Timer.periodic(const Duration(minutes: 1), (_) async {
      service.setForegroundNotificationInfo(
        title: 'Arena attendance',
        content:
            'Last update: ${DateTime.now().toString().substring(11, 19)}',
      );
    });
  }
}
