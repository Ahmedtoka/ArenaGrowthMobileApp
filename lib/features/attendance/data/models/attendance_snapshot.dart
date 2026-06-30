/// The four possible employee states surfaced by the dashboard tile.
///
///   off    — not checked in (out of office)
///   active — checked in, ready to receive tasks
///   break  — checked in, on a short break
///   away   — checked in, NOT taking new tasks (meeting, with client, etc.)
///
/// `away` is intentionally distinct from `off`: the user is still at work
/// (clock is running) but the dispatcher should skip them.
enum AttendanceStatus { off, active, breakTime, away }

extension AttendanceStatusX on AttendanceStatus {
  String get apiValue => switch (this) {
        AttendanceStatus.off => 'off',
        AttendanceStatus.active => 'active',
        AttendanceStatus.breakTime => 'break',
        AttendanceStatus.away => 'away',
      };

  static AttendanceStatus fromApi(String? value) => switch (value) {
        'active' => AttendanceStatus.active,
        'break' => AttendanceStatus.breakTime,
        'away' => AttendanceStatus.away,
        _ => AttendanceStatus.off, // covers 'off' + legacy 'away' string
      };

  /// True for any state where the user is currently checked-in.
  bool get isAtWork => this != AttendanceStatus.off;
}

/// Last raw event the server logged for the current user. We only need a
/// few fields for the UI (kind, when, and whether a registered location
/// was matched).
class AttendanceLastEvent {
  final int id;
  final String kind;
  final DateTime? occurredAt;
  final bool isMatched;
  final String? matchedLocationName;

  const AttendanceLastEvent({
    required this.id,
    required this.kind,
    required this.occurredAt,
    required this.isMatched,
    required this.matchedLocationName,
  });

  factory AttendanceLastEvent.fromJson(Map<String, dynamic> json) =>
      AttendanceLastEvent(
        id: (json['id'] as num).toInt(),
        kind: json['kind'] as String? ?? 'check_in',
        occurredAt: DateTime.tryParse(json['occurred_at'] as String? ?? ''),
        isMatched: json['is_matched'] == true,
        matchedLocationName: json['matched_location_name'] as String?,
      );
}

/// Mirror of the JSON returned by `/api/team/attendance/today`.
class AttendanceSnapshot {
  final AttendanceStatus status;
  final bool isOnDuty;
  final String? awayReason;
  final int? openSessionId;
  final DateTime? openSessionStartedAt;
  final int todayMinutes;
  final AttendanceLastEvent? lastEvent;

  const AttendanceSnapshot({
    required this.status,
    required this.isOnDuty,
    required this.awayReason,
    required this.openSessionId,
    required this.openSessionStartedAt,
    required this.todayMinutes,
    required this.lastEvent,
  });

  static const AttendanceSnapshot empty = AttendanceSnapshot(
    status: AttendanceStatus.off,
    isOnDuty: false,
    awayReason: null,
    openSessionId: null,
    openSessionStartedAt: null,
    todayMinutes: 0,
    lastEvent: null,
  );

  factory AttendanceSnapshot.fromJson(Map<String, dynamic> json) =>
      AttendanceSnapshot(
        status: AttendanceStatusX.fromApi(json['status'] as String?),
        isOnDuty: json['is_on_duty'] == true,
        awayReason: json['away_reason'] as String?,
        openSessionId: (json['open_session_id'] as num?)?.toInt(),
        openSessionStartedAt: DateTime.tryParse(
          json['open_session_started_at'] as String? ?? '',
        ),
        todayMinutes: (json['today_minutes'] as num?)?.toInt() ?? 0,
        lastEvent: json['last_event'] is Map<String, dynamic>
            ? AttendanceLastEvent.fromJson(
                json['last_event'] as Map<String, dynamic>,
              )
            : null,
      );

  /// Formatted "9h 42m" / "42m" for the today-hours counter.
  String get todayHoursLabel {
    final h = todayMinutes ~/ 60;
    final m = todayMinutes % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}
