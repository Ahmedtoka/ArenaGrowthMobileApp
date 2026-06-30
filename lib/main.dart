import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/errors/error_reporter.dart';
import 'core/providers/app_providers.dart';
import 'core/routing/app_router.dart';
import 'features/attendance/data/background_ping_service.dart';

Future<void> main() async {
  // Sprint M — global error handler. Wraps the entire app so any uncaught
  // sync OR async error surfaces in the friendly bottom sheet (and the user
  // can ship a screenshot to /api/diagnostics/report with one tap).
  await ErrorReporter.runApp(_boot);
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wire the global navigator key so ErrorReporter can show the report
  // sheet without needing a BuildContext at the crash site.
  ErrorReporter.attach(rootNavigatorKey);

  // PERF: these four inits are independent, so run them CONCURRENTLY instead
  // of one-after-another. Startup now takes the time of the SLOWEST one, not
  // the SUM of all four — a big cut to the time-to-first-frame.
  //   - BackgroundPingService: configures (doesn't start) the location service.
  //   - SharedPreferences: async-init; overrides the sync provider below.
  //   - initializeDateFormatting('ar'): Arabic month/day names for DateFormat.
  //   - Firebase: push notifications; guarded so a missing google-services.json
  //     can't crash startup.
  late final SharedPreferences prefs;
  await Future.wait<void>([
    BackgroundPingService.initialize(),
    SharedPreferences.getInstance().then((p) { prefs = p; }),
    initializeDateFormatting('ar', null),
    Firebase.initializeApp().then((_) {}).catchError((Object e) {
      if (kDebugMode) debugPrint('[firebase] init failed (push disabled): $e');
    }),
  ]);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const ArenaApp(),
    ),
  );
}
