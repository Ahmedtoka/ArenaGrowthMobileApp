import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reactive holder for a route that needs to be pushed once the app shell is
/// ready (groups loaded, auth bootstrapped). Used by the push-notification
/// tap handler — it can't push directly on cold start because the chat
/// screen would mount before groups load and show an empty stub.
///
/// HomeScreen watches [pendingDeepLinkProvider] and pushes the route on
/// every change, *after* `groupsControllerProvider` has a value.
class PendingDeepLink extends ChangeNotifier {
  PendingDeepLink._();

  /// Process-wide singleton so non-widget code (the FCM tap handler) can
  /// publish without needing a Ref.
  static final PendingDeepLink instance = PendingDeepLink._();

  String? _route;
  String? get route => _route;

  void set(String route) {
    _route = route;
    notifyListeners();
  }

  /// Atomically read + clear so only the first consumer picks it up.
  String? consume() {
    final v = _route;
    _route = null;
    return v;
  }
}

/// Riverpod-friendly view of the singleton above. HomeScreen watches this
/// to be notified the moment a deep link gets queued by the push service —
/// even when the navigation target is the same location the user is already
/// on (so `nav.go('/')` from `/` doesn't trigger any rebuild on its own).
final pendingDeepLinkProvider =
    ChangeNotifierProvider<PendingDeepLink>((ref) => PendingDeepLink.instance);
