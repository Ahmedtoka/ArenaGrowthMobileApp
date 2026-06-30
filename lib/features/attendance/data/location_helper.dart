import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Best-effort GPS fix for attendance actions.
///
/// Strategy:
///   1. Ensure OS location services are on.
///   2. Make sure we have at least "while-in-use" permission.
///   3. Try `getLastKnownPosition()` — return instantly if cached.
///   4. Fall back to `getCurrentPosition()` with `medium` accuracy + 5s
///      timeout. On Android we use `forceLocationManager: true` to bypass
///      the Fused Location Provider, which is unreliable on emulators.
///   5. On failure: throw [LocationUnavailableException]. The UI is the
///      one that decides what to do (prompt the user in release, show a
///      dev picker in debug).
class LocationHelper {
  /// Preset coordinates the dev picker can offer for testing without GPS.
  /// Tweak these if you want to test different match scenarios.
  static const double devArenaHqLat = 29.973194;
  static const double devArenaHqLng = 31.286002;
  static const double devUnmatchedLat = 30.0444;   // Downtown Cairo
  static const double devUnmatchedLng = 31.2357;   // — way outside any geofence

  /// Returns the best fix we could get, or null if even after retries we
  /// have nothing. Caller decides whether to abort or send null coords.
  static Future<({double lat, double lng, int? accuracy})?> tryGetOneShot() async {
    try {
      return await _attempt();
    } on LocationUnavailableException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('[location] unexpected: $e');
      return null;
    }
  }

  static Future<({double lat, double lng, int? accuracy})> _attempt() async {
    final servicesOn = await Geolocator.isLocationServiceEnabled();
    if (kDebugMode) debugPrint('[location] services enabled? $servicesOn');
    if (!servicesOn) {
      throw const LocationUnavailableException(
        LocationFailure.servicesOff,
        'Location is off in your phone settings. Continue without it?',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (kDebugMode) debugPrint('[location] permission = $permission');
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailableException(
        LocationFailure.denied,
        'Location permission was denied. Continue without it?',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailableException(
        LocationFailure.deniedForever,
        'Location is blocked in app settings. Continue without it?',
      );
    }

    // ── 1. cached fix (instant) ────────────────────────────
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (kDebugMode) {
        debugPrint('[location] getLastKnownPosition → '
            '${cached == null ? 'null' : '(${cached.latitude}, ${cached.longitude}, '
                'accuracy=${cached.accuracy}m, ts=${cached.timestamp})'}');
      }
      if (cached != null && cached.latitude != 0 && cached.longitude != 0) {
        if (kDebugMode) {
          final age = DateTime.now().difference(cached.timestamp);
          debugPrint('[location] using cached fix (${age.inSeconds}s old)');
        }
        return (
          lat: cached.latitude,
          lng: cached.longitude,
          accuracy: cached.accuracy.isNaN ? null : cached.accuracy.round(),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[location] cached lookup failed: $e');
    }

    // ── 2. live fix — TWO attempts ────────────────────────
    //
    // Attempt A (real devices): the FUSED provider with a generous timeout.
    // Fused blends GPS + WiFi + cell and answers in ~1-3s on any phone with
    // Google services. The old code FORCED raw LocationManager (pure GPS)
    // with a 5s cap — indoors, a cold GPS fix takes 10-30s, so real phones
    // were timing out with "No location" on every check-in.
    //
    // Attempt B (fallback): raw LocationManager, low accuracy — covers
    // emulators (no Google services) and de-Googled devices.
    try {
      if (kDebugMode) debugPrint('[location] live fix attempt A (fused)…');
      final LocationSettings fused = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.medium,
              forceLocationManager: false, // use Google's fused provider
              distanceFilter: 0,
              timeLimit: const Duration(seconds: 12),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 12),
            );

      final position = await Geolocator.getCurrentPosition(
        locationSettings: fused,
      ).timeout(const Duration(seconds: 14));
      if (kDebugMode) {
        debugPrint('[location] fused fix → (${position.latitude}, '
            '${position.longitude}, accuracy=${position.accuracy}m)');
      }
      return (
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy.isNaN ? null : position.accuracy.round(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[location] fused attempt failed: $e — trying raw LocationManager…');
    }

    try {
      final LocationSettings raw = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.low, // accept a coarse fix over none
              forceLocationManager: true,
              distanceFilter: 0,
              timeLimit: const Duration(seconds: 8),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            );

      final position = await Geolocator.getCurrentPosition(
        locationSettings: raw,
      ).timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        debugPrint('[location] raw fix → (${position.latitude}, '
            '${position.longitude}, accuracy=${position.accuracy}m)');
      }
      return (
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy.isNaN ? null : position.accuracy.round(),
      );
    } on TimeoutException {
      throw const LocationUnavailableException(
        LocationFailure.timeout,
        'Could not get a GPS fix. Continue without it?',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[location] raw attempt failed: $e');
      throw LocationUnavailableException(
        LocationFailure.unknown,
        'Location read failed: ${e.toString().split('\n').first}. Continue without it?',
      );
    }
  }
}

enum LocationFailure { servicesOff, denied, deniedForever, timeout, unknown }

class LocationUnavailableException implements Exception {
  final LocationFailure reason;
  final String userMessage;
  const LocationUnavailableException(this.reason, this.userMessage);

  @override
  String toString() => 'LocationUnavailableException($reason): $userMessage';
}
