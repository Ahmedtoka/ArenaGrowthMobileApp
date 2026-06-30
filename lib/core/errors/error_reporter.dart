import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:screenshot/screenshot.dart';

import '../network/dio_client.dart';
import '../providers/app_providers.dart';
import 'error_report_sheet.dart';

/// Sprint M — central error reporter.
///
/// Wraps the app with `runZonedGuarded` + hooks into `FlutterError.onError`
/// so EVERY uncaught error (sync or async) ends up here. On error we:
///   1. Capture the visible frame to PNG via the [Screenshot] controller.
///   2. Show a friendly modal with the error type + message + a "Send
///      screenshot" button.
///   3. POST screenshot + stack + metadata to `/api/diagnostics/report`.
///
/// The Screenshot widget must wrap the whole `MaterialApp` so the capture
/// includes everything visible.
class ErrorReporter {
  ErrorReporter._();

  static final ScreenshotController screenshotController =
      ScreenshotController();
  static GlobalKey<NavigatorState>? navigatorKey;

  /// Dio client used for SILENT auto-reporting. Set once from the app root
  /// (app.dart) so `_onError` can ship every crash to the backend without a
  /// BuildContext or a Riverpod ref at the crash site.
  static DioClient? autoSendClient;

  /// Returns the current screen/route ("which screen they were on"). Set from
  /// app.dart where the GoRouter instance is available.
  static String Function()? routeResolver;

  /// Dedupe window — the same error fingerprint is auto-sent at most once per
  /// minute, so a layout error firing every frame doesn't flood the backend.
  static final Map<String, DateTime> _recentlySent = {};

  /// Set by `main()` before runApp. Lets us show the report sheet from any
  /// zone without needing a BuildContext.
  static void attach(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
  }

  static String _currentRoute() {
    try {
      return routeResolver?.call() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Wires both `FlutterError.onError` and the surrounding zone. Call from
  /// `main()` like:
  ///   void main() => ErrorReporter.runApp(() => runApp(MyApp()));
  static Future<void> runApp(Future<void> Function() body) async {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _onError(
        details.exceptionAsString(),
        details.stack?.toString(),
      );
    };
    await runZonedGuarded<Future<void>>(() async {
      await body();
    }, (error, stack) {
      _onError(error.toString(), stack.toString());
    });
  }

  static Future<void> _onError(String message, String? stack) async {
    final route = _currentRoute();

    // 1) AUTO: ship the crash to the backend silently (deduped). This runs
    //    even if the user never taps anything, so nothing is missed.
    _autoSend(message, stack ?? '', route);

    // 2) MANUAL: surface a non-blocking notice with a "Report" action that
    //    opens the detail sheet (lets the user attach the screenshot + send
    //    explicitly). We avoid the full modal on every error so non-fatal
    //    framework errors don't constantly interrupt the user.
    final ctx = navigatorKey?.currentContext;
    if (ctx == null) {
      debugPrint('[ErrorReporter] (no ctx) $message');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final messenger = ScaffoldMessenger.maybeOf(ctx);
        if (messenger == null) return;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF7F1D1D),
            duration: const Duration(seconds: 5),
            content: const Text('Something went wrong — it was reported automatically.'),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                final c = navigatorKey?.currentContext;
                if (c != null) {
                  ErrorReportSheet.show(c, errorMessage: message, stackTrace: stack ?? '');
                }
              },
            ),
          ),
        );
      } catch (_) {/* notice is best-effort */}
    });
  }

  /// Fire-and-forget silent report (with screenshot when grabbable), deduped.
  static void _autoSend(String message, String stack, String route) {
    final client = autoSendClient;
    if (client == null) return;

    final fingerprint = '${_extractType(message)}|$route';
    final now = DateTime.now();
    final last = _recentlySent[fingerprint];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return; // already reported this error recently
    }
    _recentlySent[fingerprint] = now;
    // Keep the dedupe map small.
    if (_recentlySent.length > 50) {
      _recentlySent.clear();
      _recentlySent[fingerprint] = now;
    }

    // Best-effort capture, then send — never awaited by the caller.
    () async {
      Uint8List? shot;
      try {
        shot = await capturePng();
      } catch (_) {}
      await send(
        client: client,
        errorMessage: message,
        stackTrace: stack,
        route: route,
        screenshot: shot,
        source: 'auto',
      );
    }();
  }

  /// Capture the currently-visible frame as PNG bytes. May return null when
  /// the engine can't grab a frame (e.g. during the very first paint).
  static Future<Uint8List?> capturePng() async {
    try {
      return await screenshotController.capture(
        pixelRatio: 2.0,
        delay: const Duration(milliseconds: 100),
      );
    } catch (e) {
      debugPrint('[ErrorReporter] capture failed: $e');
      return null;
    }
  }

  /// POST the report to the backend. Returns null on success, an error
  /// message on failure (which the sheet surfaces inline).
  static Future<String?> send({
    required DioClient client,
    required String errorMessage,
    required String stackTrace,
    String? route,
    Uint8List? screenshot,
    String source = 'manual',
  }) async {
    try {
      String? screenshotB64;
      if (screenshot != null) {
        screenshotB64 = base64Encode(screenshot);
      }
      final pkg = await PackageInfo.fromPlatform();
      final resolvedRoute = (route == null || route.isEmpty) ? _currentRoute() : route;
      await client.post('/diagnostics/report', data: {
        'platform': Platform.isAndroid
            ? 'android'
            : (Platform.isIOS ? 'ios' : 'web'),
        'app_version': pkg.version,
        'route': resolvedRoute,
        'error_type': _extractType(errorMessage),
        'error_message': errorMessage,
        'stack_trace': stackTrace,
        if (screenshotB64 != null) 'screenshot': screenshotB64,
        'metadata': jsonEncode({
          'source': source, // 'auto' (silent crash) | 'manual' (user tapped)
          'screen': resolvedRoute,
          'os_locale': Platform.localeName,
          'os_version': Platform.operatingSystemVersion,
        }),
      },);
      return null;
    } on DioException catch (e) {
      return 'Network error: ${e.message ?? e.type.name}';
    } catch (e) {
      return e.toString();
    }
  }

  static String _extractType(String message) {
    // "FormatException: blah" → "FormatException"
    final colon = message.indexOf(':');
    return colon > 0 && colon < 60 ? message.substring(0, colon) : 'Error';
  }
}

/// Convenience provider so widgets can call `ref.read(errorReporterClient)`
/// instead of importing the DioClient directly.
final errorReporterClientProvider = Provider<DioClient>((ref) {
  return ref.watch(dioClientProvider);
});
