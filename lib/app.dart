import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:screenshot/screenshot.dart';

import 'core/constants/app_constants.dart';
import 'core/errors/error_reporter.dart';
import 'core/providers/app_providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class ArenaApp extends ConsumerWidget {
  const ArenaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lock to portrait — chat apps don't need landscape in v1.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    final router = ref.watch(appRouterProvider);

    // Wire the error reporter to (a) ship every crash silently to the backend
    // and (b) know which screen the user was on. Both read here where the
    // GoRouter + providers are in scope. Idempotent — safe on every rebuild.
    ErrorReporter.autoSendClient = ref.read(dioClientProvider);
    ErrorReporter.routeResolver = () {
      try {
        return router.routerDelegate.currentConfiguration.uri.toString();
      } catch (_) {
        return '';
      }
    };

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp.router(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.light,
        routerConfig: router,
        locale: const Locale(AppConstants.defaultLanguage),
        supportedLocales: const [
          Locale(AppConstants.langAr),
          Locale(AppConstants.langEn),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // App is English-first. LTR is the base direction; individual
        // user-supplied text (chat messages, task titles) auto-detects
        // its own direction via detectBidiDirection() so Arabic text
        // still renders correctly inside bubbles.
        //
        // Sprint M — wrap with Screenshot so ErrorReporter can capture
        // the visible frame when an uncaught error fires. The capture
        // happens BEFORE we show the report sheet so the screenshot
        // reflects the moment of failure (not the modal overlay).
        builder: (context, child) => Screenshot(
          controller: ErrorReporter.screenshotController,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
