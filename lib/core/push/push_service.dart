import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants/api_constants.dart';
import '../network/dio_client.dart';
import '../routing/app_router.dart';
import 'active_chat_tracker.dart';
import 'pending_deep_link.dart';

/// Wraps Firebase Messaging + local notifications so we can:
///   - request push permission on Android 13+
///   - upload the device's FCM token to the backend (one per device)
///   - show a heads-up notification for messages received in the foreground
///     (FCM by default only shows them when the app is backgrounded)
///
/// Phase 3.J: client is built but does nothing useful until the user
/// completes the Firebase setup (google-services.json + FCM_ENABLED=true
/// in the Laravel .env). See README for the steps.
class PushService {
  final DioClient _client;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  PushService(this._client);

  Future<void> init() async {
    // The one-time setup (permissions, channels, listeners) is guarded by
    // [_initialized] so we don't double-attach handlers. But token
    // registration must run on EVERY call, because:
    //   - The DB may have been wiped on the server side.
    //   - The user logs out + back in with a different account in the same
    //     app instance.
    //   - We were called from a cold-start where there's no token yet AND
    //     from post-login where one needs to be (re)registered.
    if (!_initialized) {
      _initialized = true;

      // 1. Permission (Android 13+ and iOS).
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // 2. Local notification channels for in-foreground heads-up.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // iOS: don't ask for permission here — FirebaseMessaging.requestPermission
      // above already prompted, and both go through the same iOS authorization
      // store, so asking twice would just be a redundant no-op prompt.
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (resp) {
          final payload = resp.payload;
          if (payload == null || payload.isEmpty) return;
          // ignore: avoid_print
          print('[push] local notif tap → $payload');
          PendingDeepLink.instance.set(payload);
          appNavigator?.go('/');
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'chat_messages',
              'Messages',
              importance: Importance.high,
            ),
          );

      // 3. Wire up listeners ONCE.
      _messaging.onTokenRefresh.listen(_registerToken);
      FirebaseMessaging.onMessage.listen(_onForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // 4. Cold-start tap → deep link.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        Future.delayed(
            const Duration(milliseconds: 500), () => _handleTap(initial),);
      }
    }

    // Always (re)push the current token to the server. Cheap, idempotent on
    // the backend (updateOrCreate with withTrashed). This is the critical
    // step that survives a DB wipe or a logout/login cycle.
    await registerCurrentToken();
  }

  /// Public hook the auth flow calls after login. Forces the current FCM
  /// token to be re-uploaded to the backend so a fresh device→user mapping
  /// exists for push delivery.
  Future<void> registerCurrentToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        // ignore: avoid_print
        print('[push] (re)registering FCM token (len=${token.length})');
        await _registerToken(token);
      } else {
        // ignore: avoid_print
        print('[push] FirebaseMessaging.getToken() returned null');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[push] registerCurrentToken failed: $e');
    }
  }

  void _handleTap(RemoteMessage msg) {
    final route = msg.data['route'] as String?;
    if (route == null || route.isEmpty) return;
    // ignore: avoid_print
    print('[push] tap → $route');

    if (route == '/home' || route == '/') {
      appNavigator?.go('/');
      return;
    }

    // ALWAYS publish to the reactive pending holder — HomeScreen subscribes
    // to it and pushes the deep link once groups are loaded. This works for:
    //   - cold start (appNavigator is null)
    //   - warm tap (appNavigator is ready, user already on /)
    //   - warm tap from another route (user on /tasks/5 etc.)
    // Then go to /, which seats Home at the bottom of the stack so Back from
    // the deep-linked screen returns Home, not the user's previous route.
    PendingDeepLink.instance.set(route);
    appNavigator?.go('/');
  }

  Future<void> _registerToken(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await _client.post(
        ApiConstants.fcmToken,
        data: {
          'token': token,
          'platform': platform,
          'device_label': Platform.isIOS ? 'iOS · Arena OS' : 'Android · Arena OS',
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[push] failed to register token: $e');
    }
  }

  Future<void> _onForeground(RemoteMessage msg) async {
    // ignore: avoid_print
    print('[push] 📨 _onForeground fired. data=${msg.data}, notif=${msg.notification?.title}');

    final notif = msg.notification;

    // Suppress in-app heads-up if the user is already looking at this chat.
    final groupIdStr = msg.data['group_id'];
    final groupId = groupIdStr is String ? int.tryParse(groupIdStr) : null;
    if (ActiveChatTracker.isActive(groupId)) {
      // ignore: avoid_print
      print('[push] suppressed — chat $groupId is open');
      return;
    }

    // Fall back to data fields if the server didn't include a notification
    // block (data-only messages don't auto-display either in background OR
    // foreground). We synthesize one from data.title/body so we always show
    // something useful.
    final title = notif?.title ?? msg.data['title'] as String? ?? 'New message';
    final body = notif?.body ??
        msg.data['body'] as String? ??
        msg.data['sender_name'] as String? ??
        '';

    // ignore: avoid_print
    print('[push] 🔔 showing local notification: title="$title" body="$body"');

    // Carry the deep-link route through as the payload so a foreground tap
    // can navigate (see onDidReceiveNotificationResponse above).
    final route = msg.data['route'] as String?;

    await _local.show(
      msg.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          'Messages',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: route,
    );
  }

  Future<void> deleteToken() async {
    final token = await _messaging.getToken();
    if (token == null) return;
    try {
      await _client.delete(ApiConstants.fcmToken, data: {'token': token});
    } catch (_) {/* best-effort */}
  }
}
