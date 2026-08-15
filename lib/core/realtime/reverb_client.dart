import 'dart:async';

import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';
import '../storage/secure_storage.dart';

/// Wraps `dart_pusher_channels` for Laravel Reverb.
///
/// Reverb implements the Pusher protocol, so we point a Pusher-compatible
/// client at our self-hosted host:port. Private channels are authorized via
/// the Sanctum-backed `/broadcasting/auth` endpoint.
class ReverbClient {
  final SecureStorage _storage;

  PusherChannelsClient? _client;
  final Map<String, PrivateChannel> _channels = {};
  final Map<String, List<StreamSubscription>> _channelSubs = {};
  // Every group we've been asked to subscribe to — survives socket drops so we
  // can re-subscribe them all when the connection is (re)established.
  final Set<int> _subscribedGroups = {};
  bool _connecting = false;
  bool _connected = false;
  bool _everConnected = false;
  // Last time the library's own refresh() reconnect was attempted — used by
  // the reconciler to decide when to give up on refresh and hard-rebuild.
  DateTime? _lastRefreshAttempt;
  // Backoff guard: ensures only ONE reconnect is pending at a time so a
  // failing connection (e.g. no local Reverb server during dev) becomes a
  // quiet ~3s heartbeat instead of a tight retry storm that floods the log.
  bool _reconnectScheduled = false;
  DateTime? _lastErrorLog;
  // Self-healing: periodically re-asserts every channel subscription so a
  // silently-failed subscribe (auth hiccup, mid-handshake drop) recovers on
  // its own within a few seconds — this is what fixes "one device never gets
  // messages" without restarting the app.
  Timer? _reconciler;

  final _eventController = StreamController<ReverbEvent>.broadcast();

  /// All events from any subscribed channel are emitted here. Filter on
  /// `event.channelName` + `event.eventName` in your listener.
  Stream<ReverbEvent> get events => _eventController.stream;

  bool get isConnected => _connected;

  ReverbClient(this._storage);

  /// Establishes the WebSocket connection. Safe to call multiple times.
  /// Coalesces concurrent connect() calls: while a connection is in flight,
  /// every caller awaits the SAME future instead of returning early (which
  /// used to leave `_client` null for callers 2..N → "subscribe aborted").
  Future<void>? _connectFuture;

