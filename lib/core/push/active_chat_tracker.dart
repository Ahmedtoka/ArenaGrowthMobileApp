/// Tracks which chat group (if any) is currently visible on screen so that
/// foreground push notifications for that same group can be suppressed
/// (you don't need a notification for a message you're literally looking at).
///
/// Used as a plain global (intentionally — push handlers run outside of
/// the widget tree, so a Riverpod provider would require a container handle).
class ActiveChatTracker {
  ActiveChatTracker._();

  static int? _activeGroupId;

  /// Call from `initState` of the conversation screen.
  static void enter(int groupId) {
    _activeGroupId = groupId;
  }

  /// Call from `dispose` of the conversation screen.
  static void leave(int groupId) {
    if (_activeGroupId == groupId) {
      _activeGroupId = null;
    }
  }

  static bool isActive(int? groupId) {
    if (groupId == null) return false;
    return _activeGroupId == groupId;
  }
}
