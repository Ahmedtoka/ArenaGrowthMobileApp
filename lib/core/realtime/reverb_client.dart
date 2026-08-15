import 'dart:async';
import 'dart:convert';

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
  // Channels whose _bindChannel() is mid-flight. _bindChannel awaits the token
  // BEFORE it registers in _channels, so two callers (bootstrap + the chat
  // screen, or bootstrap running twice) both used to sail past the
  // `_channels.containsKey` guard and bind the same channel twice. Two
  // overlapping subscribe() calls make the library discard the FIRST one's
  // in-flight auth (see _trySubscribe) — pure waste at best, a lost
  // subscription at worst.
  final Set<String> _binding = {};
  // Channels Pusher has actually ACKed with pusher:subscription_succeeded.
  // This is the only trustworthy "am I really subscribed?" signal: the
  // library's own channel status flips to pendingSubscription on every
  // subscribe() call, so it can't distinguish healthy from stuck.
  final Set<String> _subscribedChannels = {};
  // Channels that were confirmed subscribed at some point. Used to tell a
  // FIRST subscription (no gap to fill) from a RE-subscription after the
  // channel silently died (gap → tell listeners to refetch).
  final Set<String> _everSubscribedChannels = {};
  // When we last sent a subscribe for a channel. The auth round-trip to
  // /broadcasting/auth takes seconds on this backend; re-asserting faster
  // than that cancels the in-flight attempt and the channel never settles.
  final Map<String, DateTime> _lastSubscribeAttempt = {};
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
    _subscribedChannels.clear();
    _lastSubscribeAttempt.clear();
    _client = PusherChannelsClient.websocket(
      options: options,
      connectionErrorHandler: (e, st, refresh) {
        _connected = false;
        // The socket is gone, so every server-side subscription died with it.
        // Drop our ACK bookkeeping so the reconciler re-subscribes (and so a
        // recovered channel is correctly seen as a RE-subscription → gap fill).
        _subscribedChannels.clear();
        _lastSubscribeAttempt.clear();

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

    // A connection-level `pusher:error` is the ONLY thing Pusher sends back
    // when a subscribe carries a bad auth signature — and the library drops
    // it on the floor: it flips an internal `gotPusherError` lifecycle state
    // that NOTHING in the package reads, with no error handler and no log.
    // The result is a subscribe that is answered with total silence. This
    // listener is the only way to see it.
    _client!.pusherErrorEventStream.listen((event) {
      // ignore: avoid_print
      print('[Reverb] 🛑 PUSHER ERROR: ${event.rootObject}');
    });

    // Every raw frame from the server, minus the ping/pong keepalive noise.
    // Shows exactly what Pusher does (or doesn't) reply to a subscribe.
    if (kDebugMode) {
      _client!.eventStream.listen((event) {
        final name = '${event.rootObject['event'] ?? ''}';
        if (name.contains('ping') || name.contains('pong')) return;
        // ignore: avoid_print
        print('[Reverb] ⟵ $name ${event.rootObject['channel'] ?? ''}');
      });
    }

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
    // `_binding` closes the async gap: without it a second caller arriving
    // while the first is still awaiting its token binds the channel twice.
    if (_channels.containsKey(channelName) || _binding.contains(channelName)) {
      return; // already bound / binding
    }

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
    _subscribedChannels.clear();
    _lastSubscribeAttempt.clear();
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
  /// (an earlier subscribe was aborted) → create it; if we have one that Pusher
  /// has NOT ACKed → re-assert it, rate-limited. Channels with a live ACK are
  /// left untouched.
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
        if (!_binding.contains(name)) {
          _bindChannel(name).catchError((_) {});
        }
        continue;
      }
      // Pusher has ACKed this one — leave it ALONE. Re-asserting a healthy
      // subscription every 6s used to fire a /broadcasting/auth POST per
      // channel per tick (20+/min/device against a backend answering in ~5s)
      // and, worse, each new subscribe() invalidates the previous one's
      // in-flight auth inside the library — so a slow auth response could be
      // cancelled forever and the channel would never subscribe at all. That
      // is silent: no error, no event, just a chat that never updates.
      if (_subscribedChannels.contains(name)) continue;

      // Unconfirmed: retry, but no faster than the auth round-trip.
      final last = _lastSubscribeAttempt[name];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 15)) {
        continue;
      }
      // ignore: avoid_print
      print('[Reverb] ⚠️ $name not confirmed subscribed — re-asserting');
      _trySubscribe(channel, name);
    }
  }

  /// Sends a subscribe for [channel], guarding the one condition the library
  /// swallows without a trace: no socket id yet (it returns from
  /// `setAuthKeyFromDelegate` before even calling the auth endpoint, so the
  /// channel sits idle forever and the logs look identical to a healthy one).
  void _trySubscribe(PrivateChannel channel, String channelName) {
    final socketId = _client?.socketId;
    if (socketId == null) {
      // ignore: avoid_print
      print('[Reverb] ⏳ no socketId yet — deferring subscribe for $channelName');
      return;
    }
    _lastSubscribeAttempt[channelName] = DateTime.now();
    // ignore: avoid_print
    print('[Reverb] → subscribe $channelName (socket=$socketId)');
    try {
      channel.subscribeIfNotUnsubscribed();
    } catch (e) {
      // ignore: avoid_print
      print('[Reverb] subscribe threw for $channelName: $e');
    }
  }

  Future<void> _bindChannel(String channelName) async {
    if (_client == null ||
        _channels.containsKey(channelName) ||
        _binding.contains(channelName)) {
      return;
    }
    _binding.add(channelName);
    try {
      await _doBindChannel(channelName);
    } finally {
      _binding.remove(channelName);
    }
  }

  Future<void> _doBindChannel(String channelName) async {
    final token = await _storage.getToken() ?? '';
    if (_client == null || _channels.containsKey(channelName)) return;
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
        // Same as the library's default parser, plus a log line: this is the
        // ONLY place we can see the auth endpoint's actual response, and
        // "did /broadcasting/auth answer, and with what?" is the first
        // question whenever realtime is silent.
        parser: (response) {
          final decoded = jsonDecode(response.body);
          final auth = decoded is Map ? decoded['auth'] : null;
          if (auth is! String) {
            throw StateError(
              'auth endpoint returned no "auth" key: ${response.body}',
            );
          }
          // Laravel returns "<app_key>:<hmac>". The app key it signs with
          // comes from the SERVER's .env; the key we opened the socket with
          // comes from --dart-define. When those disagree, /broadcasting/auth
          // still answers 200 — but Pusher rejects the subscribe as an
          // invalid signature and (see pusherErrorEventStream above) the
          // failure is otherwise completely invisible.
          final signingKey = auth.split(':').first;
          // ignore: avoid_print
          print('[Reverb] auth ${response.statusCode} for $channelName '
              '(signed by key=$signingKey)');
          if (signingKey != Env.reverbAppKey) {
            // ignore: avoid_print
            print('[Reverb] 🛑 APP KEY MISMATCH — server signs with '
                '"$signingKey" but this build connected with '
                '"${Env.reverbAppKey}". Every subscribe will be rejected. '
                'Fix the backend .env (PUSHER_APP_KEY/SECRET) or rebuild the '
                'app with --dart-define=REVERB_APP_KEY=$signingKey');
          }
          return PrivateChannelAuthorizationData(authKey: auth);
        },
        // WITHOUT this, a rejected /broadcasting/auth (expired token, 403 from
        // channels.php, HTML error page) throws inside the library and is
        // swallowed — the channel silently never subscribes and the logs look
        // IDENTICAL to a healthy-but-quiet chat. This is the single most
        // common cause of "connected, but no messages arrive".
        onAuthFailed: (exception, trace) {
          // PusherChannelsException has no toString override — printing it
          // raw gives "Instance of '...'", which hides the response body.
          final detail = exception is PusherChannelsException
              ? exception.message
              : '$exception';
          // ignore: avoid_print
          print('[Reverb] ❌ AUTH FAILED for $channelName: $detail');
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
          // Was this channel confirmed before and then lost? Then we were
          // deaf for a while and Pusher replays nothing — tell the open chat
          // and the chats list to refetch. This is what removes the "I have
          // to leave the chat and come back to see the message" step.
          final recovered = _everSubscribedChannels.contains(channelName) &&
              !_subscribedChannels.contains(channelName);
          _subscribedChannels.add(channelName);
          _everSubscribedChannels.add(channelName);
          if (recovered) {
            _eventController.add(ReverbEvent(
              channelName: channelName,
              eventName: '__reconnected',
              rawData: '',
            ),);
          }
        } else if (name.contains('subscription_error')) {
          _subscribedChannels.remove(channelName);
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

    // Register BEFORE subscribing so the reconciler sees this channel as
    // bound (and doesn't bind a second one) the moment it ticks.
    _channels[channelName] = channel;
    _channelSubs[channelName] = subs;
    _trySubscribe(channel, channelName);
  }

  Future<void> unsubscribeFromBrandGroup(int groupId) async {
    final channelName = 'private-brand-group.$groupId';
    final subs = _channelSubs.remove(channelName) ?? const [];
    for (final s in subs) {
      await s.cancel();
    }
    final channel = _channels.remove(channelName);
    _subscribedChannels.remove(channelName);
    _everSubscribedChannels.remove(channelName);
    _lastSubscribeAttempt.remove(channelName);
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
    _binding.clear();
    _subscribedChannels.clear();
    _everSubscribedChannels.clear();
    _lastSubscribeAttempt.clear();
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