  Future<void> connect() async {
    if (_connected) return;
    if (_connectFuture != null) return _connectFuture;
    _connectFuture = _doConnect();
    try {
      await _connectFuture;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> _doConnect() async {
    // ignore: avoid_print
    print('[Reverb] >>> _doConnect() (connected=$_connected)');
    _connecting = true;

    final token = await _storage.getToken();
    if (token == null || token.isEmpty) {
      // ignore: avoid_print
      print('[Reverb] no token yet — skipping connect');
      _connecting = false;
      return;
    }

    // Normalize scheme — accept http/https as aliases for ws/wss to be
    // forgiving of misconfigured --dart-define values.
    final raw = Env.reverbScheme.toLowerCase();
    final scheme = (raw == 'http' || raw == 'ws')
        ? 'ws'
        : (raw == 'https' || raw == 'wss')
            ? 'wss'
            : 'ws';

    final options = PusherChannelsOptions.fromHost(
      scheme: scheme,
      host: Env.reverbHost,
      port: Env.reverbPort,
      key: Env.reverbAppKey,
    );

    // ignore: avoid_print
    print(
        '[Reverb] connecting to $scheme://${Env.reverbHost}:${Env.reverbPort} key=${Env.reverbAppKey}',);

    _client?.dispose();
    // The old client is gone — every channel object bound to it is now DEAD.
    // Clear the registry so (a) the rebind in onConnectionEstablished kicks
    // in (it requires _channels.isEmpty) and (b) _reconcile() doesn't keep
    // "re-asserting" corpses. Without this, a network blip + reconnect left
    // the app subscribed to NOTHING until a full restart — messages and
    // typing stopped arriving silently.
    for (final subs in _channelSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _channelSubs.clear();
    _channels.clear();
    _client = PusherChannelsClient.websocket(
      options: options,
      connectionErrorHandler: (e, st, refresh) {
        _connected = false;

        // Log at most once every ~5s so a downed server (common in local
        // dev — no Reverb running) doesn't bury the console.
        final now = DateTime.now();
        if (kDebugMode &&
            (_lastErrorLog == null ||
                now.difference(_lastErrorLog!) >
                    const Duration(seconds: 5))) {
          _lastErrorLog = now;
          // ignore: avoid_print
          print('[Reverb] connection error (retrying in background): $e');
        }

        // CRITICAL: `refresh()` is the library's OWN reconnect mechanism — it
        // re-establishes the SAME client and re-subscribes its channels. But
        // calling it on EVERY error tight-loops (fail → refresh → fail …).
        // Debounce so only one reconnect is in flight, on a 3s backoff.
        if (_reconnectScheduled) return;
        _reconnectScheduled = true;
        Future.delayed(const Duration(seconds: 3), () {
          _reconnectScheduled = false;
          _lastRefreshAttempt = DateTime.now();
          try {
            refresh();
          } catch (_) {/* best effort */}
        });
      },
    );

    _client!.onConnectionEstablished.listen((_) {
      final wasReconnect = _everConnected;
      _connected = true;
      _everConnected = true;
      // ignore: avoid_print
      print('[Reverb] connection established (reconnect=$wasReconnect, '
          'channels=${_channels.length})');
      if (wasReconnect && _subscribedGroups.isNotEmpty) {
        if (_channels.isEmpty) {
          // Brand-new client (we recreated it) — full rebind.
          _resubscribeAll();
        } else {
          // Same client refreshed — the library re-subscribes its own
          // channels; we just need to fill the message gap (Pusher does not
          // replay anything sent while we were offline).
          _emitReconnected();
        }
      }
      _startReconciler();
    });

    try {
      await _client!.connect();
      _connected = true;
      // ignore: avoid_print
      print('[Reverb] connect() awaited OK');
    } catch (e) {
      // ignore: avoid_print
      print('[Reverb] connect threw: $e');
    } finally {
      _connecting = false;
    }
  }

  /// Subscribe to a brand-group private channel. Binds to the specific
  /// events we care about (MessageSent, TypingChanged, etc.).
  Future<void> subscribeToBrandGroup(int groupId) async {
    _subscribedGroups.add(groupId);
    await connect();
    if (_client == null) return;

    final channelName = 'private-brand-group.$groupId';
    if (_channels.containsKey(channelName)) return; // already bound

    await _bindChannel(channelName);
  }

  /// Re-create channel bindings for every tracked group. Called on each
  /// (re)connection so a dropped socket doesn't leave the device deaf.
  void _resubscribeAll() {
    // Tear down stale bindings first.
    for (final subs in _channelSubs.values) {
      for (final s in subs) {
        s.cancel();
      }
    }
    _channels.clear();
    _channelSubs.clear();
    for (final id in _subscribedGroups) {
      _bindChannel('private-brand-group.$id').catchError((_) {});
    }
    _emitReconnected();
  }

  /// Tell listeners we just recovered from a dropped connection. Pusher does
  /// NOT replay messages sent while we were offline, so open chats + the
  /// chats list refetch to fill the gap ("messages missing until reopen").
  void _emitReconnected() {
    for (final id in _subscribedGroups) {
      _eventController.add(ReverbEvent(
        channelName: 'private-brand-group.$id',
        eventName: '__reconnected',
        rawData: '',
      ),);
    }
  }

  /// Starts the periodic self-healing loop (idempotent — only one runs).
  void _startReconciler() {
    if (_reconciler != null) return;
    _reconciler = Timer.periodic(const Duration(seconds: 6), (_) => _reconcile());
  }

  /// For every group we SHOULD be subscribed to: if we never created a channel
  /// (an earlier subscribe was aborted) → create it; if we have one → re-assert
  /// the subscription (a no-op when already subscribed, a recovery when not).
  void _reconcile() {
    if (_client == null) return;
    if (!_connected) {
      // Connection dropped. The library's refresh() (kicked off from the
      // error handler) is the preferred recovery — it keeps the same client
      // and re-subscribes its channels itself. Only if refresh has gone
      // quiet for >15s (gave up / silently dead) do we hard-rebuild with a
      // brand-new client, which clears + rebinds everything from scratch.
      final last = _lastRefreshAttempt;
      final refreshGaveUp = last == null ||
          DateTime.now().difference(last) > const Duration(seconds: 15);
      if (refreshGaveUp) {
        // ignore: avoid_print
        print('[Reverb] reconciler: refresh stalled — hard-rebuilding client');
        connect().catchError((_) {});
      }
      return;
    }
    for (final id in _subscribedGroups) {
      final name = 'private-brand-group.$id';
      final channel = _channels[name];
      if (channel == null) {
        _bindChannel(name).catchError((_) {});
      } else {
        try {
          channel.subscribeIfNotUnsubscribed();
        } catch (_) {/* ignore */}
      }
    }
  }

  Future<void> _bindChannel(String channelName) async {
    if (_client == null || _channels.containsKey(channelName)) return;

    final token = await _storage.getToken() ?? '';
    const apiBase = Env.apiBaseUrl;
    final hostBase = apiBase.endsWith('/api')
        ? apiBase.substring(0, apiBase.length - 4)
        : apiBase;

    // ignore: avoid_print
    print('[Reverb] subscribing: $channelName via $hostBase/broadcasting/auth (token len=${token.length})');

    final channel = _client!.privateChannel(
      channelName,
      authorizationDelegate:
          EndpointAuthorizableChannelTokenAuthorizationDelegate
              .forPrivateChannel(
        authorizationEndpoint: Uri.parse('$hostBase/broadcasting/auth'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
        // WITHOUT this, a rejected /broadcasting/auth (expired token, 403 from
        // channels.php, HTML error page) throws inside the library and is
        // swallowed — the channel silently never subscribes and the logs look
        // IDENTICAL to a healthy-but-quiet chat. This is the single most
        // common cause of "connected, but no messages arrive".
        onAuthFailed: (exception, trace) {
          // ignore: avoid_print
          print('[Reverb] ❌ AUTH FAILED for $channelName: $exception');
        },
      ),
    );

    // Bind to the events we care about and forward them.
    final subs = <StreamSubscription>[];

    // Subscription lifecycle — proves whether Reverb actually ACCEPTED the
    // subscribe, as opposed to us merely having sent one.
    try {
      subs.add(channel.bindToAll().listen((event) {
        final name = event.name;
        if (name.contains('subscription_succeeded')) {
          // ignore: avoid_print
          print('[Reverb] ✅ SUBSCRIBED to $channelName');
        } else if (name.contains('subscription_error')) {
          // ignore: avoid_print
          print('[Reverb] ❌ SUBSCRIPTION ERROR on $channelName: ${event.data}');
        } else if (name.startsWith('pusher:') || name.startsWith('pusher_internal:')) {
          // protocol chatter (ping/pong) — ignore
        } else {
          // Any application event, including ones we don't explicitly bind.
          // If a name shows up here that we never forward, that's the bug.
          // ignore: avoid_print
          print('[Reverb] 👀 event "$name" on $channelName');
        }
      }),);
    } catch (e) {
      // ignore: avoid_print
      print('[Reverb] bindToAll threw: $e');
    }

    for (final evt in const ['MessageSent', 'TypingChanged', 'MessageDeleted', 'MessageUpdated']) {
      try {
        final sub = channel.bind(evt).listen(
          (event) {
            // ignore: avoid_print
            print('[Reverb] 📩 $evt on $channelName: ${event.data}');
            _eventController.add(ReverbEvent(
              channelName: channelName,
              eventName: evt,
              rawData: event.data ?? '',
            ),);
          },
          onError: (e) {
            // ignore: avoid_print
            print('[Reverb] bind error on $evt: $e');
          },
        );
        subs.add(sub);
      } catch (e) {
        // ignore: avoid_print
        print('[Reverb] bind threw for $evt: $e');
      }
    }

    channel.subscribeIfNotUnsubscribed();
    // ignore: avoid_print
    print('[Reverb] subscribeIfNotUnsubscribed() called for $channelName');
    _channels[channelName] = channel;
    _channelSubs[channelName] = subs;
  }

  Future<void> unsubscribeFromBrandGroup(int groupId) async {
    final channelName = 'private-brand-group.$groupId';
    final subs = _channelSubs.remove(channelName) ?? const [];
    for (final s in subs) {
      await s.cancel();
    }
    final channel = _channels.remove(channelName);
    channel?.unsubscribe();
    if (kDebugMode) debugPrint('[Reverb] unsubscribed: $channelName');
  }

  Future<void> disconnect() async {
    _reconciler?.cancel();
    _reconciler = null;
    for (final subs in _channelSubs.values) {
      for (final s in subs) {
        await s.cancel();
      }
    }
    _channelSubs.clear();
    _channels.clear();
    _client?.disconnect();
    _connected = false;
  }

  Future<void> dispose() async {
    await disconnect();
    _client?.dispose();
    _client = null;
    await _eventController.close();
  }
}

/// Decoded Reverb event passed through the stream.
class ReverbEvent {
  final String channelName;
  final String eventName;
  final String rawData;

  const ReverbEvent({
    required this.channelName,
    required this.eventName,
    required this.rawData,
  });
}
