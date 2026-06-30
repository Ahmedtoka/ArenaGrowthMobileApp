import '../config/env.dart';

/// Centralized API path constants — matches Laravel `routes/api.php`.
///
/// Base URL comes from [Env.apiBaseUrl] (set via --dart-define).
class ApiConstants {
  ApiConstants._();

  /// Base URL with `/api` suffix already included.
  static String get baseUrl => Env.apiBaseUrl;

  // ─── Auth ─────────────────────────────────────────────
  static const String login = '/auth/login';
  static const String logout = '/auth/logout';
  static const String me = '/auth/me';

  // ─── Manager dashboard (read-only, role-aware) ───────
  static const String dashboard = '/team/dashboard';

  // ─── Me / scoped lists ───────────────────────────────
  static const String myGroups = '/team/me/groups';
  static const String myBrands = '/team/me/brands';
  static const String myInbox = '/team/me/inbox';
  static const String myCalendar = '/team/me/calendar';
  static const String myScorecard = '/team/me/scorecard';
  static const String myDuty = '/team/me/duty';
  static const String mySelfTasks = '/team/me/self-tasks';

  // ─── Profile (self-service) ─────────────────────────
  static const String myAvatar = '/team/me/avatar';
  static const String myPassword = '/team/me/password';
  static String userAvatar(int id) => '/team/users/$id/avatar';

  // ─── Attendance (Sprint E.2) ─────────────────────────
  static const String attendanceToday        = '/team/attendance/today';
  static const String attendanceCheckIn      = '/team/attendance/check-in';
  static const String attendanceCheckOut     = '/team/attendance/check-out';
  static const String attendanceBreakStart   = '/team/attendance/break-start';
  static const String attendanceBreakEnd     = '/team/attendance/break-end';
  static const String attendanceAvailability = '/team/attendance/availability';
  static const String attendancePings        = '/team/attendance/pings';

  // ─── FCM ─────────────────────────────────────────────
  static const String fcmTokens = '/team/me/fcm-tokens';
  static const String fcmToken = '/team/me/fcm-token';

  // ─── Users ───────────────────────────────────────────
  static const String users = '/team/users';
  static String user(int id) => '/team/users/$id';

  // ─── Direct messages (1-on-1) ────────────────────────
  static const String dm = '/team/dm';

  // ─── Messages ────────────────────────────────────────
  static String groupMessages(int groupId) => '/team/groups/$groupId/messages';
  static String groupPins(int groupId) => '/team/groups/$groupId/pins';
  static String groupTaskSummary(int groupId) => '/team/groups/$groupId/task-summary';
  static String groupMessageFile(int groupId) => '/team/groups/$groupId/messages/file';
  static String groupMessageVoice(int groupId) => '/team/groups/$groupId/messages/voice';
  static String groupAttachments(int groupId) => '/team/groups/$groupId/attachments';
  static String groupTyping(int groupId) => '/team/groups/$groupId/typing';
  static String groupRead(int groupId) => '/team/groups/$groupId/read';
  static String message(int messageId) => '/team/messages/$messageId';
  static String messageRead(int messageId) => '/team/messages/$messageId/read';
  static String messageMarkRed(int messageId) => '/team/messages/$messageId/mark-red';
  static String messageMarkGreen(int messageId) => '/team/messages/$messageId/mark-green';
  static String messageRevert(int messageId) => '/team/messages/$messageId/revert';
  static String messageSeenBy(int messageId) => '/team/messages/$messageId/seen-by';
  static String messagePlayed(int messageId) => '/team/messages/$messageId/played';
  static String messagePlayedBy(int messageId) => '/team/messages/$messageId/played-by';
  static String messageReact(int messageId) => '/team/messages/$messageId/react';
  static String messagePin(int messageId) => '/team/messages/$messageId/pin';

  // ─── Tasks ───────────────────────────────────────────
  static const String tasks = '/team/tasks';
  // Add-Task form helpers — role-aware deliverables + free deadline sockets.
  static const String taskFormConfig = '/team/tasks/form-config';
  static const String taskAvailableSlots = '/team/tasks/available-slots';
  static String task(int id) => '/team/tasks/$id';
  static String taskOpen(int id) => '/team/tasks/$id/open';
  static String taskStart(int id) => '/team/tasks/$id/start';
  static String taskClarify(int id) => '/team/tasks/$id/request-clarification';
  static String taskClarifyReply(int id) => '/team/tasks/$id/clarification-reply';
  static String taskComplete(int id) => '/team/tasks/$id/complete';
  static String taskDeliverables(int id) => '/team/tasks/$id/deliverables';
  static String taskDeliver(int id) => '/team/tasks/$id/deliverables/deliver';
  // Task chaining — hand off to next stage + fetch the project chain.
  static String taskHandoff(int id) => '/team/tasks/$id/handoff';
  static String taskChain(int id) => '/team/tasks/$id/chain';
  static String taskCompleteWithFile(int id) => '/team/tasks/$id/complete-with-file';
  static String taskApprove(int id) => '/team/tasks/$id/approve';

  // ─── Meetings ────────────────────────────────────────
  static String groupMeetings(int groupId) => '/team/groups/$groupId/meetings';
  static String meetingRsvp(int id) => '/team/meetings/$id/rsvp';
  static String meeting(int id) => '/team/meetings/$id';

  // ─── Polls ───────────────────────────────────────────
  static String groupPolls(int groupId) => '/team/groups/$groupId/polls';
  static String poll(int id) => '/team/polls/$id';
  static String pollVote(int id) => '/team/polls/$id/vote';
  static String pollClose(int id) => '/team/polls/$id/close';

  // ─── Broadcasting auth (for Reverb private/presence channels) ─
  /// NOTE: this lives at host root, NOT under /api. Use Env.apiBaseUrl
  /// stripped of the trailing /api segment when calling.
  static const String broadcastingAuth = '/broadcasting/auth';
}
